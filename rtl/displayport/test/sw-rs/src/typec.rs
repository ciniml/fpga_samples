//! Type-C DP alt-mode SOURCE policy engine (polling, single-threaded).
//!
//! Drives the FUSB302B through: attach detection -> orientation ->
//! (board mux GPIOs) -> PD contract (5 V fixed) -> DP alt mode VDM
//! sequence -> virtual HPD mirroring. Call `poll()` from the main
//! loop; it never blocks for long.
//!
//! GPIO map (cpu_io_out bits, see typec_board_kicad_notes.md):
//!   bit 24 = HD3SS460 EN, bit 25 = HD3SS460 POL (1 = flipped),
//!   bit 26 = VBUS_EN.

use crate::fusb302::{Cc, Fusb302};
use crate::pd;

/// HD3SS460 AMSEL level selecting the 4-lane DP mode.
/// TODO: verify the level against the HD3SS460 datasheet mode table on
/// the bench (runtime-flippable via the UART FW loader if wrong).
const AMSEL_4LANE_DP: bool = true;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TcState {
    Detached,
    AttachWait,
    Contracting,
    Discovering,
    ModeEntered,
    Configured,
    Failed,
}

pub struct TypeC<'a> {
    phy: Fusb302<'a>,
    pub state: TcState,
    msg_id: u8,
    cc: Cc,
    /// Latest sink DP status VDO (HPD lives here).
    pub sink_dp_status: u32,
    /// Discovered UFP_D pin assignment capabilities.
    pub ufp_d_assignments: u8,
    substep: u8,
    settle: u32,
}

impl<'a> TypeC<'a> {
    pub fn new(phy: Fusb302<'a>) -> Self {
        Self {
            phy,
            state: TcState::Detached,
            msg_id: 0,
            cc: Cc::Cc1,
            sink_dp_status: 0,
            ufp_d_assignments: 0,
            substep: 0,
            settle: 0,
        }
    }

    pub fn init(&mut self) -> bool {
        self.phy.init_source().is_ok()
    }

    fn next_msg_id(&mut self) -> u8 {
        let id = self.msg_id;
        self.msg_id = (self.msg_id + 1) & 0x7;
        id
    }

    fn send_ctrl(&mut self, t: u8) {
        let id = self.next_msg_id();
        let h = pd::header(t, 0, id, true, true);
        let _ = self.phy.send_sop(h, &[]);
    }

    fn send_data(&mut self, t: u8, objs: &[u32]) {
        let id = self.next_msg_id();
        let h = pd::header(t, objs.len() as u8, id, true, true);
        let _ = self.phy.send_sop(h, objs);
    }

    fn send_vdm(&mut self, svid: u16, cmd: u8, tail: &[u32]) {
        let mut objs = [0u32; 7];
        objs[0] = pd::vdm_header(svid, if cmd >= pd::VDM_CMD_ENTER_MODE { 1 } else { 0 },
                                 pd::VDM_INITIATOR, cmd);
        let n = 1 + tail.len();
        objs[1..n].copy_from_slice(tail);
        let id = self.next_msg_id();
        let h = pd::header(pd::DATA_VENDOR_DEFINED, n as u8, id, true, true);
        let _ = self.phy.send_sop(h, &objs[..n]);
    }

    /// One polling step. Returns Some((hpd, irq)) whenever the sink's
    /// HPD state (from Status Update / Attention) changed.
    pub fn poll(&mut self) -> Option<(bool, bool)> {
        match self.state {
            TcState::Detached => {
                // Probe both CC pins for Rd.
                let c1 = self.phy.measure_cc(Cc::Cc1).unwrap_or(0);
                let c2 = self.phy.measure_cc(Cc::Cc2).unwrap_or(0);
                if c1 != 0 || c2 != 0 {
                    self.cc = if c1 >= c2 { Cc::Cc1 } else { Cc::Cc2 };
                    self.settle = 0;
                    self.state = TcState::AttachWait;
                }
                None
            }
            TcState::AttachWait => {
                // Debounce (tCCDebounce-ish; poll cadence is the timer).
                self.settle += 1;
                if self.settle < 20 {
                    return None;
                }
                let lvl = self.phy.measure_cc(self.cc).unwrap_or(0);
                if lvl == 0 {
                    self.state = TcState::Detached;
                    return None;
                }
                if self.phy.configure_attached(self.cc).is_err() {
                    self.state = TcState::Failed;
                    return None;
                }
                // Board mux: EN + polarity + AMSEL, then VBUS on.
                let pol_flipped = self.cc == Cc::Cc2;
                crate::typec_gpio(true, pol_flipped, true, AMSEL_4LANE_DP);
                // Announce our capabilities.
                let pdo = pd::pdo_fixed_5v(900);
                self.send_data(pd::DATA_SOURCE_CAPABILITIES, &[pdo]);
                self.substep = 0;
                self.state = TcState::Contracting;
                None
            }
            TcState::Contracting => {
                let mut objs = [0u32; 7];
                match self.phy.recv_sop(&mut objs) {
                    Ok(Some((h, _n))) => {
                        match pd::hdr_msg_type(h) {
                            pd::DATA_REQUEST => {
                                self.send_ctrl(pd::CTRL_ACCEPT);
                                self.send_ctrl(pd::CTRL_PS_RDY);
                                self.substep = 0;
                                self.state = TcState::Discovering;
                                // Kick off the alt-mode discovery.
                                self.send_vdm(pd::SVID_PD_SID, pd::VDM_CMD_DISCOVER_IDENTITY, &[]);
                            }
                            pd::CTRL_GET_SOURCE_CAP => {
                                let pdo = pd::pdo_fixed_5v(900);
                                self.send_data(pd::DATA_SOURCE_CAPABILITIES, &[pdo]);
                            }
                            _ => {}
                        }
                    }
                    _ => {}
                }
                None
            }
            TcState::Discovering => {
                let mut objs = [0u32; 7];
                if let Ok(Some((h, n))) = self.phy.recv_sop(&mut objs) {
                    if pd::hdr_msg_type(h) == pd::DATA_VENDOR_DEFINED && n >= 1 {
                        let vh = objs[0];
                        if pd::vdm_cmd_type(vh) == pd::VDM_ACK {
                            match pd::vdm_command(vh) {
                                pd::VDM_CMD_DISCOVER_IDENTITY => {
                                    self.send_vdm(pd::SVID_PD_SID, pd::VDM_CMD_DISCOVER_SVIDS, &[]);
                                }
                                pd::VDM_CMD_DISCOVER_SVIDS => {
                                    // Assume DP SVID present (checked in
                                    // the modes step anyway).
                                    self.send_vdm(pd::SVID_DISPLAYPORT, pd::VDM_CMD_DISCOVER_MODES, &[]);
                                }
                                pd::VDM_CMD_DISCOVER_MODES => {
                                    if n >= 2 {
                                        self.ufp_d_assignments = pd::dp_mode_ufp_d_assignments(objs[1]);
                                    }
                                    self.send_vdm(pd::SVID_DISPLAYPORT, pd::VDM_CMD_ENTER_MODE, &[]);
                                }
                                pd::VDM_CMD_ENTER_MODE => {
                                    self.state = TcState::ModeEntered;
                                    self.send_vdm(
                                        pd::SVID_DISPLAYPORT,
                                        pd::VDM_CMD_DP_STATUS_UPDATE,
                                        &[pd::dp_status_dfp_d()],
                                    );
                                }
                                _ => {}
                            }
                        }
                    }
                }
                None
            }
            TcState::ModeEntered => {
                let mut objs = [0u32; 7];
                if let Ok(Some((h, n))) = self.phy.recv_sop(&mut objs) {
                    if pd::hdr_msg_type(h) == pd::DATA_VENDOR_DEFINED && n >= 1 {
                        let vh = objs[0];
                        if pd::vdm_cmd_type(vh) == pd::VDM_ACK
                            && pd::vdm_command(vh) == pd::VDM_CMD_DP_STATUS_UPDATE
                        {
                            if n >= 2 {
                                self.sink_dp_status = objs[1];
                            }
                            // Pick assignment C when offered (4 lanes);
                            // fall back to D (2 lanes, needs the
                            // 2-lane build) otherwise.
                            let pin = if self.ufp_d_assignments & pd::DP_PIN_ASSIGN_C != 0 {
                                pd::DP_PIN_ASSIGN_C
                            } else {
                                pd::DP_PIN_ASSIGN_D
                            };
                            self.send_vdm(
                                pd::SVID_DISPLAYPORT,
                                pd::VDM_CMD_DP_CONFIGURE,
                                &[pd::dp_configure(pin)],
                            );
                        } else if pd::vdm_cmd_type(vh) == pd::VDM_ACK
                            && pd::vdm_command(vh) == pd::VDM_CMD_DP_CONFIGURE
                        {
                            self.state = TcState::Configured;
                            return Some((
                                pd::dp_status_hpd(self.sink_dp_status),
                                pd::dp_status_irq_hpd(self.sink_dp_status),
                            ));
                        }
                    }
                }
                None
            }
            TcState::Configured => {
                // Steady state: watch for Attention (HPD changes).
                let mut objs = [0u32; 7];
                if let Ok(Some((h, n))) = self.phy.recv_sop(&mut objs) {
                    if pd::hdr_msg_type(h) == pd::DATA_VENDOR_DEFINED
                        && n >= 2
                        && pd::vdm_command(objs[0]) == pd::VDM_CMD_ATTENTION
                        && pd::vdm_svid(objs[0]) == pd::SVID_DISPLAYPORT
                    {
                        self.sink_dp_status = objs[1];
                        return Some((
                            pd::dp_status_hpd(self.sink_dp_status),
                            pd::dp_status_irq_hpd(self.sink_dp_status),
                        ));
                    }
                }
                None
            }
            TcState::Failed => None,
        }
    }
}
