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
mod link_training;
mod main_link;
mod mock_sink;
mod serialout;

use aux::AuxCh;
use main_link::MainLink;
use mock_sink::MockSink;
use serialout::SerialOut;

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

fn source_process(aux: &AuxCh, ml: &MainLink) {
    println!("[SRC] waiting for HPD");
    while !read_hpd_level() {}
    if read_hpd_event_plug() {
        println!("[SRC] HPD plug observed");
        clear_hpd_events();
    }

    // Phase A reads (still useful as integration smoke).
    let mut buf = [0u8; 16];
    if dpcd::read_block(aux, dpcd::DPCD_REV, &mut buf).is_ok() {
        println!("[SRC] DPCD[0..]: {:02X?}", &buf[..16]);
    }

    // Phase C link training.
    match link_training::run(aux, ml) {
        Ok(stats) => {
            println!(
                "[SRC] link training done (cr_iters={}, eq_iters={})",
                stats.cr_iters, stats.eq_iters
            );
            // Encode iteration counts in upper bits of cpu_io_out for the TB
            // to verify the ADJUST_REQUEST loop ran exactly twice per phase.
            let v = 0x0000_0001
                | ((stats.cr_iters & 0xFF) << 8)
                | ((stats.eq_iters & 0xFF) << 16);
            write_system_out(v);
        }
        Err(e) => {
            println!("[SRC] link training failed: {:?}", e);
            write_system_out(0x0000_0003);
        }
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
    println!("[CPU{}] phase C boot", cpu_id);

    match cpu_id {
        0 => source_process(&aux, &ml),
        1 => sink_process(&aux),
        other => {
            println!("[CPU?] unknown id {:08X}", other);
            write_system_out(0x0000_0001);
        }
    }

    loop {}
}
