#![no_std]
#![no_main]

use core::{
    arch::global_asm,
    fmt::{self, Write},
    panic::PanicInfo,
    sync::atomic::{compiler_fence, Ordering},
};

use bootrom_pac;

mod aux;
mod dpcd;
mod edid;
mod link_training;
mod main_link;
mod mock_sink;
mod serialout;
mod video;

use aux::AuxCh;
use main_link::MainLink;
use mock_sink::MockSink;
use serialout::SerialOut;
use video::{Video, VideoConfig};

#[allow(unused_imports)]
use riscv::asm;

global_asm!(
    r#"
.section .isr_vector,"ax",@progbits
    j _start
.section .text,"ax",@progbits
_start:
    la sp, ramend
    addi sp, sp, -4
    csrw mstatus, zero
    csrw mip, zero
    csrw mie, zero
    csrw mtvec, zero
    j start_rust
"#
);

extern "C" {
    static mut _bss_start: u32;
    static mut _bss_end: u32;
    static mut _data_start: u32;
    static mut _data_end: u32;
    static _data_rom_start: u32;
}

#[no_mangle]
pub unsafe extern "C" fn trap_handler() {
    loop {}
}

#[no_mangle]
pub unsafe extern "C" fn init() {
    let mut bss: *mut u32 = &mut _bss_start;
    let bss_end: *mut u32 = &mut _bss_end;
    while bss < bss_end {
        core::ptr::write_volatile(bss, 0);
        bss = bss.offset(1);
    }
    let mut data: *mut u32 = &mut _data_start;
    let data_end: *mut u32 = &mut _data_end;
    let mut data_rom: *const u32 = &_data_rom_start;
    while data < data_end {
        core::ptr::write_volatile(data, core::ptr::read_volatile(data_rom));
        data_rom = data_rom.offset(1);
        data = data.offset(1);
    }
    compiler_fence(Ordering::SeqCst);
}

#[no_mangle]
pub unsafe extern "C" fn start_rust() {
    init();
    main();
}

// ---------------------------------------------------------------------------
// Globals.
// ---------------------------------------------------------------------------

static mut SYSTEM: Option<bootrom_pac::SYSTEM> = None;
static mut SERIAL_OUT: Option<SerialOut<bootrom_pac::SYSTEM_SERIALOUT>> = None;

fn get_cpu_id() -> u32 {
    unsafe {
        SYSTEM
            .as_mut()
            .map(|s| s.id.read().bits())
            .unwrap_or(0xFFFF_FFFF)
    }
}

fn write_system_out(value: u32) {
    unsafe {
        if let Some(system) = SYSTEM.as_mut() {
            system.out.write(|w| w.bits(value));
        }
    }
}

fn read_hpd_level() -> bool {
    unsafe {
        SYSTEM
            .as_mut()
            .map(|s| s.hpd.read().bits() & 0x1 != 0)
            .unwrap_or(false)
    }
}

fn read_hpd_event_plug() -> bool {
    unsafe {
        SYSTEM
            .as_mut()
            .map(|s| s.hpd.read().bits() & 0x2 != 0)
            .unwrap_or(false)
    }
}

fn clear_hpd_events() {
    unsafe {
        if let Some(system) = SYSTEM.as_mut() {
            system.hpd.write(|w| w.bits(0b110));
        }
    }
}

fn print_fmt(args: fmt::Arguments, line_end: bool) {
    unsafe {
        if let Some(serial_out) = SERIAL_OUT.as_mut() {
            let _ = serial_out.write_fmt(args);
            if line_end {
                let _ = writeln!(serial_out);
            }
        }
    }
}

macro_rules! print {
    ($($arg:tt)*) => (print_fmt(format_args!($($arg)*), false));
}
macro_rules! println {
    ($($arg:tt)*) => (print_fmt(format_args!($($arg)*), true));
}

#[panic_handler]
fn panic(info: &PanicInfo) -> ! {
    println!("Panic: {}", info);
    write_system_out(0x0000_0001);
    loop {}
}

// ---------------------------------------------------------------------------
// Source-side scenario.
// ---------------------------------------------------------------------------

// Active lane count for this build. 480p (27 Mpix) fits 1 lane;
// the 1080p60 profile uses all 4.
#[cfg(not(feature = "lanes4"))]
const LANE_COUNT: u8 = 1;
#[cfg(feature = "lanes4")]
const LANE_COUNT: u8 = 4;

fn source_process(aux: &AuxCh, ml: &MainLink, vid: &mut Video) {
    println!("[SRC] waiting for HPD");
    while !read_hpd_level() {}
    if read_hpd_event_plug() {
        println!("[SRC] HPD plug observed");
        clear_hpd_events();
    }

    // Phase A reads (still useful as integration smoke). A real monitor
    // may need some time after HPD before its AUX replier is awake, so
    // retry with a delay and report the detailed failure cause of each
    // attempt (Timeout with rx_count == 0 means the sink never answered
    // at all -> electrical / polarity problem; rx_count > 0 means bytes
    // arrived but the reply could not be decoded).
    let mut buf = [0u8; 16];
    let mut dpcd_ok = false;
    for attempt in 0..10u32 {
        match dpcd::read_block(aux, dpcd::DPCD_REV, &mut buf) {
            Ok(_) => {
                println!("[SRC] DPCD[0..]: {:02X?}", &buf[..16]);
                dpcd_ok = true;
                break;
            }
            Err(e) => {
                println!(
                    "[SRC] DPCD read attempt {} failed: {:?} (rx_count={})",
                    attempt,
                    e,
                    aux.rx_count()
                );
                // ~10 ms at 27 MHz between attempts.
                for _ in 0..90_000 {
                    unsafe { core::arch::asm!("nop") };
                }
            }
        }
    }
    if !dpcd_ok {
        println!("[SRC] giving up: AUX/DPCD unreachable");
        write_system_out(0x0000_0002);
        return;
    }

    // Dump the monitor's EDID so we can check which modes it actually
    // accepts (the link runs error-free but the monitor reports "no
    // video input" — a rejected timing is one of the few remaining
    // explanations).
    let mut edid_buf = [0u8; 128];
    for block in 0..2u8 {
        match edid::read_edid(aux, block * 128, &mut edid_buf) {
            Ok(()) => {
                for row in 0..8 {
                    println!(
                        "[SRC] EDID {:02X}: {:02X?}",
                        block as usize * 128 + row * 16,
                        &edid_buf[row * 16..row * 16 + 16]
                    );
                }
            }
            Err(e) => {
                println!(
                    "[SRC] EDID block {} read failed: {:?} (rx_count={})",
                    block,
                    e,
                    aux.rx_count()
                );
            }
        }
    }

    // Phase C link training. Training on the real monitor is
    // intermittent (EQ typically needs all 5 iterations; occasionally
    // it misses, and right after the EDID I2C burst the sink's AUX can
    // be slow to answer), so retry the whole sequence a few times with
    // a breather in between.
    let mut stats = None;
    for attempt in 0..5u32 {
        match link_training::run(aux, ml, LANE_COUNT) {
            Ok(s) => {
                println!(
                    "[SRC] link training done (attempt={}, cr_iters={}, eq_iters={})",
                    attempt, s.cr_iters, s.eq_iters
                );
                stats = Some(s);
                break;
            }
            Err(e) => {
                println!("[SRC] link training attempt {} failed: {:?}", attempt, e);
                // ~50 ms at 27 MHz before retraining from scratch.
                for _ in 0..450_000 {
                    unsafe { core::arch::asm!("nop") };
                }
            }
        }
    }
    let stats = match stats {
        Some(s) => s,
        None => {
            println!("[SRC] link training failed permanently");
            write_system_out(0x0000_0003);
            return;
        }
    };

    // Phase D: configure MSA and enable the video pipeline.
    // 4-lane sim profile: miniature version of the 1080p60 structure.
    // 64x16 active in an 88x24 raster at the 12/11 rate ratio:
    // B = 48 bytes/lane/line, tu_active = 44 -> W = 64 + 4 = 68
    // symbols, line = 88 * 12/11 = 96 symbols/lane.
    #[cfg(all(not(feature = "board"), feature = "lanes4"))]
    let cfg = VideoConfig {
        htotal:    88,
        vtotal:    24,
        hstart:    16,
        vstart:    8,
        hwidth:    64,
        vheight:   16,
        hsw:       4,
        hsp:       false,
        vsw:       2,
        vsp:       false,
        mvid:      0x7555, // round(0x8000 * 11 / 12)
        nvid:      0x8000,
        misc0:     0x21,
        misc1:     0x00,
        tu_active: 44,
    };
    // Sim profile: exercises the half-rate path (1 pixel = 6 link
    // symbols, tu_active = 32) that the board now uses. 64x16 active in
    // an 80x24 raster: B = 192 bytes/line -> 6 full TUs (384 symbols),
    // line = 480 symbols, hblank window = 96.
    #[cfg(all(not(feature = "board"), not(feature = "lanes4")))]
    let cfg = VideoConfig {
        htotal:    80,
        vtotal:    24,
        hstart:    16,
        vstart:    8,
        hwidth:    64,
        vheight:   16,
        hsw:       4,
        hsp:       false,
        vsw:       2,
        vsp:       false,
        mvid:      0x1555, // 1/6 against Nvid = 0x8000
        nvid:      0x8000,
        misc0:     0x21, // sync clock, 8 bpc RGB (Table 2-45)
        misc1:     0x00,
        tu_active: 32,
    };
    // Board profile: CEA-861 720x480p @ 59.94 (VIC 2/3), the exact
    // 27 MHz mode advertised in the monitor's EDID extension block
    // (the Philips 242P6V rejects timings outside its discrete mode
    // table). Half-rate: 1 pixel = 6 link symbols (162/27 = 6),
    // tu_active = 32. 858x525 raster, hsync 62 + hback 60, vsync 6 +
    // vback 30, both sync polarities negative. Mvid/Nvid = 27/162 =
    // 1/6 with the conventional Nvid = 0x8000.
    #[cfg(feature = "board")]
    let cfg = VideoConfig {
        htotal:    858,
        vtotal:    525,
        hstart:    122, // HSW 62 + HBACK 60
        vstart:    36,  // VSW 6 + VBACK 30
        hwidth:    720,
        vheight:   480,
        hsw:       62,
        hsp:       true, // negative sync polarity
        vsw:       6,
        vsp:       true,
        mvid:      0x1555, // round(0x8000 / 6)
        nvid:      0x8000,
        misc0:     0x21, // sync clock, 8 bpc RGB (Table 2-45)
        misc1:     0x00,
        tu_active: 32,
    };
    // Line-accounting rate: LS_clk/pixel_clk as a fraction, plus lanes.
    #[cfg(feature = "lanes4")]
    vid.set_rate(12, 11, 4);
    #[cfg(not(feature = "lanes4"))]
    vid.set_rate(6, 1, 1);
    vid.setup_and_enable(&cfg);
    println!("[SRC] video pipeline enabled");

    // Encode iteration counts in upper bits of cpu_io_out and signal done.
    let v = 0x0000_0001
        | ((stats.cr_iters & 0xFF) << 8)
        | ((stats.eq_iters & 0xFF) << 16);
    write_system_out(v);

    // Phase E: keep polling the link/sink status field (DPCD 0x200-0x205)
    // so a post-training failure is visible on the UART. SYNC is
    // SINK_STATUS bit0 (RECEIVE_PORT_0_STATUS): 1 means the sink is in
    // sync with our main-link stream, so "training done but no picture"
    // splits into signal-level problems (CR/EQ/SYM drop) vs stream
    // formatting problems (all 1 but SYNC=0 or the monitor still blank).
    println!("[SRC] monitoring link status (DPCD 200h-205h)");
    let mut prev = [0u8; 6];
    let mut have_prev = false;
    let mut beat: u32 = 0;
    loop {
        // ~1 s between polls (same nop scale as the retry delay above).
        for _ in 0..9_000_000u32 {
            unsafe { core::arch::asm!("nop") };
        }
        let mut st = [0u8; 6];
        match dpcd::read_block(aux, dpcd::SINK_COUNT, &mut st) {
            Ok(_) => {
                // Symbol error counter (DPCD 210h-211h): the definitive
                // signal-integrity probe. A trained link that still
                // accumulates symbol errors has an electrical problem; a
                // clean zero here shifts suspicion to stream formatting.
                let mut ec = [0u8; 2];
                let (err_valid, err_count) =
                    match dpcd::read_block(aux, dpcd::SYMBOL_ERROR_COUNT_LANE0, &mut ec) {
                        Ok(_) => (ec[1] & 0x80 != 0, (((ec[1] & 0x7F) as u16) << 8) | ec[0] as u16),
                        Err(_) => (false, 0xFFFF),
                    };
                if !have_prev || st != prev || err_count != 0 || beat % 10 == 0 {
                    let lane = st[2];
                    println!(
                        "[SRC] status {:02X?} CR={} EQ={} SYM={} ALIGN={} SYNC={} IRQ={:02X} ERR={}{}",
                        st,
                        lane & 1,
                        (lane >> 1) & 1,
                        (lane >> 2) & 1,
                        st[4] & 1,
                        st[5] & 1,
                        st[1],
                        err_count,
                        if err_valid { "" } else { "(inval)" },
                    );
                }
                prev = st;
                have_prev = true;
            }
            Err(e) => {
                println!(
                    "[SRC] status read failed: {:?} (rx_count={})",
                    e,
                    aux.rx_count()
                );
            }
        }
        beat = beat.wrapping_add(1);
    }
}

fn sink_process(aux: &AuxCh) {
    println!("[SNK] mock sink ready");
    let mut sink = MockSink::new();
    let _ = sink.run(aux);
    println!("[SNK] training observed (TRAINING_PATTERN_SET cleared)");
    write_system_out(0x0000_0001);
}

#[no_mangle]
pub extern "C" fn main() -> ! {
    let peripherals = bootrom_pac::Peripherals::take().unwrap();
    unsafe {
        SYSTEM = Some(peripherals.SYSTEM);
    }
    let serial_out = SerialOut::<bootrom_pac::SYSTEM_SERIALOUT>::init(peripherals.SYSTEM_SERIALOUT);
    unsafe {
        SERIAL_OUT = Some(serial_out);
    }

    let cpu_id = get_cpu_id();
    let aux = AuxCh::new(peripherals.AUX_CH);
    let ml = MainLink::new(peripherals.MAIN_LINK);
    let mut vid = Video::new(peripherals.VIDEO);
    println!("[CPU{}] phase D boot", cpu_id);

    match cpu_id {
        0 => source_process(&aux, &ml, &mut vid),
        1 => sink_process(&aux),
        other => {
            println!("[CPU?] unknown id {:08X}", other);
            write_system_out(0x0000_0001);
        }
    }

    loop {}
}
