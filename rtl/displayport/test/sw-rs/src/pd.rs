//! USB PD 2.0 message construction/parsing + DisplayPort alt mode VDMs.
//! Pure functions (no I/O) so the encoders are easy to eyeball against
//! the PD and DP-alt-mode specs.

/// PD header (rev 2.0). `msg_id` is masked to 3 bits.
pub fn header(msg_type: u8, ndo: u8, msg_id: u8, power_role_src: bool, data_role_dfp: bool) -> u16 {
    ((ndo as u16 & 0x7) << 12)
        | (((msg_id & 0x7) as u16) << 9)
        | ((power_role_src as u16) << 8)
        | (0b01 << 6) // spec rev 2.0
        | ((data_role_dfp as u16) << 5)
        | (msg_type as u16 & 0x1F)
}

pub fn hdr_msg_type(h: u16) -> u8 {
    (h & 0x1F) as u8
}
pub fn hdr_ndo(h: u16) -> usize {
    ((h >> 12) & 0x7) as usize
}
pub fn hdr_msg_id(h: u16) -> u8 {
    ((h >> 9) & 0x7) as u8
}

// Control message types
pub const CTRL_GOODCRC: u8 = 0x1;
pub const CTRL_ACCEPT: u8 = 0x3;
pub const CTRL_REJECT: u8 = 0x4;
pub const CTRL_PS_RDY: u8 = 0x6;
pub const CTRL_GET_SOURCE_CAP: u8 = 0x7;
// Data message types
pub const DATA_SOURCE_CAPABILITIES: u8 = 0x1;
pub const DATA_REQUEST: u8 = 0x2;
pub const DATA_VENDOR_DEFINED: u8 = 0xF;

/// Fixed-supply source PDO: 5 V, `ma` mA, dual-role none, no USB comm.
pub fn pdo_fixed_5v(ma: u32) -> u32 {
    let v50 = 5000 / 50; // 100 units of 50 mV
    let i10 = ma / 10;
    (v50 << 10) | i10
}

// ---------------------------------------------------------------------
// Structured VDM (header VDO)
// ---------------------------------------------------------------------
pub const SVID_PD_SID: u16 = 0xFF00;
pub const SVID_DISPLAYPORT: u16 = 0xFF01;

pub const VDM_CMD_DISCOVER_IDENTITY: u8 = 1;
pub const VDM_CMD_DISCOVER_SVIDS: u8 = 2;
pub const VDM_CMD_DISCOVER_MODES: u8 = 3;
pub const VDM_CMD_ENTER_MODE: u8 = 4;
pub const VDM_CMD_EXIT_MODE: u8 = 5;
pub const VDM_CMD_ATTENTION: u8 = 6;
pub const VDM_CMD_DP_STATUS_UPDATE: u8 = 0x10;
pub const VDM_CMD_DP_CONFIGURE: u8 = 0x11;

pub const VDM_INITIATOR: u8 = 0; // command type field
pub const VDM_ACK: u8 = 1;

/// Structured VDM header VDO.
pub fn vdm_header(svid: u16, obj_pos: u8, cmd_type: u8, command: u8) -> u32 {
    ((svid as u32) << 16)
        | (1 << 15) // structured
        | (((obj_pos & 0x7) as u32) << 8)
        | (((cmd_type & 0x3) as u32) << 6)
        | (command as u32 & 0x1F)
}

pub fn vdm_svid(vdo: u32) -> u16 {
    (vdo >> 16) as u16
}
pub fn vdm_command(vdo: u32) -> u8 {
    (vdo & 0x1F) as u8
}
pub fn vdm_cmd_type(vdo: u32) -> u8 {
    ((vdo >> 6) & 0x3) as u8
}

// ---------------------------------------------------------------------
// DP alt mode VDOs (VESA DP Alt Mode on USB Type-C standard)
// ---------------------------------------------------------------------

/// DP Capabilities mode VDO: UFP_D pin assignments supported (bits
/// 23:16) — the mask the SOURCE inspects to pick an assignment.
pub fn dp_mode_ufp_d_assignments(mode_vdo: u32) -> u8 {
    ((mode_vdo >> 16) & 0xFF) as u8
}
pub const DP_PIN_ASSIGN_C: u8 = 1 << 2;
pub const DP_PIN_ASSIGN_D: u8 = 1 << 3;
pub const DP_PIN_ASSIGN_E: u8 = 1 << 4;

/// DP Status Update VDO from the sink: HPD state (bit 7) and IRQ_HPD
/// (bit 8) — mirrored into the virtual HPD register.
pub fn dp_status_hpd(status_vdo: u32) -> bool {
    (status_vdo >> 7) & 1 != 0
}
pub fn dp_status_irq_hpd(status_vdo: u32) -> bool {
    (status_vdo >> 8) & 1 != 0
}
pub fn dp_status_multi_function_pref(status_vdo: u32) -> bool {
    (status_vdo >> 4) & 1 != 0
}

/// DP Configure VDO: select DP mode with the given UFP_U pin
/// assignment mask (single bit), DPv1.3 signalling.
pub fn dp_configure(pin_assign: u8) -> u32 {
    ((pin_assign as u32) << 8)
        | (0b01 << 2) // signalling: DP 1.3
        | 0b10 // configure UFP_U as UFP_D
}

/// Our DP Status VDO as the DFP_D source: enabled, no low-power.
pub fn dp_status_dfp_d() -> u32 {
    0b01 // DFP_D connected
}
