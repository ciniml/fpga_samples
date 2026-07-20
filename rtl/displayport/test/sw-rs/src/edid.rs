//! EDID read over I2C-over-AUX (DP 1.2 §2.7.7).
//!
//! The EDID EEPROM sits at I2C address 0x50 behind the sink's I2C
//! bridge. Sequence: set the word offset with an I2C write (MOT=1),
//! then read 128 bytes in chunks (MOT=1 except for the final chunk,
//! which ends the I2C transaction with MOT=0).

use crate::aux::{AuxCh, AuxCommand, AuxError, AuxRequest, AuxResponseKind};

const EDID_I2C_ADDR: u32 = 0x50;
/// I2C-over-AUX sinks answer DEFER (or ACK with no data) while the
/// EEPROM access is in flight; retry generously.
const MAX_RETRIES: u32 = 64;

fn transact(aux: &AuxCh, req: &AuxRequest, out: &mut [u8]) -> Result<usize, AuxError> {
    for _ in 0..MAX_RETRIES {
        match aux.send_request_wait_reply(req, out) {
            Ok(reply) => match reply.kind {
                AuxResponseKind::Ack => return Ok(reply.data_len),
                AuxResponseKind::Defer => continue,
                AuxResponseKind::Nack => return Err(AuxError::Protocol),
            },
            Err(AuxError::Timeout) => return Err(AuxError::Timeout),
            // I2C_NACK/I2C_DEFER decode as Protocol in the reply
            // parser; treat as retryable here.
            Err(AuxError::Protocol) => continue,
        }
    }
    Err(AuxError::Protocol)
}

/// Read `out.len()` bytes starting at EDID word offset `start`
/// (0 = base block, 128 = first extension block).
pub fn read_edid(aux: &AuxCh, start: u8, out: &mut [u8]) -> Result<(), AuxError> {
    let mut scratch = [0u8; 16];

    // Word offset (MOT=1 keeps the I2C transaction open).
    let offset = [start];
    let set_offset = AuxRequest {
        command: AuxCommand::I2cWriteMot,
        address: EDID_I2C_ADDR,
        data: &offset,
        read_length_minus_one: 0,
    };
    transact(aux, &set_offset, &mut scratch)?;

    let mut off = 0usize;
    while off < out.len() {
        let want = 16.min(out.len() - off);
        let last = off + want >= out.len();
        let req = AuxRequest {
            command: if last {
                AuxCommand::I2cRead
            } else {
                AuxCommand::I2cReadMot
            },
            address: EDID_I2C_ADDR,
            data: &[],
            read_length_minus_one: (want - 1) as u8,
        };
        let got = transact(aux, &req, &mut out[off..off + want])?;
        // A sink may legally return fewer bytes than requested (or an
        // ACK with zero data as an I2C-style defer); just advance by
        // what arrived and continue.
        off += got;
    }
    Ok(())
}
