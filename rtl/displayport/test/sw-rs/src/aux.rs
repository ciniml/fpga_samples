//! AUX CH transaction layer (DP 1.2 §2.7).

use bootrom_pac;

#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AuxCommand {
    I2cWrite = 0x0,
    I2cRead = 0x1,
    I2cWriteMot = 0x4,
    I2cReadMot = 0x5,
    NativeWrite = 0x8,
    NativeRead = 0x9,
}

impl AuxCommand {
    pub fn try_from(value: u8) -> Result<Self, ()> {
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

    pub fn is_read(self) -> bool {
        matches!(self, Self::I2cRead | Self::I2cReadMot | Self::NativeRead)
    }
}

/// Errors that can be raised by the AUX *requester* path.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AuxError {
    /// The sink did not complete the reply within the bounded wait window.
    /// DP 1.2 §2.7.1 specifies a 400 us reply timeout for the requester; when
    /// the poll loop expires we surface this instead of hanging forever.
    Timeout,
    /// A reply arrived but was empty or otherwise malformed.
    Protocol,
}

/// Upper bound on busy-poll iterations while waiting for a requester-side
/// transaction to finish before declaring an `AuxError::Timeout`.
///
/// DP 1.2 §2.7.1 mandates that a requester wait at least 400 us for a reply.
/// The main link clock is 162 MHz, so 400 us == 64,800 clocks. Each iteration
/// of the poll loop performs at least one volatile MMIO register read (several
/// clocks over the CPU bus), so even at an unrealistically optimistic 1
/// clock/iteration this bound corresponds to 1,000,000 / 162e6 ~= 6.2 ms of
/// wall time -- comfortably above the 400 us spec minimum with margin measured
/// in milliseconds, while still guaranteeing termination on a dead sink.
const AUX_WAIT_TIMEOUT_ITERS: u32 = 1_000_000;

#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AuxResponseKind {
    Ack = 0b00,
    Nack = 0b01,
    Defer = 0b10,
}

impl AuxResponseKind {
    pub fn try_from(value: u8) -> Result<Self, ()> {
        match value {
            0b00 => Ok(Self::Ack),
            0b01 => Ok(Self::Nack),
            0b10 => Ok(Self::Defer),
            _ => Err(()),
        }
    }
}

pub struct AuxRequest<'a> {
    pub command: AuxCommand,
    pub address: u32,
    pub data: &'a [u8],
    /// For read transactions, the expected length-1.
    pub read_length_minus_one: u8,
}

pub struct AuxReply {
    pub kind: AuxResponseKind,
    pub data_len: usize,
}

pub struct AuxCh {
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

    // NOTE: `wait_tx_done` / `wait_rx_complete` are the *replier*-side waits
    // (used by `receive_request` / `send_reply`, e.g. the mock sink). A replier
    // legitimately blocks until the requester drives the bus, so these remain
    // unbounded busy-loops and their signatures must stay intact.
    fn wait_tx_done(&self) {
        while self.is_tx_running() {}
    }
    fn wait_rx_complete(&self) {
        while !self.is_rx_complete() {}
    }

    // Requester-side, timeout-guarded variants. DP 1.2 §2.7.1: a requester must
    // not wait indefinitely for a reply -- if the sink is absent/unresponsive we
    // bail out with `AuxError::Timeout` after `AUX_WAIT_TIMEOUT_ITERS` polls.
    fn wait_tx_done_timeout(&self) -> Result<(), AuxError> {
        let mut iters = AUX_WAIT_TIMEOUT_ITERS;
        while self.is_tx_running() {
            if iters == 0 {
                return Err(AuxError::Timeout);
            }
            iters -= 1;
        }
        Ok(())
    }
    fn wait_rx_complete_timeout(&self) -> Result<(), AuxError> {
        let mut iters = AUX_WAIT_TIMEOUT_ITERS;
        while !self.is_rx_complete() {
            if iters == 0 {
                return Err(AuxError::Timeout);
            }
            iters -= 1;
        }
        Ok(())
    }

    /// Send an AUX request and wait for the reply (requester role).
    ///
    /// The wait for TX completion and for the sink reply is bounded per DP 1.2
    /// §2.7.1; an unresponsive sink yields `AuxError::Timeout` instead of a
    /// permanent hang. Note this returns the raw reply *kind* (Ack/Nack/Defer);
    /// DEFER retry handling per §3.5.1.2.2 lives in the `dpcd` layer.
    pub fn send_request_wait_reply(
        &self,
        request: &AuxRequest,
        out: &mut [u8],
    ) -> Result<AuxReply, AuxError> {
        let length_minus_one = if request.command.is_read() {
            request.read_length_minus_one
        } else {
            request.data.len().saturating_sub(1) as u8
        };
        let addr = request.address;
        let header = [
            ((request.command as u8) << 4) | (((addr >> 16) & 0x0f) as u8),
            ((addr >> 8) & 0xff) as u8,
            (addr & 0xff) as u8,
            length_minus_one,
        ];

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

        self.clear_rx_complete();
        self.set_rx_index(0);
        self.enable_rx();

        self.start_tx(total_len as u8);
        self.wait_tx_done_timeout()?;
        self.wait_rx_complete_timeout()?;
        self.clear_rx_complete();

        let rx_count = self.get_rx_count() as usize;
        if rx_count == 0 {
            return Err(AuxError::Protocol);
        }
        let header0 = self.buffer_read(0);
        let kind = AuxResponseKind::try_from(header0 >> 4).map_err(|_| AuxError::Protocol)?;

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

    /// Receive an AUX request (replier role).
    pub fn receive_request(
        &self,
        data_out: &mut [u8],
    ) -> Result<(AuxCommand, u32, usize, usize), ()> {
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

    pub fn send_reply(&self, kind: AuxResponseKind, data: &[u8]) {
        let header = (kind as u8) << 4;
        self.buffer_write(0, header);
        for (i, b) in data.iter().enumerate() {
            self.buffer_write(1 + i, *b);
        }
        self.start_tx((1 + data.len()) as u8);
        self.wait_tx_done();
    }

    pub fn arm_rx(&self) {
        self.clear_rx_complete();
        self.set_rx_index(0);
        self.enable_rx();
    }
}
