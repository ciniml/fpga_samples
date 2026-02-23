#![no_std]
#![no_main]

use core::{arch::global_asm, fmt::Write, panic::PanicInfo, sync::atomic::{compiler_fence, Ordering}};
use bootrom_pac::{self};

mod serialout;
use serialout::SerialOut;


#[allow(unused_imports)]
use riscv::asm;

global_asm!(r#"
.section .isr_vector,"ax",@progbits
    j _start
.section .text,"ax",@progbits
_start:
    la sp, ramend
    addi sp, sp, -4
    csrw mstatus, zero
    csrw mip, zero
    csrw mie, zero
    la t0, trap_handler
    csrw mtvec, zero
    j start_rust
"#);

extern "C" {
    static mut _bss_start: u32;
    static mut _bss_end: u32;
    static mut _data_start: u32;
    static mut _data_end: u32;
    static _data_rom_start: u32;
}

#[no_mangle]
pub unsafe extern "C" fn trap_handler() {
    loop{};
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

// SYSTEM
static mut SYSTEM: Option<bootrom_pac::SYSTEM> = None;

fn get_cpu_id() -> u32 {
    match unsafe { SYSTEM.as_mut() } {
        Some(system) => {
            system.id.read().bits()
        }
        None => panic!("SYSTEM is not initialized"),
    }
}

fn write_system_out(value: u32) {
    match unsafe { SYSTEM.as_mut() } {
        Some(system) => {
            system.out.write(|w| w.bits(value));
        }
        None => {}
    }
}

// Stdout struct 
use core::fmt;
static mut SERIAL_OUT: Option<SerialOut<bootrom_pac::SYSTEM_SERIALOUT>> = None;

// print formatted arguments to the stdout.
fn print_fmt(args: fmt::Arguments, line_end: bool) {
    match unsafe { SERIAL_OUT.as_mut() } {
        Some(serial_out) => {
            serial_out.write_fmt(args).unwrap();
            if line_end {
                writeln!(serial_out).unwrap();
            }
        }
        None => {}
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

struct AuxCh {
    aux_ch: bootrom_pac::AUX_CH,
}
impl AuxCh {
    pub fn new(aux_ch: bootrom_pac::AUX_CH) -> Self {
        Self { aux_ch }
    }

    fn enable_rx(&self) {
        self.aux_ch.operation_status.write(|w| w.rx_enable().enabled());
    }
    fn clear_rx_complete(&self) {
        self.aux_ch.interrupt_status.write(|w| w.rx_complete().pending());
    }
    fn is_rx_complete(&self) -> bool {
        self.aux_ch.interrupt_status.read().rx_complete().is_pending()
    }
    fn is_rx_running(&self ) -> bool {
        self.aux_ch.operation_status.read().rx_running().is_running()
    }
    fn is_tx_running(&self ) -> bool {
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

    fn start_tx<I: Iterator<Item = u8>>(&self, data: I) {
        let mut length = 0;
        for (i, byte) in data.enumerate() {
            self.aux_ch.buffer[i].write(|w| w.data().bits(byte));
            length += 1;
        }
        self.set_tx_count(length as u8);
        self.set_tx_index(0);
        self.aux_ch.operation_status.write(|w| w.tx_start().start().rx_enable().enabled());
    }
    fn wait_tx_done(&self) {
        while self.is_tx_running() {}
    }
    fn wait_rx_complete(&self) {
        while !self.is_rx_complete() {}
    }
    fn read_rx<'r, I: Iterator<Item = &'r mut u8>>(&self, bytes_to_read: usize, data: I) -> Result<usize, ()> {
        self.clear_rx_complete();
        self.set_rx_index(0);
        self.enable_rx();
        self.wait_rx_complete();
        self.clear_rx_complete();
        let rx_count = self.get_rx_count() as usize;
        let bytes_to_read = bytes_to_read.min(rx_count);
        for (i, b) in data.enumerate() {
            if i >= bytes_to_read {
                break;
            }
            *b = self.aux_ch.buffer[i].read().data().bits();
        }
        Ok(rx_count as usize)
    }

    fn send_requester_request(&self, request: AuxChRequesterRequest) {
        match request {
            AuxChRequesterRequest::Read(read_request) => {
                self.start_tx(read_request.request_header().into_iter());
            }
            AuxChRequesterRequest::Write(write_request) => {
                self.start_tx(write_request.request_header().into_iter().chain(write_request.data.iter().copied()));
            }
        }
    }

    fn send_replier_response(&self, response: AuxChReplierResponse) {
        match response {
            AuxChReplierResponse { kind, data: Some(data) } => {
                self.start_tx([(kind as u8) << 4].iter().copied().chain(data.iter().copied()));
            }
            AuxChReplierResponse { kind, data: None } => {
                self.start_tx([(kind as u8) << 4].iter().copied());
            }
        }
    }

    fn receive_replier_request(&self, buffer: &mut [u8]) -> Result<AuxChReplierRequest, ()> {
        let mut header_buffer = [0u8; 4];
        let bytes_read = self.read_rx(5 + buffer.len(), header_buffer.iter_mut().chain(buffer.iter_mut()))?;
        println!("[REPLIER] Received request[{}]: {:02X?}", bytes_read, &header_buffer[..]);
        let command = AuxChRequestCommand::try_from(header_buffer[0] >> 4)?;
        let address = u32::from_be_bytes([0, header_buffer[0] & 0x0f, header_buffer[1], header_buffer[2]]);
        let length = (header_buffer[3] as usize) + 1;
        Ok(AuxChReplierRequest::new(command, address, length))
    }

    fn receive_requester_response(&self, is_read: bool,  buffer: &mut [u8]) -> Result<AuxChRequesterResponse, ()> {
        let mut header_buffer = [0u8; 2];
        let header_bytes_to_read = if is_read { 1 } else { 2 };
        let bytes_to_read = header_bytes_to_read + buffer.len();
        let bytes_read = self.read_rx(bytes_to_read, header_buffer[..header_bytes_to_read].iter_mut().chain(buffer.iter_mut()))?;
        println!("[REQUESTER] Received response[{}]: {:02X?}", bytes_read, &header_buffer[..]);
        if bytes_read == 0 {
            return Err(());
        }
        let kind = AuxChNativeResponseKind::try_from(header_buffer[0] >> 4)?;
        let length = if bytes_read >= 2 { header_buffer[1] as usize + 1 } else { 0 };
        match kind {
            AuxChNativeResponseKind::Ack => {
                if is_read {
                    Ok(AuxChRequesterResponse::Read(AuxChRequesterReadResponse::new(kind, bytes_read - 1)))
                } else {
                    Ok(AuxChRequesterResponse::Write(AuxChRequesterWriteResponse::new(kind, 0)))
                }
            }
            AuxChNativeResponseKind::Nack => {
                if is_read {
                    Ok(AuxChRequesterResponse::Read(AuxChRequesterReadResponse::new(kind, 0)))
                } else {
                    Ok(AuxChRequesterResponse::Write(AuxChRequesterWriteResponse::new(kind, length)))
                }
            }
            AuxChNativeResponseKind::Defer => {
                if is_read {
                    Ok(AuxChRequesterResponse::Read(AuxChRequesterReadResponse::new(kind, 0)))
                } else {
                    Ok(AuxChRequesterResponse::Write(AuxChRequesterWriteResponse::new(kind, 0)))
                }
            }
        }
    }

    
}

enum AuxChRequesterRequest<'a> {
    Read(AuxChRequesterReadRequest),
    Write(AuxChRequesterWriteRequest<'a>),
}

#[repr(u8)]
#[derive(Debug)]
enum AuxChRequestCommand {
    NativeRead = 0x9,
    NativeWrite = 0x8,
}

impl TryFrom<u8> for AuxChRequestCommand {
    type Error = ();
    fn try_from(value: u8) -> Result<Self, Self::Error> {
        match value {
            0x9 => Ok(Self::NativeRead),
            0x8 => Ok(Self::NativeWrite),
            _ => Err(()),
        }
    }
}

struct AuxChRequesterReadRequest {
    address: u32,
    length: usize,
}

impl AuxChRequesterReadRequest {
    fn new(address: u32, length: usize) -> Self {
        assert!(address < 0x0010_0000);
        assert!(length <= 255);
        Self { address, length }
    }
    fn request_header(&self) -> [u8; 4] {
        let address_bytes = self.address.to_be_bytes();
        let command_byte = (AuxChRequestCommand::NativeRead as u8) << 4;
        [command_byte | address_bytes[1], address_bytes[2], address_bytes[3], (self.length - 1) as u8]
    }
}

struct AuxChRequesterWriteRequest<'a> {
    address: u32,
    data: &'a [u8],
}

impl<'a> AuxChRequesterWriteRequest<'a> {
    fn new(address: u32, data: &'a [u8]) -> Self {
        assert!(address < 0x0010_0000);
        assert!(data.len() <= 255);
        Self { address, data }
    }
    fn request_header(&self) -> [u8; 4] {
        let address_bytes = self.address.to_be_bytes();
        let command_byte = (AuxChRequestCommand::NativeWrite as u8) << 4;
        [command_byte | address_bytes[1], address_bytes[2], address_bytes[3], (self.data.len() - 1) as u8]
    }
}

struct AuxChReplierRequest {
    command: AuxChRequestCommand,
    address: u32,
    length: usize,
}

impl AuxChReplierRequest {
    fn new(command: AuxChRequestCommand, address: u32, length: usize) -> Self {
        assert!(address < 0x0010_0000);
        assert!(length <= 255);
        Self { command, address, length }
    }
}

#[derive(Debug)]
enum AuxChRequesterResponse {
    Read(AuxChRequesterReadResponse),
    Write(AuxChRequesterWriteResponse),
}

#[derive(Debug)]
enum AuxChNativeResponseKind {
    Ack,
    Nack,
    Defer,
}

impl TryFrom<u8> for AuxChNativeResponseKind {
    type Error = ();
    fn try_from(value: u8) -> Result<Self, Self::Error> {
        match value {
            0b00 => Ok(Self::Ack),
            0b01 => Ok(Self::Nack),
            0b10 => Ok(Self::Defer),
            _ => Err(()),
        }
    }
}

#[derive(Debug)]
struct AuxChRequesterReadResponse {
    kind: AuxChNativeResponseKind,
    length: usize,
}

impl AuxChRequesterReadResponse {
    fn new(kind: AuxChNativeResponseKind, length: usize) -> Self {
        Self { kind, length }
    }
}

#[derive(Debug)]
struct AuxChRequesterWriteResponse {
    kind: AuxChNativeResponseKind,
    length: usize,
}

impl AuxChRequesterWriteResponse {
    fn new(kind: AuxChNativeResponseKind, length: usize) -> Self {
        Self { kind, length }
    }
}

struct AuxChReplierResponse<'a> {
    kind: AuxChNativeResponseKind,
    data: Option<&'a [u8]>,
}

fn requester_process(aux_ch: &AuxCh) -> Result<(), ()> {
    let mut buffer = [0u8; 256];
    // aux_ch.send_requester_request(AuxChRequesterRequest::Read(AuxChRequesterReadRequest::new(0x01_2345, 3)));
    // let response = aux_ch.receive_requester_response(true, &mut buffer)?;
    // println!("[REQUESTER] Received response: {:?}", response);
    // aux_ch.send_requester_request(AuxChRequesterRequest::Read(AuxChRequesterReadRequest::new(0x03_4567, 3)));
    // let response = aux_ch.receive_requester_response(true, &mut buffer)?;
    // println!("[REQUESTER] Received response: {:?}", response);
    // aux_ch.send_requester_request(AuxChRequesterRequest::Write(AuxChRequesterWriteRequest::new(0x01_2345, &[0x01, 0x02, 0x03])));
    // let response = aux_ch.receive_requester_response(false, &mut buffer)?;
    // println!("[REQUESTER] Received response: {:?}", response);
    // aux_ch.send_requester_request(AuxChRequesterRequest::Write(AuxChRequesterWriteRequest::new(0x03_4567, &[0x01, 0x02, 0x03])));
    // let response = aux_ch.receive_requester_response(false, &mut buffer)?;
    // println!("[REQUESTER] Received response: {:?}", response);

    // for i in 0..16 {
    //     let address = 0x10 * i + 0x100;
    //     aux_ch.send_requester_request(AuxChRequesterRequest::Read(AuxChRequesterReadRequest::new(address, 16)));
    //     let response = aux_ch.receive_requester_response(true, &mut buffer)?;
    //     println!("[REQUESTER] Received response: {:?}", response);
    //     match response {
    //         AuxChRequesterResponse::Read(AuxChRequesterReadResponse { kind: AuxChNativeResponseKind::Ack, length }) => {
    //             println!("[REQUESTER] Read response[{:04X}]: {:02X?}", address, &buffer[..length]);
    //         },
    //         _ => {}
    //     }
    // }

    let address = 0x10 * 0 + 0x100;
    aux_ch.send_requester_request(AuxChRequesterRequest::Read(AuxChRequesterReadRequest::new(address, 16)));
    let response = aux_ch.receive_requester_response(true, &mut buffer)?;
    println!("[REQUESTER] Received response: {:?}", response);
    match response {
        AuxChRequesterResponse::Read(AuxChRequesterReadResponse { kind: AuxChNativeResponseKind::Ack, length }) => {
            println!("[REQUESTER] Read response[{:04X}]: {:02X?}", address, &buffer[..length]);
        },
        _ => {}
    }
    Ok(())
}

fn replier_process_command(aux_ch: &AuxCh) -> Result<bool, ()> {
    let mut buffer = [0u8; 256];
    let request = aux_ch.receive_replier_request(&mut buffer)?;
    let mut exit = false;
    println!("[REPLIER] Received request: {:?} {:06X} {}", request.command, request.address, request.length);
    let mut response_data = [0u8; 256];
    let response = match request.command {
        AuxChRequestCommand::NativeRead => {
            match request.address {
                0x00_0100 => {
                    let data = [0x0A, 0x84, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,];
                    response_data[..16].copy_from_slice(&data);
                    AuxChReplierResponse { kind: AuxChNativeResponseKind::Ack, data: Some(&response_data[0..request.length]) }
                }
                0x01_2345 => {
                    response_data[0] = 0x02;
                    response_data[1] = 0x00;
                    response_data[2] = 0x01;
                    response_data[3] = 0x02;
                    AuxChReplierResponse { kind: AuxChNativeResponseKind::Ack, data: Some(&response_data[0..4]) }
                },
                _ => AuxChReplierResponse { kind: AuxChNativeResponseKind::Nack, data: None }
            
            }
        },
        AuxChRequestCommand::NativeWrite => {
            match request.address {
                0x03_4567 => {
                    exit = true;
                    response_data[0] = (request.length - 1) as u8;
                    AuxChReplierResponse { kind: AuxChNativeResponseKind::Ack, data: Some(&response_data[0..1]) }
                },
                _ => AuxChReplierResponse { kind: AuxChNativeResponseKind::Nack, data: None }
            }
        }
    };
    println!("[REPLIER] Sending response: {:?} {:02X?}", response.kind, response.data);
    aux_ch.send_replier_response(response);
    Ok(exit)
}

fn replier_process(aux_ch: &AuxCh) {
    loop {
        if let Some(exit) = replier_process_command(aux_ch).ok() {
            if exit {
                println!("[REPLIER] Exiting");
                break;
            }
        }
    }
}

#[no_mangle]
pub extern "C" fn main() -> ! {
    let peripherals = bootrom_pac::Peripherals::take().unwrap();
    unsafe { SYSTEM = Some(peripherals.SYSTEM); }
    let serial_out = SerialOut::<bootrom_pac::SYSTEM_SERIALOUT>::init(peripherals.SYSTEM_SERIALOUT);
    unsafe { SERIAL_OUT = Some(serial_out); }

    let cpu_id = get_cpu_id();
    let aux_ch = AuxCh::new(peripherals.AUX_CH);
    for i in 0..10 {
        println!("Hello, world from {:08X} {}", cpu_id, i); 
    }

    match cpu_id {
        0x00 => {
            println!("Requester process");
            requester_process(&aux_ch).unwrap();
        },
        0x01 => {
            println!("Replier process");
            replier_process(&aux_ch);
        },
        other => {
            println!("Unknown CPU ID: {:08X}", other);
        }
    }
    write_system_out(0x0000_0001);
    loop {}
}