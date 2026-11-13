# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
# Gowin rejects constraints for ports that the design does not have (CT1135), so a design uses
#   source <targets/chromatic>/chromatic_cst.tcl
#   chromatic_cst <top.sv / top.v> <out.cst> ?<substitutions>?
# which copies chromatic.cst, keeping only the ports declared in the top module.
# <substitutions>: a list of {regexp replacement} applied to the filtered text (e.g. a HS USB dx pair).
set ::CHROMATIC_TARGET_DIR [file dirname [file normalize [info script]]]
proc chromatic_cst {top out {subst {}}} {
    set dir $::CHROMATIC_TARGET_DIR
    set fh [open $top r]; set src [read $fh]; close $fh
    # drop comments, then collect the declared port names
    regsub -all {//[^\n]*} $src {} src
    regsub -all {/\*.*?\*/} $src {} src
    set ports {}
    foreach {m name} [regexp -all -inline {(?:input|output|inout)\s+(?:wire\s+|logic\s+|reg\s+)?(?:signed\s+)?(?:\[[^\]]*\]\s*)?([A-Za-z_][A-Za-z0-9_]*)} $src] {
        dict set ports $name 1
    }
    set fh [open [file join $dir chromatic.cst] r]; set base [read $fh]; close $fh
    set result {}
    foreach line [split $base "\n"] {
        if {[regexp {^\s*IO_(?:LOC|PORT)\s+"?([A-Za-z_][A-Za-z0-9_]*)} $line -> name]} {
            if {![dict exists $ports $name]} { continue }
        }
        lappend result $line
    }
    set text [join $result "\n"]
    foreach {re rep} $subst {
        regsub -all -line $re $text $rep text
    }
    set fh [open $out w]; puts -nonewline $fh $text; close $fh
    return [file normalize $out]
}
