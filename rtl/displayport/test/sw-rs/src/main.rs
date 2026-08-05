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
#[cfg(feature = "typec")]
mod fusb302;
#[cfg(feature = "typec")]
mod i2c;
#[cfg(feature = "typec")]
mod pd;
#[cfg(feature = "typec")]
mod typec;
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

/// Virtual HPD (SYSTEM HPD bit 4): Type-C alt mode delivers HPD via PD
/// Attention VDMs; the policy engine mirrors it here. Writing the
/// register also acts as W1C on the event bits, so pass zeros there.
#[cfg(feature = "typec")]
fn set_virtual_hpd(level: bool) {
    unsafe {
        if let Some(system) = SYSTEM.as_mut() {
            system.hpd.write(|w| w.bits((level as u32) << 4));
        }
    }
}

/// Type-C board GPIOs on cpu_io_out: bit24 = HD3SS460 EN, bit25 = POL
/// (1 = flipped), bit26 = VBUS_EN (unused if VBUS is hardwired on the
/// board), bit27 = AMSEL. Read-modify-write so the status code in the
/// low bits is preserved.
#[cfg(feature = "typec")]
pub fn typec_gpio(en: bool, pol_flipped: bool, vbus: bool, amsel: bool) {
    unsafe {
        if let Some(system) = SYSTEM.as_mut() {
            let cur = system.out.read().bits() & !(0xF << 24);
            let v = cur
                | ((en as u32) << 24)
                | ((pol_flipped as u32) << 25)
                | ((vbus as u32) << 26)
                | ((amsel as u32) << 27);
            system.out.write(|w| w.bits(v));
        }
    }
}
#[cfg(not(feature = "typec"))]
#[allow(dead_code)]
pub fn typec_gpio(_en: bool, _pol: bool, _vbus: bool, _amsel: bool) {}

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
#[cfg(all(not(feature = "lanes4"), not(feature = "lanes2")))]
const LANE_COUNT: u8 = 1;
#[cfg(feature = "lanes4")]
const LANE_COUNT: u8 = 4;
#[cfg(all(feature = "lanes2", not(feature = "lanes4")))]
const LANE_COUNT: u8 = 2;

fn source_process(aux: &AuxCh, ml: &MainLink, vid: &mut Video, i2c_p: bootrom_pac::I2C) {
    // Type-C alt mode: bring up USB PD and the alt-mode entry first;
    // the physical-HPD wait below is then satisfied via the virtual
    // HPD register once the sink reports HPD over PD.
    #[cfg(feature = "typec")]
    let i2c = i2c::I2c::new(i2c_p);
    #[cfg(feature = "typec")]
    let mut tc = typec::TypeC::new(fusb302::Fusb302::new(&i2c));
    #[cfg(feature = "typec")]
    {
        // First board smoke test: the DEVICE_ID read exercises the I2C
        // master and the board wiring before anything else happens.
        match fusb302::Fusb302::new(&i2c).device_id() {
            Ok(id) => println!("[SRC] FUSB302B DEVICE_ID = {:02X}", id),
            Err(e) => println!("[SRC] FUSB302B DEVICE_ID read failed: {:?}", e),
        }
        match tc.init() {
            true => println!("[SRC] FUSB302B initialized"),
            false => println!("[SRC] FUSB302B init FAILED"),
        }
    }
    #[cfg(not(feature = "typec"))]
    let _ = i2c_p;

    // Bring-up bypass: skip the HPD gate and go straight to the DPCD
    // retry loop (which keeps polling the PD engine). Useful while the
    // PD/alt-mode path itself is being debugged on a new board.
    #[cfg(feature = "typec")]
    const HPD_BYPASS: bool = true;

    #[cfg(feature = "typec")]
    let mut tc_last_state = tc.state;
    #[cfg(feature = "typec")]
    macro_rules! tc_poll_and_log {
        () => {
            if let Some((hpd, irq)) = tc.poll() {
                println!("[SRC] PD: sink HPD={} IRQ={}", hpd as u32, irq as u32);
                set_virtual_hpd(hpd);
            }
            if tc.state != tc_last_state {
                println!("[SRC] PD state: {:?}", tc.state);
                tc_last_state = tc.state;
            }
        };
    }

    #[cfg(feature = "typec")]
    let skip_hpd_wait = HPD_BYPASS;
    #[cfg(not(feature = "typec"))]
    let skip_hpd_wait = false;

    if skip_hpd_wait {
        println!("[SRC] HPD wait BYPASSED (bring-up mode)");
        // Type-C-side test: the sink hangs off the USB-C receptacle, so
        // the mux and orientation must come from the PD engine. Wait for
        // alt-mode entry (Configure ACKed) before touching AUX; fall
        // back to a manual mux enable if PD goes nowhere (e.g. a cable
        // adapter that skips PD, or an engine bug to debug next).
        #[cfg(feature = "typec")]
        {
            println!("[SRC] waiting for PD alt-mode entry (Type-C)");
            let mut waited_ms = 0u32;
            while tc.state != typec::TcState::Configured
                && tc.state != typec::TcState::Failed
                && waited_ms < 60_000
            {
                tc_poll_and_log!();
                // ~1 ms at 27 MHz between polls.
                for _ in 0..9_000 {
                    unsafe { core::arch::asm!("nop") };
                }
                waited_ms += 1;
            }
            if tc.state == typec::TcState::Configured {
                println!(
                    "[SRC] alt mode configured (POL={}, assignments={:02X})",
                    tc.pol_flipped as u32, tc.ufp_d_assignments
                );
            } else {
                println!(
                    "[SRC] PD stuck in {:?} after 60 s — manual mux enable (POL=0, AMSEL=1)",
                    tc.state
                );
                typec_gpio(true, false, true, true);
            }
        }
    } else {
        println!("[SRC] waiting for HPD");
        while !read_hpd_level() {
            #[cfg(feature = "typec")]
            tc_poll_and_log!();
        }
        if read_hpd_event_plug() {
            println!("[SRC] HPD plug observed");
            clear_hpd_events();
        }
    }

    // Phase A reads (still useful as integration smoke). A real monitor
    // may need some time after HPD before its AUX replier is awake, so
    // retry with a delay and report the detailed failure cause of each
    // attempt (Timeout with rx_count == 0 means the sink never answered
    // at all -> electrical / polarity problem; rx_count > 0 means bytes
    // arrived but the reply could not be decoded).
    let mut buf = [0u8; 16];
    let mut dpcd_ok = false;
    // With the Type-C engine, the AUX path only opens after PD alt-mode
    // entry succeeds, so keep polling the engine between (many more)
    // DPCD attempts instead of giving up after 10.
    #[cfg(feature = "typec")]
    const DPCD_ATTEMPTS: u32 = 600; // ~1 min at 10 ms + PD polling
    #[cfg(not(feature = "typec"))]
    const DPCD_ATTEMPTS: u32 = 10;
    for attempt in 0..DPCD_ATTEMPTS {
        match dpcd::read_block(aux, dpcd::DPCD_REV, &mut buf) {
            Ok(_) => {
                println!("[SRC] DPCD[0..]: {:02X?}", &buf[..16]);
                dpcd_ok = true;
                break;
            }
            Err(e) => {
                if attempt < 10 || attempt % 50 == 0 {
                    println!(
                        "[SRC] DPCD read attempt {} failed: {:?} (rx_count={})",
                        attempt,
                        e,
                        aux.rx_count()
                    );
                }
                #[cfg(feature = "typec")]
                tc_poll_and_log!();
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
    // Type-C-side training: keep EN=1 and the PD-decided polarity, but
    // the HD3SS460 AMSEL level for 4-lane DP is still unverified, so
    // try both levels (4-lane first, then 2-lane probes purely as a
    // diagnostic — a wrong AMSEL level routes only two lanes).
    #[cfg(feature = "typec")]
    {
        let pol = tc.pol_flipped;
        let plan: [(bool, u8); 8] = [
            (true, 4),
            (true, 4),
            (false, 4),
            (false, 4),
            (true, 2),
            (true, 2),
            (false, 2),
            (false, 2),
        ];
        'sweep: for (i, (amsel, lanes)) in plan.iter().enumerate() {
            typec_gpio(true, pol, true, *amsel);
            // Let the mux settle.
            for _ in 0..90_000 {
                unsafe { core::arch::asm!("nop") };
            }
            match link_training::run(aux, ml, *lanes) {
                Ok(s) => {
                    println!(
                        "[SRC] TRAINED: POL={} AMSEL={} lanes={} (cr={}, eq={})",
                        pol as u32, *amsel as u32, lanes, s.cr_iters, s.eq_iters
                    );
                    if *lanes == LANE_COUNT {
                        stats = Some(s);
                    } else {
                        println!("[SRC] NOTE: only {}-lane trains at AMSEL={} — check the mux mode/wiring", lanes, *amsel as u32);
                    }
                    break 'sweep;
                }
                Err(e) => {
                    println!(
                        "[SRC] train {} POL={} AMSEL={} lanes={}: {:?}",
                        i, pol as u32, *amsel as u32, lanes, e
                    );
                    for _ in 0..450_000 {
                        unsafe { core::arch::asm!("nop") };
                    }
                }
            }
        }
    }
    #[cfg(not(feature = "typec"))]
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
    // 2-lane sim profile: 64x16 active, 12/11 rate ratio, tu_active =
    // 44. B = 96 bytes/lane/line -> 2 full TUs + 8-symbol tail =
    // 136 symbols; line = 143 * 12 / 11 = 156 symbols/lane.
    #[cfg(all(not(feature = "board"), feature = "lanes2", not(feature = "lanes4")))]
    let cfg = VideoConfig {
        htotal:    143,
        vtotal:    24,
        hstart:    40,
        vstart:    8,
        hwidth:    64,
        vheight:   16,
        hsw:       4,
        hsp:       false,
        vsw:       2,
        vsp:       false,
        mvid:      0x7555,
        nvid:      0x8000,
        misc0:     0x21,
        misc1:     0x00,
        tu_active: 44,
    };
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
    #[cfg(all(not(feature = "board"), not(feature = "lanes4"), not(feature = "lanes2")))]
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
    // Board 4-lane profile: CEA 1920x1080p60 (VIC 16), 148.5 MHz pixel
    // clock on RBR x4 (162/148.5 = 12/11, line = 2200 * 12/11 = 2400
    // symbols/lane, tu_active = 44 -> window = 32 * 64 + 32 = 2080).
    // hsync 44 + hback 148, vsync 5 + vback 36, both sync positive.
    #[cfg(all(feature = "board", feature = "lanes4"))]
    let cfg = VideoConfig {
        htotal:    2200,
        vtotal:    1125,
        hstart:    192, // HSW 44 + HBACK 148
        vstart:    41,  // VSW 5 + VBACK 36
        hwidth:    1920,
        vheight:   1080,
        hsw:       44,
        hsp:       false,
        vsw:       5,
        vsp:       false,
        mvid:      0x7555, // round(0x8000 * 11 / 12)
        nvid:      0x8000,
        misc0:     0x21,
        misc1:     0x00,
        tu_active: 44,
    };
    // Board 1-lane fallback: CEA 720x480p59.94.
    #[cfg(all(feature = "board", not(feature = "lanes4")))]
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
    #[cfg(all(feature = "lanes2", not(feature = "lanes4")))]
    vid.set_rate(12, 11, 2);
    #[cfg(all(not(feature = "lanes4"), not(feature = "lanes2")))]
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
        #[cfg(feature = "typec")]
        if let Some((hpd, irq)) = tc.poll() {
            println!("[SRC] PD Attention: HPD={} IRQ={}", hpd as u32, irq as u32);
            set_virtual_hpd(hpd);
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
        0 => source_process(&aux, &ml, &mut vid, peripherals.I2C),
        1 => sink_process(&aux),
        other => {
            println!("[CPU?] unknown id {:08X}", other);
            write_system_out(0x0000_0001);
        }
    }

    loop {}
}
