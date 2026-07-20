//! DPCD address constants + helper accessors over AUX (DP 1.2 Tab 2-75).

use crate::aux::{AuxCh, AuxCommand, AuxError, AuxReply, AuxRequest, AuxResponseKind};

/// Detailed failure cause of a DPCD transaction, for bring-up logging.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DpcdError {
    /// No reply within the AUX timeout (sink silent / RX never locked).
    Timeout,
    /// Reply framing was invalid.
    Protocol,
    /// Sink answered AUX_NACK.
    Nack,
    /// Sink kept answering AUX_DEFER beyond the retry budget.
    DeferExhausted,
}

/// Maximum number of AUX DEFER retries tolerated for a single transaction.
///
/// DP 1.2 §3.5.1.2.2: a source shall retry a Native AUX request that is
/// answered with AUX_DEFER, tolerating up to 7 consecutive DEFERs. If the sink
/// still DEFERs on the 8th attempt (i.e. after 7 retries) the source gives up.
const MAX_AUX_DEFER_RETRIES: u32 = 7;

/// Run one AUX transaction with DP 1.2 §3.5.1.2.2 DEFER-retry semantics.
///
/// - ACK   -> return the reply.
/// - DEFER -> resend, up to `MAX_AUX_DEFER_RETRIES` times; give up afterwards.
/// - NACK  -> immediate error (sink rejected the request; no retry).
/// - `AuxError` (e.g. Timeout) -> immediate error, propagated to the caller so
///   it can decide (per §2.7.1 a timeout is not retried at this layer).
fn transact(aux: &AuxCh, req: &AuxRequest, out: &mut [u8]) -> Result<AuxReply, DpcdError> {
    // 1 initial attempt + up to MAX_AUX_DEFER_RETRIES retries = 8 attempts.
    for _ in 0..=MAX_AUX_DEFER_RETRIES {
        match aux.send_request_wait_reply(req, out) {
            Ok(reply) => match reply.kind {
                AuxResponseKind::Ack => return Ok(reply),
                AuxResponseKind::Defer => continue,
                AuxResponseKind::Nack => return Err(DpcdError::Nack),
            },
            // Timeout / protocol errors are not DEFER: do not retry here.
            Err(AuxError::Timeout) => return Err(DpcdError::Timeout),
            Err(AuxError::Protocol) => return Err(DpcdError::Protocol),
        }
    }
    // 8th consecutive DEFER: abandon the transaction (§3.5.1.2.2).
    Err(DpcdError::DeferExhausted)
}

// Receiver Capability field
pub const DPCD_REV: u32 = 0x00000;
pub const MAX_LINK_RATE: u32 = 0x00001;
pub const MAX_LANE_COUNT: u32 = 0x00002;
pub const MAX_DOWNSPREAD: u32 = 0x00003;
pub const TRAINING_AUX_RD_INTERVAL: u32 = 0x0000E;

// Link Configuration field
pub const LINK_BW_SET: u32 = 0x00100;
pub const LANE_COUNT_SET: u32 = 0x00101;
pub const TRAINING_PATTERN_SET: u32 = 0x00102;
pub const TRAINING_LANE0_SET: u32 = 0x00103;
pub const TRAINING_LANE1_SET: u32 = 0x00104;
pub const TRAINING_LANE2_SET: u32 = 0x00105;
pub const TRAINING_LANE3_SET: u32 = 0x00106;
pub const DOWNSPREAD_CTRL: u32 = 0x00107;
pub const MAIN_LINK_CHANNEL_CODING_SET: u32 = 0x00108;

// Link/Sink Status field
pub const LANE0_1_STATUS: u32 = 0x00202;
pub const LANE2_3_STATUS: u32 = 0x00203;
pub const LANE_ALIGN_STATUS_UPDATED: u32 = 0x00204;
pub const SINK_STATUS: u32 = 0x00205;
pub const ADJUST_REQUEST_LANE0_1: u32 = 0x00206;
pub const ADJUST_REQUEST_LANE2_3: u32 = 0x00207;

// Bit fields
pub const LANE0_CR_DONE: u8 = 1 << 0;
pub const LANE0_CHANNEL_EQ_DONE: u8 = 1 << 1;
pub const LANE0_SYMBOL_LOCKED: u8 = 1 << 2;
pub const INTERLANE_ALIGN_DONE: u8 = 1 << 0;

// Common values
pub const LINK_BW_RBR: u8 = 0x06;
pub const TPS1: u8 = 0x01;
pub const TPS2: u8 = 0x02;
pub const SCRAMBLING_DISABLE: u8 = 0x20; // bit 5 of TRAINING_PATTERN_SET
pub const ANSI_8B10B: u8 = 0x01;

/// Voltage swing / pre-emphasis encoded into TRAINING_LANEx_SET.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DriveSetting {
    pub voltage_swing: u8,    // 0..3
    pub pre_emphasis: u8,     // 0..3
}

impl Default for DriveSetting {
    fn default() -> Self {
        Self {
            voltage_swing: 0,
            pre_emphasis: 0,
        }
    }
}

impl DriveSetting {
    pub fn encode(self) -> u8 {
        let max_swing = (self.voltage_swing == 3) as u8;
        let max_preemph = (self.pre_emphasis == 3) as u8;
        (self.voltage_swing & 0x3)
            | (max_swing << 2)
            | ((self.pre_emphasis & 0x3) << 3)
            | (max_preemph << 5)
    }

    /// Extract lane0 setting from ADJUST_REQUEST_LANE0_1 byte (DPCD 0x206).
    pub fn from_adjust_lane0(b: u8) -> Self {
        Self {
            voltage_swing: b & 0x3,
            pre_emphasis: (b >> 2) & 0x3,
        }
    }

    pub fn swing_max(self) -> bool {
        self.voltage_swing >= 3
    }
}

pub fn read(aux: &AuxCh, address: u32) -> Result<u8, DpcdError> {
    let mut buf = [0u8; 1];
    let req = AuxRequest {
        command: AuxCommand::NativeRead,
        address,
        data: &[],
        read_length_minus_one: 0,
    };
    // transact() only returns Ok on ACK (DEFER retried per §3.5.1.2.2).
    transact(aux, &req, &mut buf)?;
    Ok(buf[0])
}

pub fn write(aux: &AuxCh, address: u32, value: u8) -> Result<(), DpcdError> {
    let mut buf = [0u8; 4];
    let data = [value];
    let req = AuxRequest {
        command: AuxCommand::NativeWrite,
        address,
        data: &data,
        read_length_minus_one: 0,
    };
    transact(aux, &req, &mut buf)?;
    Ok(())
}

pub fn read_block(aux: &AuxCh, address: u32, out: &mut [u8]) -> Result<usize, DpcdError> {
    let len = out.len().min(16);
    let req = AuxRequest {
        command: AuxCommand::NativeRead,
        address,
        data: &[],
        read_length_minus_one: (len - 1) as u8,
    };
    let reply = transact(aux, &req, out)?;
    Ok(reply.data_len.min(out.len()))
}
