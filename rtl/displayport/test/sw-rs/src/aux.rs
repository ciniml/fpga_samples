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

    fn wait_tx_done(&self) {
        while self.is_tx_running() {}
    }
    fn wait_rx_complete(&self) {
        while !self.is_rx_complete() {}
    }

    /// Send an AUX request and wait for the reply.
    pub fn send_request_wait_reply(
        &self,
        request: &AuxRequest,
        out: &mut [u8],
    ) -> Result<AuxReply, ()> {
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
