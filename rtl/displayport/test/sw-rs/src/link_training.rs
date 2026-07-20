//! Source-side link training state machine (DP 1.2 §3.5.1.2,
//! Fig 3-32 / Fig 3-33).

use crate::aux::AuxCh;
use crate::dpcd::{self, DpcdError, DriveSetting};
use crate::main_link::{MainLink, Pattern};

#[derive(Debug, Clone, Copy)]
pub enum Error {
    DpcdRead(DpcdError),
    DpcdWrite(DpcdError),
    CrFailed,
    CrLost,
    EqFailed,
}

pub struct Stats {
    pub cr_iters: u32,
    pub eq_iters: u32,
}

/// Wait roughly TRAINING_AUX_RD_INTERVAL. The encoded value (DPCD 0x0E)
/// uses 0x00 = 100 us / 400 us, etc. We approximate in system-clock cycles
/// (this firmware does not model wall-clock time exactly).
fn wait_aux_rd_interval(_value: u8) {
    // ~200 system-clock cycles is plenty for sim. The mock sink does not
    // need real timing; this just provides a small breathing space between
    // DPCD writes and the first status read.
    for _ in 0..200 {
        unsafe {
            core::arch::asm!("nop");
        }
    }
}

/// Per-lane status mask helpers: 0x202 carries lanes 0/1 in its low and
/// high nibbles, 0x203 carries lanes 2/3.
fn lanes_done(status01: u8, status23: u8, lanes: u8, mask: u8) -> bool {
    let mut ok = (status01 & mask) == mask;
    if lanes >= 2 {
        ok &= ((status01 >> 4) & mask) == mask;
    }
    if lanes >= 4 {
        ok &= (status23 & mask) == mask;
        ok &= ((status23 >> 4) & mask) == mask;
    }
    ok
}

pub fn run(aux: &AuxCh, ml: &MainLink, lanes: u8) -> Result<Stats, Error> {
    // Sink capability
    let _max_link_rate = dpcd::read(aux, dpcd::MAX_LINK_RATE).map_err(Error::DpcdRead)?;
    let max_lane_count_raw = dpcd::read(aux, dpcd::MAX_LANE_COUNT).map_err(Error::DpcdRead)?;
    let _max_lane_count = max_lane_count_raw & 0x1F;
    // ENHANCED_FRAME_CAP (bit 7 of MAX_LANE_COUNT). DP 1.2 §2.2.1.1
    // requires Enhanced Framing when interoperating with a DPCD 1.2+
    // sink, and such sinks must advertise this capability.
    // (A bring-up experiment ran with EF forced off: no behavioural
    // difference on the real monitor, which ruled out an EF
    // scrambler-reset-position mismatch.)
    let enhanced_framing = (max_lane_count_raw & 0x80) != 0;
    let aux_rd_interval =
        dpcd::read(aux, dpcd::TRAINING_AUX_RD_INTERVAL).map_err(Error::DpcdRead)?;

    // Phase C: RBR / 1 lane fixed
    dpcd::write(aux, dpcd::LINK_BW_SET, dpcd::LINK_BW_RBR).map_err(Error::DpcdWrite)?;
    // LANE_COUNT_SET: lane count | ENHANCED_FRAME_EN (bit 7).
    dpcd::write(
        aux,
        dpcd::LANE_COUNT_SET,
        lanes | if enhanced_framing { 0x80 } else { 0x00 },
    )
    .map_err(Error::DpcdWrite)?;
    dpcd::write(aux, dpcd::MAIN_LINK_CHANNEL_CODING_SET, dpcd::ANSI_8B10B)
        .map_err(Error::DpcdWrite)?;
    ml.set_lane_count(lanes);

    let mut stats = Stats {
        cr_iters: 0,
        eq_iters: 0,
    };

    // (3) Clock Recovery loop
    let mut drive = DriveSetting::default();
    let mut prev_drive = drive;
    let mut same_voltage_count: u32 = 0;
    let mut first_iter = true;
    loop {
        ml.set_pattern(Pattern::Tps1, /* rd_reset = */ first_iter, enhanced_framing);
        ml.set_lane0_drive(drive.voltage_swing, drive.pre_emphasis);
        dpcd::write(aux, dpcd::TRAINING_PATTERN_SET, dpcd::SCRAMBLING_DISABLE | dpcd::TPS1)
            .map_err(Error::DpcdWrite)?;
        // Same drive on every active lane (we adjust from lane 0's
        // request only — a deliberate simplification).
        for l in 0..lanes as u32 {
            dpcd::write(aux, dpcd::TRAINING_LANE0_SET + l, drive.encode())
                .map_err(Error::DpcdWrite)?;
        }
        wait_aux_rd_interval(aux_rd_interval);
        stats.cr_iters += 1;

        let st01 = dpcd::read(aux, dpcd::LANE0_1_STATUS).map_err(Error::DpcdRead)?;
        let st23 = if lanes >= 4 {
            dpcd::read(aux, dpcd::LANE2_3_STATUS).map_err(Error::DpcdRead)?
        } else {
            0
        };
        if lanes_done(st01, st23, lanes, dpcd::LANE0_CR_DONE) {
            break;
        }
        let adjust =
            dpcd::read(aux, dpcd::ADJUST_REQUEST_LANE0_1).map_err(Error::DpcdRead)?;
        let new_drive = DriveSetting::from_adjust_lane0(adjust);
        if !first_iter && new_drive == prev_drive {
            same_voltage_count += 1;
            if same_voltage_count >= 5 || drive.swing_max() {
                return Err(Error::CrFailed);
            }
        } else {
            same_voltage_count = 0;
        }
        prev_drive = new_drive;
        drive = new_drive;
        first_iter = false;
    }

    // (4) Channel EQ loop (max 5 iterations)
    for _ in 0..5 {
        ml.set_pattern(Pattern::Tps2, false, enhanced_framing);
        ml.set_lane0_drive(drive.voltage_swing, drive.pre_emphasis);
        dpcd::write(aux, dpcd::TRAINING_PATTERN_SET, dpcd::SCRAMBLING_DISABLE | dpcd::TPS2)
            .map_err(Error::DpcdWrite)?;
        for l in 0..lanes as u32 {
            dpcd::write(aux, dpcd::TRAINING_LANE0_SET + l, drive.encode())
                .map_err(Error::DpcdWrite)?;
        }
        wait_aux_rd_interval(aux_rd_interval);
        stats.eq_iters += 1;

        let st01 = dpcd::read(aux, dpcd::LANE0_1_STATUS).map_err(Error::DpcdRead)?;
        let st23 = if lanes >= 4 {
            dpcd::read(aux, dpcd::LANE2_3_STATUS).map_err(Error::DpcdRead)?
        } else {
            0
        };
        let lane_align =
            dpcd::read(aux, dpcd::LANE_ALIGN_STATUS_UPDATED).map_err(Error::DpcdRead)?;
        let eq_mask = dpcd::LANE0_CR_DONE | dpcd::LANE0_CHANNEL_EQ_DONE | dpcd::LANE0_SYMBOL_LOCKED;
        if lanes_done(st01, st23, lanes, eq_mask)
            && (lane_align & dpcd::INTERLANE_ALIGN_DONE) != 0
        {
            // Done. Stop training, return to IDLE.
            ml.set_pattern(Pattern::Idle, false, enhanced_framing);
            dpcd::write(aux, dpcd::TRAINING_PATTERN_SET, 0x00).map_err(Error::DpcdWrite)?;
            return Ok(stats);
        }
        if !lanes_done(st01, st23, lanes, dpcd::LANE0_CR_DONE) {
            return Err(Error::CrLost);
        }
        let adjust =
            dpcd::read(aux, dpcd::ADJUST_REQUEST_LANE0_1).map_err(Error::DpcdRead)?;
        drive = DriveSetting::from_adjust_lane0(adjust);
    }

    Err(Error::EqFailed)
}
