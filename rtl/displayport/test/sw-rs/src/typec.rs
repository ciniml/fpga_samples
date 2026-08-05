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

/// Polls with no reply before the current request is re-sent
/// (~0.5 s at the main loop's ~1 ms poll cadence).
const RESEND_POLLS: u32 = 500;

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
    /// Orientation decided at attach (true = flipped, CC2 active).
    pub pol_flipped: bool,
    substep: u8,
    settle: u32,
    /// Polls since the last RX (or resend) in a waiting state.
    age: u32,
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
            pol_flipped: false,
            substep: 0,
            settle: 0,
            age: 0,
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
        crate::pd_trace('>', h, &[]);
        let _ = self.phy.send_sop(h, &[]);
    }

    fn send_data(&mut self, t: u8, objs: &[u32]) {
        let id = self.next_msg_id();
        let h = pd::header(t, objs.len() as u8, id, true, true);
        crate::pd_trace('>', h, objs);
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
        crate::pd_trace('>', h, &objs[..n]);
        let _ = self.phy.send_sop(h, &objs[..n]);
    }

    /// Traced wrapper around the PHY receive: every SOP frame that
    /// reaches the policy engine shows up in the bring-up log.
    fn recv(&mut self, objs: &mut [u32; 7]) -> Option<(u16, usize)> {
        match self.phy.recv_sop(objs) {
            Ok(Some((h, n))) => {
                crate::pd_trace('<', h, &objs[..n]);
                self.age = 0;
                Some((h, n))
            }
            _ => None,
        }
    }

    /// Re-issue the last request for the current (state, substep) when
    /// the peer has been silent too long. PD peers legitimately miss
    /// messages (our first SourceCap can race their attach), and a
    /// polling engine has no timer-driven retry otherwise.
    fn resend_current(&mut self) {
        match (self.state, self.substep) {
            (TcState::Contracting, _) => {
                let pdo = pd::pdo_fixed_5v(3000);
                self.send_data(pd::DATA_SOURCE_CAPABILITIES, &[pdo]);
            }
            (TcState::Discovering, 0) => {
                self.send_vdm(pd::SVID_PD_SID, pd::VDM_CMD_DISCOVER_IDENTITY, &[])
            }
            (TcState::Discovering, 1) => {
                self.send_vdm(pd::SVID_PD_SID, pd::VDM_CMD_DISCOVER_SVIDS, &[])
            }
            (TcState::Discovering, 2) => {
                self.send_vdm(pd::SVID_DISPLAYPORT, pd::VDM_CMD_DISCOVER_MODES, &[])
            }
            (TcState::Discovering, _) => {
                self.send_vdm(pd::SVID_DISPLAYPORT, pd::VDM_CMD_ENTER_MODE, &[])
            }
            (TcState::ModeEntered, 0) => self.send_vdm(
                pd::SVID_DISPLAYPORT,
                pd::VDM_CMD_DP_STATUS_UPDATE,
                &[pd::dp_status_dfp_d()],
            ),
            (TcState::ModeEntered, _) => {
                let pin = if self.ufp_d_assignments & pd::DP_PIN_ASSIGN_C != 0 {
                    pd::DP_PIN_ASSIGN_C
                } else {
                    pd::DP_PIN_ASSIGN_D
                };
                self.send_vdm(pd::SVID_DISPLAYPORT, pd::VDM_CMD_DP_CONFIGURE, &[pd::dp_configure(pin)]);
            }
            _ => {}
        }
        self.age = 0;
    }

    /// Bring-up aid: read VBUS through the PHY's MDAC comparator.
    pub fn vbus_mv(&mut self) -> u32 {
        self.phy.measure_vbus_mv().unwrap_or(0)
    }

    /// Bring-up aid: fire a DP Status Update query regardless of state
    /// so CC-side liveness can be checked while AUX is dead. The ACK
    /// (or its absence) shows up in the PD trace.
    pub fn query_status(&mut self) {
        self.send_vdm(
            pd::SVID_DISPLAYPORT,
            pd::VDM_CMD_DP_STATUS_UPDATE,
            &[pd::dp_status_dfp_d()],
        );
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
                self.pol_flipped = self.cc == Cc::Cc2;
                crate::typec_gpio(true, self.pol_flipped, true, AMSEL_4LANE_DP);
                // Announce our capabilities.
                let pdo = pd::pdo_fixed_5v(3000);
                self.send_data(pd::DATA_SOURCE_CAPABILITIES, &[pdo]);
                self.substep = 0;
                self.state = TcState::Contracting;
                None
            }
            TcState::Contracting => {
                let mut objs = [0u32; 7];
                if let Some((h, _n)) = self.recv(&mut objs) {
                    match pd::hdr_msg_type(h) {
                        pd::DATA_REQUEST => {
                            self.send_ctrl(pd::CTRL_ACCEPT);
                            self.send_ctrl(pd::CTRL_PS_RDY);
                            self.substep = 0;
                            self.age = 0;
                            self.state = TcState::Discovering;
                            // Kick off the alt-mode discovery.
                            self.send_vdm(pd::SVID_PD_SID, pd::VDM_CMD_DISCOVER_IDENTITY, &[]);
                        }
                        pd::CTRL_GET_SOURCE_CAP => {
                            let pdo = pd::pdo_fixed_5v(3000);
                            self.send_data(pd::DATA_SOURCE_CAPABILITIES, &[pdo]);
                        }
                        _ => {}
                    }
                } else {
                    self.age += 1;
                    if self.age > RESEND_POLLS {
                        self.resend_current();
                    }
                }
                None
            }
            TcState::Discovering => {
                let mut objs = [0u32; 7];
                if let Some((h, n)) = self.recv(&mut objs) {
                    if pd::hdr_msg_type(h) == pd::DATA_VENDOR_DEFINED && n >= 1 {
                        let vh = objs[0];
                        if pd::vdm_cmd_type(vh) == pd::VDM_ACK {
                            match pd::vdm_command(vh) {
                                pd::VDM_CMD_DISCOVER_IDENTITY => {
                                    self.substep = 1;
                                    self.send_vdm(pd::SVID_PD_SID, pd::VDM_CMD_DISCOVER_SVIDS, &[]);
                                }
                                pd::VDM_CMD_DISCOVER_SVIDS => {
                                    // Assume DP SVID present (checked in
                                    // the modes step anyway).
                                    self.substep = 2;
                                    self.send_vdm(pd::SVID_DISPLAYPORT, pd::VDM_CMD_DISCOVER_MODES, &[]);
                                }
                                pd::VDM_CMD_DISCOVER_MODES => {
                                    if n >= 2 {
                                        self.ufp_d_assignments = pd::dp_mode_pin_assignments(objs[1]);
                                    }
                                    self.substep = 3;
                                    self.send_vdm(pd::SVID_DISPLAYPORT, pd::VDM_CMD_ENTER_MODE, &[]);
                                }
                                pd::VDM_CMD_ENTER_MODE => {
                                    self.state = TcState::ModeEntered;
                                    self.substep = 0;
                                    self.send_vdm(
                                        pd::SVID_DISPLAYPORT,
                                        pd::VDM_CMD_DP_STATUS_UPDATE,
                                        &[pd::dp_status_dfp_d()],
                                    );
                                }
                                pd::VDM_CMD_EXIT_MODE => {
                                    // Stale mode cleared: enter again.
                                    self.send_vdm(pd::SVID_DISPLAYPORT, pd::VDM_CMD_ENTER_MODE, &[]);
                                }
                                _ => {}
                            }
                        } else if pd::vdm_cmd_type(vh) == pd::VDM_NAK {
                            match pd::vdm_command(vh) {
                                pd::VDM_CMD_ENTER_MODE => {
                                    // Likely still in DP mode from a
                                    // previous run that never exited:
                                    // exit, then re-enter on its ACK.
                                    self.send_vdm(pd::SVID_DISPLAYPORT, pd::VDM_CMD_EXIT_MODE, &[]);
                                }
                                pd::VDM_CMD_EXIT_MODE => {
                                    self.send_vdm(pd::SVID_DISPLAYPORT, pd::VDM_CMD_ENTER_MODE, &[]);
                                }
                                _ => {}
                            }
                        }
                    }
                } else {
                    self.age += 1;
                    if self.age > RESEND_POLLS {
                        self.resend_current();
                    }
                }
                None
            }
            TcState::ModeEntered => {
                let mut objs = [0u32; 7];
                let rx = self.recv(&mut objs);
                if rx.is_none() {
                    self.age += 1;
                    if self.age > RESEND_POLLS {
                        self.resend_current();
                    }
                    return None;
                }
                if let Some((h, n)) = rx {
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
                            self.substep = 1;
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
                // Steady state: watch for Attention (HPD changes), and
                // while HPD is still low actively re-query DP Status —
                // some adapters never volunteer an Attention.
                let mut objs = [0u32; 7];
                if let Some((h, n)) = self.recv(&mut objs) {
                    if pd::hdr_msg_type(h) == pd::DATA_VENDOR_DEFINED
                        && n >= 2
                        && pd::vdm_svid(objs[0]) == pd::SVID_DISPLAYPORT
                    {
                        let cmd = pd::vdm_command(objs[0]);
                        if cmd == pd::VDM_CMD_ATTENTION
                            || (cmd == pd::VDM_CMD_DP_STATUS_UPDATE
                                && pd::vdm_cmd_type(objs[0]) == pd::VDM_ACK)
                        {
                            self.sink_dp_status = objs[1];
                            return Some((
                                pd::dp_status_hpd(self.sink_dp_status),
                                pd::dp_status_irq_hpd(self.sink_dp_status),
                            ));
                        }
                    }
                } else {
                    self.age += 1;
                    if !pd::dp_status_hpd(self.sink_dp_status) && self.age > 4 {
                        self.send_vdm(
                            pd::SVID_DISPLAYPORT,
                            pd::VDM_CMD_DP_STATUS_UPDATE,
                            &[pd::dp_status_dfp_d()],
                        );
                        self.age = 0;
                    }
                }
                None
            }
            TcState::Failed => None,
        }
    }
}
