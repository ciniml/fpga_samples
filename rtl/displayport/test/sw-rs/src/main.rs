#![no_std]
#![no_main]

use core::{
    arch::global_asm,
    fmt::{self, Write},
    panic::PanicInfo,
    sync::atomic::{compiler_fence, Ordering},
};

use bootrom_pac;

mod serialout;
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
// Globals (peripheral handles owned by main).
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
            // W1C the event bits (level is RO so the value doesn't matter)
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
// AUX CH transaction layer (DP 1.2 §2.7).
// ---------------------------------------------------------------------------

#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum AuxCommand {
    I2cWrite = 0x0,
    I2cRead = 0x1,
    I2cWriteMot = 0x4,
    I2cReadMot = 0x5,
    NativeWrite = 0x8,
    NativeRead = 0x9,
}

impl AuxCommand {
    fn try_from(value: u8) -> Result<Self, ()> {
        match value {
            0x0 => Ok(Self::I2cWrite),
            0x1 => Ok(Self::I2cRead),
            0x4 => Ok(Self::I2cWriteMot),
            0x5 => Ok(Self::I2cReadMot),
            0x8 => Ok(Self::NativeWrite),
            0x9 => Ok(Self::NativeRead),
            _ => Err(()),
        }
    }

    fn is_read(self) -> bool {
        matches!(
            self,
            Self::I2cRead | Self::I2cReadMot | Self::NativeRead
        )
    }
}

#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum AuxResponseKind {
    Ack = 0b00,
    Nack = 0b01,
    Defer = 0b10,
}

impl AuxResponseKind {
    fn try_from(value: u8) -> Result<Self, ()> {
        match value {
            0b00 => Ok(Self::Ack),
            0b01 => Ok(Self::Nack),
            0b10 => Ok(Self::Defer),
            _ => Err(()),
        }
    }
}

struct AuxRequest<'a> {
    command: AuxCommand,
    address: u32,
    data: &'a [u8],
    /// For read transactions, the expected length-1.
    read_length_minus_one: u8,
}

struct AuxReply {
    kind: AuxResponseKind,
    /// Bytes received after the reply header. For ACK on read this contains
    /// payload; for NACK on write this contains the count of bytes written.
    data_len: usize,
}

struct AuxCh {
    aux_ch: bootrom_pac::AUX_CH,
}

impl AuxCh {
    fn new(aux_ch: bootrom_pac::AUX_CH) -> Self {
        Self { aux_ch }
    }

    fn enable_rx(&self) {
        self.aux_ch.operation_status.write(|w| w.rx_enable().enabled());
    }
    fn clear_rx_complete(&self) {
        self.aux_ch
            .interrupt_status
            .write(|w| w.rx_complete().pending());
    }
    fn is_rx_complete(&self) -> bool {
        self.aux_ch
            .interrupt_status
            .read()
            .rx_complete()
            .is_pending()
    }
    fn is_tx_running(&self) -> bool {
        self.aux_ch.operation_status.read().tx_running().is_running()
    }
    fn set_tx_index(&self, value: u8) {
        self.aux_ch.tx_index.write(|w| w.value().bits(value));
    }
    fn set_tx_count(&self, value: u8) {
        self.aux_ch.tx_count.write(|w| w.value().bits(value));
    }
    fn set_rx_index(&self, value: u8) {
        self.aux_ch.rx_index.write(|w| w.value().bits(value));
    }
    fn get_rx_count(&self) -> u8 {
        self.aux_ch.rx_count.read().value().bits()
    }
    fn buffer_write(&self, index: usize, value: u8) {
        self.aux_ch.buffer[index].write(|w| w.data().bits(value));
    }
    fn buffer_read(&self, index: usize) -> u8 {
        self.aux_ch.buffer[index].read().data().bits()
    }

    fn start_tx(&self, length: u8) {
        self.set_tx_count(length);
        self.set_tx_index(0);
        self.aux_ch
            .operation_status
            .write(|w| w.tx_start().start().rx_enable().enabled());
    }

    fn wait_tx_done(&self) {
        while self.is_tx_running() {}
    }

    fn wait_rx_complete(&self) {
        while !self.is_rx_complete() {}
    }

    /// Send an AUX request (header + optional data) and wait for the reply.
    /// `out` receives reply payload bytes (best-effort, capped by `out.len()`).
    fn send_request_wait_reply(
        &self,
        request: &AuxRequest,
        out: &mut [u8],
    ) -> Result<AuxReply, ()> {
        // Build header: byte0 = (cmd<<4) | addr[19:16], byte1 = addr[15:8],
        // byte2 = addr[7:0], byte3 = length-1.
        let length_minus_one = if request.command.is_read() {
            request.read_length_minus_one
        } else {
            // For writes, length-1 = data.len() - 1
            (request.data.len().saturating_sub(1)) as u8
        };
        let addr = request.address;
        let header = [
            ((request.command as u8) << 4) | (((addr >> 16) & 0x0f) as u8),
            ((addr >> 8) & 0xff) as u8,
            (addr & 0xff) as u8,
            length_minus_one,
        ];

        // Stage in TX buffer
        for (i, b) in header.iter().enumerate() {
            self.buffer_write(i, *b);
        }
        let mut total_len = header.len();
        if !request.command.is_read() {
            for (i, b) in request.data.iter().enumerate() {
                self.buffer_write(total_len + i, *b);
            }
            total_len += request.data.len();
        }

        // Arm the RX side before TX so we don't miss the reply.
        self.clear_rx_complete();
        self.set_rx_index(0);
        self.enable_rx();

        // Kick off TX (combined with rx_enable)
        self.start_tx(total_len as u8);
        self.wait_tx_done();
        self.wait_rx_complete();
        self.clear_rx_complete();

        let rx_count = self.get_rx_count() as usize;
        if rx_count == 0 {
            return Err(());
        }
        let header0 = self.buffer_read(0);
        let kind = AuxResponseKind::try_from(header0 >> 4)?;

        let payload_len = rx_count - 1;
        let copy_len = payload_len.min(out.len());
        for i in 0..copy_len {
            out[i] = self.buffer_read(1 + i);
        }

        Ok(AuxReply {
            kind,
            data_len: payload_len,
        })
    }

    /// Receive an incoming AUX request (replier role).
    /// Returns the parsed command/address/length and copies data bytes
    /// (for writes) into `data_out`.
    fn receive_request(&self, data_out: &mut [u8]) -> Result<(AuxCommand, u32, usize, usize), ()> {
        // Wait for an incoming transaction. RX is left enabled by the previous
        // reply transmission (start_tx writes rx_enable=1).
        self.wait_rx_complete();
        self.clear_rx_complete();

        let rx_count = self.get_rx_count() as usize;
        if rx_count < 4 {
            return Err(());
        }
        let header0 = self.buffer_read(0);
        let header1 = self.buffer_read(1);
        let header2 = self.buffer_read(2);
        let header3 = self.buffer_read(3);

        let command = AuxCommand::try_from(header0 >> 4)?;
        let address = u32::from_be_bytes([0, header0 & 0x0f, header1, header2]);
        let length = (header3 as usize) + 1;

        let data_count = rx_count.saturating_sub(4);
        let copy_len = data_count.min(data_out.len());
        for i in 0..copy_len {
            data_out[i] = self.buffer_read(4 + i);
        }
        Ok((command, address, length, data_count))
    }

    fn send_reply(&self, kind: AuxResponseKind, data: &[u8]) {
        let header = (kind as u8) << 4;
        self.buffer_write(0, header);
        for (i, b) in data.iter().enumerate() {
            self.buffer_write(1 + i, *b);
        }
        self.start_tx((1 + data.len()) as u8);
        self.wait_tx_done();
    }
}

// ---------------------------------------------------------------------------
// Source-side scenario (HPD driven).
// ---------------------------------------------------------------------------

const DPCD_RECEIVER_CAP_BASE: u32 = 0x0_0000;
const EDID_I2C_ADDR: u32 = 0x50;

fn requester_process(aux: &AuxCh) {
    let mut buf = [0u8; 16];

    println!("[SRC] waiting for HPD");
    while !read_hpd_level() {}
    if read_hpd_event_plug() {
        println!("[SRC] HPD plug event observed");
        clear_hpd_events();
    } else {
        println!("[SRC] HPD level high (event missed)");
    }

    // 1. DPCD: read Receiver Capability (0x00000-0x0000F = 16 bytes, §2.9.3).
    let req = AuxRequest {
        command: AuxCommand::NativeRead,
        address: DPCD_RECEIVER_CAP_BASE,
        data: &[],
        read_length_minus_one: 15,
    };
    match aux.send_request_wait_reply(&req, &mut buf) {
        Ok(reply) if reply.kind == AuxResponseKind::Ack => {
            println!("[SRC] DPCD[0x00000..]: {:02X?}", &buf[..reply.data_len.min(buf.len())]);
        }
        Ok(reply) => {
            println!("[SRC] DPCD read non-ACK: {:?}", reply.kind);
            write_system_out(0x0000_0001);
            return;
        }
        Err(()) => {
            println!("[SRC] DPCD read failed");
            write_system_out(0x0000_0001);
            return;
        }
    }

    // 2. EDID: I2C-over-AUX read from device 0x50, 16 bytes.
    let req = AuxRequest {
        command: AuxCommand::I2cRead,
        address: EDID_I2C_ADDR,
        data: &[],
        read_length_minus_one: 15,
    };
    match aux.send_request_wait_reply(&req, &mut buf) {
        Ok(reply) if reply.kind == AuxResponseKind::Ack => {
            println!("[SRC] EDID[0x00..]: {:02X?}", &buf[..reply.data_len.min(buf.len())]);
        }
        Ok(reply) => {
            println!("[SRC] EDID read non-ACK: {:?}", reply.kind);
            write_system_out(0x0000_0001);
            return;
        }
        Err(()) => {
            println!("[SRC] EDID read failed");
            write_system_out(0x0000_0001);
            return;
        }
    }

    println!("[SRC] phase A scenario done");
    write_system_out(0x0000_0001);
}

// ---------------------------------------------------------------------------
// Sink-side scenario (mock replier).
// ---------------------------------------------------------------------------

// Minimal DPCD Receiver Capability response (DP 1.2 Tab 2-75).
// 0x00000 DPCD_REV       = 0x12 (DP 1.2)
// 0x00001 MAX_LINK_RATE  = 0x06 (RBR=0x06)
// 0x00002 MAX_LANE_COUNT = 0x01 (1 lane, no enhanced framing)
// 0x00003 MAX_DOWNSPREAD = 0x00
// 0x00004..0x0000F: zero
const DPCD_RECEIVER_CAP: [u8; 16] = [
    0x12, 0x06, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
];

// Minimal EDID block 0 header marker. Just the standard 8-byte signature
// followed by recognizable bytes for Phase A loopback verification.
const EDID_BLOCK0: [u8; 16] = [
    0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00,
    0x4D, 0x29, 0xC2, 0x07, 0x01, 0x00, 0x00, 0x00,
];

fn replier_process(aux: &AuxCh) {
    // RX must be enabled for the first transaction.
    aux.clear_rx_complete();
    aux.set_rx_index(0);
    aux.enable_rx();

    let mut handled = 0u32;
    let mut buf = [0u8; 256];
    loop {
        let (command, address, length, _data_in) = match aux.receive_request(&mut buf) {
            Ok(v) => v,
            Err(()) => {
                println!("[SNK] malformed request");
                continue;
            }
        };
        let length = length.min(16);
        println!(
            "[SNK] req cmd={:?} addr=0x{:05X} len={}",
            command, address, length
        );

        match command {
            AuxCommand::NativeRead => {
                if address == DPCD_RECEIVER_CAP_BASE {
                    aux.send_reply(AuxResponseKind::Ack, &DPCD_RECEIVER_CAP[..length]);
                } else {
                    aux.send_reply(AuxResponseKind::Nack, &[]);
                }
            }
            AuxCommand::I2cRead | AuxCommand::I2cReadMot => {
                if address == EDID_I2C_ADDR {
                    aux.send_reply(AuxResponseKind::Ack, &EDID_BLOCK0[..length]);
                } else {
                    aux.send_reply(AuxResponseKind::Nack, &[]);
                }
            }
            AuxCommand::NativeWrite | AuxCommand::I2cWrite | AuxCommand::I2cWriteMot => {
                aux.send_reply(AuxResponseKind::Ack, &[]);
            }
        }

        // Re-arm RX for the next transaction.
        aux.clear_rx_complete();
        aux.set_rx_index(0);
        aux.enable_rx();

        handled += 1;
        if handled >= 2 {
            // Source side does DPCD + EDID = 2 transactions. End after that
            // so the TB termination check on cpu_io_out fires.
            println!("[SNK] handled {} transactions, exiting", handled);
            write_system_out(0x0000_0001);
            return;
        }
    }
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
    println!("[CPU{}] phase A boot", cpu_id);

    match cpu_id {
        0 => requester_process(&aux),
        1 => replier_process(&aux),
        other => {
            println!("[CPU?] unknown id {:08X}", other);
            write_system_out(0x0000_0001);
        }
    }

    loop {}
}
