//! Mock sink replier for Phase C link-training tests. Maintains a small
//! DPCD register file in RAM and applies an ADJUST_REQUEST policy that
//! requires the source to update its drive setting once per phase before
//! reporting CR / EQ done.

use crate::aux::{AuxCh, AuxCommand, AuxResponseKind};
use crate::dpcd;

const DPCD_TABLE_SIZE: usize = 0x300;

/// Number of initial Native AUX requests the mock sink answers with AUX_DEFER
/// before serving normally. This forces the source through the DP 1.2
/// §3.5.1.2.2 DEFER-retry path on every link-training run. Kept well under the
/// 7-retry tolerance so training still converges.
const DEFER_INJECT_COUNT: u8 = 2;

pub struct MockSink {
    dpcd: [u8; DPCD_TABLE_SIZE],
    cr_writes: u8, // count of TRAINING_PATTERN_SET writes selecting TPS1
    eq_writes: u8, // count of TRAINING_PATTERN_SET writes selecting TPS2
    defer_budget: u8, // remaining Native AUX requests to answer with DEFER
}

const EDID_BLOCK0: [u8; 16] = [
    0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x4D, 0x29, 0xC2, 0x07, 0x01, 0x00, 0x00, 0x00,
];

impl MockSink {
    pub fn new() -> Self {
        let mut s = Self {
            dpcd: [0u8; DPCD_TABLE_SIZE],
            cr_writes: 0,
            eq_writes: 0,
            defer_budget: DEFER_INJECT_COUNT,
        };
        // Receiver capability
        s.dpcd[dpcd::DPCD_REV as usize] = 0x12; // DP 1.2
        s.dpcd[dpcd::MAX_LINK_RATE as usize] = dpcd::LINK_BW_RBR;
        // 1 lane + ENHANCED_FRAME_CAP (bit 7): a DPCD 1.2 sink must
        // support Enhanced Framing (DP 1.2 §2.2.1.2).
        s.dpcd[dpcd::MAX_LANE_COUNT as usize] = 0x81;
        s.dpcd[dpcd::MAX_DOWNSPREAD as usize] = 0x01; // 0.5% downspread
        s.dpcd[dpcd::TRAINING_AUX_RD_INTERVAL as usize] = 0x00;
        s
    }

    fn read_byte(&self, address: u32) -> u8 {
        let a = address as usize;
        if a < DPCD_TABLE_SIZE {
            self.dpcd[a]
        } else {
            0
        }
    }

    fn write_byte(&mut self, address: u32, value: u8) {
        let a = address as usize;
        if a < DPCD_TABLE_SIZE {
            self.dpcd[a] = value;
        }
    }

    /// Update LANE_STATUS / ADJUST_REQUEST based on the training counters.
    /// Policy: each phase requires 2 iterations (1st returns failure +
    /// drive-adjust request, 2nd returns success).
    fn refresh_status(&mut self) {
        // Track the current TPS from TRAINING_PATTERN_SET.
        let tps_field = self.read_byte(dpcd::TRAINING_PATTERN_SET) & 0x3;

        let mut lane_status: u8 = 0;
        let mut lane_align: u8 = 0;
        let mut adjust: u8 = 0;

        match tps_field {
            0x01 => {
                // TPS1 — Clock Recovery in progress
                if self.cr_writes >= 2 {
                    lane_status |= dpcd::LANE0_CR_DONE;
                } else {
                    // 1st iter: ask for swing+1 (level 1)
                    adjust = 0x01; // VOLTAGE_SWING_LANE0=1, PRE_EMPHASIS_LANE0=0
                }
            }
            0x02 => {
                // TPS2 — Channel EQ in progress
                lane_status |= dpcd::LANE0_CR_DONE; // CR was already done
                if self.eq_writes >= 2 {
                    lane_status |= dpcd::LANE0_CHANNEL_EQ_DONE | dpcd::LANE0_SYMBOL_LOCKED;
                    lane_align |= dpcd::INTERLANE_ALIGN_DONE;
                } else {
                    // 1st EQ iter: ask for preemph+1 (level 1)
                    adjust = 0x05; // VOLTAGE_SWING_LANE0=1, PRE_EMPHASIS_LANE0=1
                }
            }
            _ => {
                // Pattern cleared — link is up post-training.
                lane_status |= dpcd::LANE0_CR_DONE
                    | dpcd::LANE0_CHANNEL_EQ_DONE
                    | dpcd::LANE0_SYMBOL_LOCKED;
                lane_align |= dpcd::INTERLANE_ALIGN_DONE;
            }
        }

        self.write_byte(dpcd::LANE0_1_STATUS, lane_status);
        self.write_byte(dpcd::LANE_ALIGN_STATUS_UPDATED, lane_align);
        self.write_byte(dpcd::ADJUST_REQUEST_LANE0_1, adjust);
    }

    fn handle_request(&mut self, aux: &AuxCh) -> Result<bool, ()> {
        let mut buf = [0u8; 256];
        let (command, address, length, data_count) = aux.receive_request(&mut buf)?;
        let length = length.min(16);

        let mut training_done_observed = false;

        // DP 1.2 §3.5.1.2.2 DEFER-retry exercise: answer the first
        // DEFER_INJECT_COUNT Native AUX requests with AUX_DEFER (no side
        // effects) so the source must retry. The request is not applied here;
        // the source resends it and it is served normally once the budget is
        // exhausted.
        let is_native = matches!(command, AuxCommand::NativeRead | AuxCommand::NativeWrite);
        if is_native && self.defer_budget > 0 {
            self.defer_budget -= 1;
            aux.send_reply(AuxResponseKind::Defer, &[]);
            return Ok(false);
        }

        match command {
            AuxCommand::NativeRead => {
                self.refresh_status();
                let mut resp = [0u8; 16];
                for i in 0..length {
                    resp[i] = self.read_byte(address + i as u32);
                }
                aux.send_reply(AuxResponseKind::Ack, &resp[..length]);
            }
            AuxCommand::NativeWrite => {
                for i in 0..data_count.min(buf.len()) {
                    self.write_byte(address + i as u32, buf[i]);
                }
                if address == dpcd::TRAINING_PATTERN_SET && data_count > 0 {
                    let tps = buf[0] & 0x03;
                    match tps {
                        0x01 => self.cr_writes = self.cr_writes.saturating_add(1),
                        0x02 => self.eq_writes = self.eq_writes.saturating_add(1),
                        0x00 => {
                            // Training complete.
                            training_done_observed = true;
                        }
                        _ => {}
                    }
                }
                aux.send_reply(AuxResponseKind::Ack, &[]);
            }
            AuxCommand::I2cRead | AuxCommand::I2cReadMot => {
                if address == 0x00050 {
                    let mut resp = [0u8; 16];
                    let copy = length.min(EDID_BLOCK0.len());
                    resp[..copy].copy_from_slice(&EDID_BLOCK0[..copy]);
                    aux.send_reply(AuxResponseKind::Ack, &resp[..copy]);
                } else {
                    aux.send_reply(AuxResponseKind::Nack, &[]);
                }
            }
            AuxCommand::I2cWrite | AuxCommand::I2cWriteMot => {
                aux.send_reply(AuxResponseKind::Ack, &[]);
            }
        }
        Ok(training_done_observed)
    }

    pub fn run(&mut self, aux: &AuxCh) -> bool {
        // Loop forever, but report when training complete (TRAINING_PATTERN_SET
        // cleared) is observed so the caller can signal SYSTEM_OUT.
        aux.arm_rx();
        loop {
            match self.handle_request(aux) {
                Ok(true) => {
                    // Caller signals done; keep replying for any tail
                    // transactions the source might issue.
                    aux.arm_rx();
                    return true;
                }
                Ok(false) => {
                    aux.arm_rx();
                }
                Err(()) => {
                    aux.arm_rx();
                }
            }
        }
    }
}
