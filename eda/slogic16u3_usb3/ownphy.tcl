# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
# Our USB 3.0 PHY on the GW5AT-15 quad, for the SLogic16U3 designs (slogic16u3_usb3, slogic16u3_la):
# sourced by their project.tcl. The GUI-generated USB 3.0 PHY IP (src/slogic16u3/usb3_ln0) provides
# serdes.v (the GTR12 quad instance and its wiring); a copy of it is made with
#   OWNPHY: usb3_softphy.v (+ rtl/usb3 usb3_phy_*) in place of Gowin's encrypted USB3_0_PHY_Top
#   NOARB:  quad_drp_mux.v in place of the encrypted upar arbiter; its channel x on SerDes_Top
#           XDRP_i {req, wr, addr[23:0], wdata[31:0]} / XDRP_o {init_done, done, rdata[31:0]}
#   QCSR:   the quad's static configuration written from a ROM by quad_drp_mux.v (csr/gw5at15_csr.py),
#           and the CSR file given to PnR cut down to QCSR_STATIC ("none": empty, "full": the IP's)
# Each defaults to on (env OWNPHY / NOARB / QCSR = 0 turns it off, each needs the one before).

set OWNPHY_DIR [file dirname [file normalize [info script]]]

proc ownphy_flag {name default} {
    if {[info exists ::env($name)] && $::env($name) ne ""} { return [expr {$::env($name) eq "1"}] }
    return $default
}

# reads the settings; returns the Verilog defines they need (QUAD_XDRP, QUAD_CSR_INIT)
proc ownphy_config {{own_default 1}} {
    global OWNPHY NOARB QCSR QCSR_STATIC QCSR_ARGS
    set OWNPHY [ownphy_flag OWNPHY $own_default]
    set NOARB [expr {$OWNPHY && [ownphy_flag NOARB 1]}]
    set QCSR [expr {$NOARB && [ownphy_flag QCSR 1]}]
    set QCSR_STATIC [expr {[info exists ::env(QCSR_STATIC)] && $::env(QCSR_STATIC) ne "" ? $::env(QCSR_STATIC) : "none"}]
    set QCSR_ARGS [expr {[info exists ::env(QCSR_ARGS)] ? $::env(QCSR_ARGS) : ""}]
    set defs ""
    if {$NOARB} { append defs "`define QUAD_XDRP\n" }
    if {$QCSR} { append defs "`define QUAD_CSR_INIT\n" }
    return $defs
}

# the serdes.v copy (text in sv_var) and the source files that go with it
proc ownphy_serdes {sv_var SRC_DIR RTL_DIR} {
    global OWNPHY NOARB QCSR QCSR_ARGS OWNPHY_DIR
    upvar $sv_var sv
    if {$OWNPHY} {
        if {[regsub {USB3_0_PHY_Top USB3_0_PHY_Top_inst \(} $sv "usb3_softphy USB3_0_PHY_Top_inst (\n    .serdes_rxdet_result_i(q0_fabric_ln0_rxdet_result)," sv] != 1} { error "OWNPHY: USB3_0_PHY_Top_inst not found" }
        foreach f {usb3_phy_pkg usb3_phy_tx usb3_phy_rx usb3_phy_eb usb3_phy_ctl} {
            add_file -type verilog [file normalize ${RTL_DIR}/usb3/${f}.sv]
        }
        add_file -type verilog [file normalize ${OWNPHY_DIR}/src/slogic16u3/usb3_softphy.v]
    }
    if {$NOARB} {
        set d "upar_arbiter_wrap_SerDes_Top_inst"
        set direct [join [list \
            "input \[57:0\] XDRP_i;" "output \[33:0\] XDRP_o;" \
            "assign upar_rst = 1'b0;" "assign upar_bus_width_s = 1'b0;" \
            "assign ${d}_drp_clk_o\[0\] = q0_fabric_cm_life_clk_o;" "assign ${d}_drp_resp_o\[0\] = 1'b0;" \
            "quad_drp_mux u_quad_drp_mux (.clk(q0_fabric_cm_life_clk_o)," \
            "    .p_wren(${d}_drp_wren_i\[0\]), .p_rden(${d}_drp_rden_i\[0\]), .p_addr(${d}_drp_addr_i\[23:0\])," \
            "    .p_wrdata(${d}_drp_wrdata_i\[31:0\]), .p_strb(${d}_drp_strb_i\[7:0\]), .p_ready(${d}_drp_ready_o\[0\])," \
            "    .p_rdvld(${d}_drp_rdvld_o\[0\]), .p_rddata(${d}_drp_rddata_o\[31:0\])," \
            "    .x_req(XDRP_i\[57\]), .x_wr(XDRP_i\[56\]), .x_addr(XDRP_i\[55:32\]), .x_wdata(XDRP_i\[31:0\])," \
            "    .x_done(XDRP_o\[32\]), .x_rdata(XDRP_o\[31:0\]), .init_done(XDRP_o\[33\])," \
            "    .wren(upar_wren_s), .rden(upar_rden_s), .addr(upar_addr_s), .wrdata(upar_wrdata_s), .strb(upar_strb_s)," \
            "    .ready(upar_ready_s), .rdvld(upar_rdvld_s), .rddata(upar_rddata_s));"] "\n"]
        if {[regsub {\\~upar_arbiter_wrap\.SerDes_Top upar_arbiter_wrap_SerDes_Top_inst \(.*?\n\);\n} $sv "$direct\n" sv] != 1} { error "NOARB: arbiter instance not found" }
        if {[regsub {module SerDes_Top \(} $sv "module SerDes_Top (XDRP_i, XDRP_o, " sv] != 1} { error "NOARB: SerDes_Top header not found" }
        add_file -type verilog [file normalize ${OWNPHY_DIR}/src/slogic16u3/quad_drp_mux.v]
    }
    if {$QCSR} {
        exec python3 ${OWNPHY_DIR}/csr/gw5at15_csr.py --verilog -o [file normalize quad_csr_rom.vh] {*}$QCSR_ARGS
        set_option -include_path [file normalize .]
    }
}

# the IP's other files, without the ones replaced
proc ownphy_ip_files {IPDIR} {
    global OWNPHY NOARB
    foreach f [glob -nocomplain ${IPDIR}/*/*.v] {
        if {[string match *_tmp.v $f]} continue
        if {$OWNPHY && [string match */usb3_0_phy/* $f]} continue
        if {$NOARB && [string match */upar_arbiter/* $f]} continue
        add_file -type verilog $f
    }
}

# SDC text: without the arbiter the register port runs straight in the quad's clock
proc ownphy_sdc {sdc} {
    global NOARB
    if {$NOARB} {
        set sdc [string map [list {u_serdes/upar_arbiter_wrap_SerDes_Top_inst_drp_clk_o[0]} {u_serdes/q0_fabric_cm_life_clk_o}] $sdc]
    }
    return $sdc
}

# the CSR file for PnR
proc ownphy_csr {IPDIR} {
    global QCSR QCSR_STATIC QCSR_ARGS OWNPHY_DIR
    if {!$QCSR || $QCSR_STATIC eq "full"} { return ${IPDIR}/serdes.csr }
    set csr [file normalize serdes_static.csr]
    set keep {}
    foreach p [split $QCSR_STATIC ","] { lappend keep --keep $p }
    exec python3 ${OWNPHY_DIR}/csr/gw5at15_csr.py {*}$keep -o $csr {*}$QCSR_ARGS
    return $csr
}
