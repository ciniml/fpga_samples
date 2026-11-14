// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
//! Cartridge bus test of the FPGA cartridge adapter (gb_fpga_cart_de0 + Tang Primer 25K running
//! eda/cart_target) from a ModRetro Chromatic running eda/chromatic_cart_bustest. Both ends check
//! every bus cycle on their own (rtl/chromatic/bt_pkg.veryl), so a failure is located by
//! direction and by line.

mod link;
mod proto;

use clap::{Parser, Subcommand};
use link::{Link, SerialLink, Sim, UsbLink};
use proto::*;
use std::time::Duration;

#[derive(Parser)]
#[command(version, about = "Cartridge bus test: Chromatic (eda/chromatic_cart_bustest) <-> adapter <-> target (eda/cart_target)")]
struct Cli {
    /// both ends in the Verilator model (rtl/chromatic/test/bt, make simexe) instead of the hardware
    #[arg(long, global = true, value_name = "EXE")]
    sim: Option<String>,
    /// UART of the target board
    #[arg(long, global = true, default_value = "/dev/ttyUSB1")]
    tty: String,
    #[arg(long, global = true, default_value_t = 1_000_000)]
    baud: u32,
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// both ends' state
    Status,
    /// L0: every line, both directions, statically (and /RST both ways)
    Pins,
    /// PHI as measured by the target
    Phi,
    /// one sequence run, checked by both ends
    Run {
        /// fill, verify or mix
        #[arg(long, default_value = "mix")]
        op: String,
        /// all (0x0000-0xFFFF) or cart (0x0000-0x7FFF, 0xA000-0xBFFF)
        #[arg(long, default_value = "all")]
        region: String,
        #[arg(long, default_value_t = 65536)]
        count: u32,
        #[arg(long, default_value_t = 1)]
        seed: u32,
        /// target response delay (target clocks)
        #[arg(long, default_value_t = 0)]
        dly: u8,
        /// bus timing cyc,sample,wr_on,wr_off (60 MHz clocks)
        #[arg(long)]
        timing: Option<String>,
    },
    /// L0 + PHI + L1 at 1 us and 0.5 us cycles, all and cartridge regions
    Suite {
        /// MIX operations per run
        #[arg(long, default_value_t = 1_000_000)]
        mix: u32,
        /// leave out the static pin test
        #[arg(long)]
        no_pins: bool,
    },
    /// L2: cycle length x sample point (and the target response delay)
    Shmoo {
        /// cycle lengths (60 MHz clocks)
        #[arg(long, default_value = "60,30,24,20,16,14,12,10,8")]
        cycles: String,
        /// target response delays (target clocks at 100 MHz)
        #[arg(long, default_value = "0")]
        dly: String,
        /// operations per verify
        #[arg(long, default_value_t = 16384)]
        count: u32,
    },
}

struct Bench {
    m: Master<Box<dyn Link>>,
    t: Target<Box<dyn Link>>,
    /// PHI meter window (s): 1 on hardware, 0.001 in the model
    window: f64,
}

/// default write strobe for a cycle length
fn timing_for(cyc: u8) -> (u8, u8) {
    let on = (cyc / 2).saturating_sub(1).max(3);
    let off = (cyc - 4).max(on + 1);
    (on, off)
}

fn op_of(s: &str) -> Result<u8, String> {
    match s {
        "fill" => Ok(OP_FILL),
        "verify" => Ok(OP_VERIFY),
        "mix" => Ok(OP_MIX),
        _ => Err(format!("unknown op '{s}'")),
    }
}

fn op_name(op: u8) -> &'static str { ["FILL", "VERIFY", "MIX", "?"][op as usize & 3] }

struct RunReport {
    m: MResult,
    t: TStatus,
}

impl RunReport {
    fn ok(&self, count: u32) -> bool {
        self.m.status == 0 && self.m.ops == count && self.m.errors == 0 && self.t.seen == count && self.t.errs == 0 && self.t.extra == 0
    }
    fn line(&self, count: u32) -> String {
        let mut s = format!(
            "master {} ops {} read errors (data xor {:02x}), target {} cycles {} errors (addr xor {:04x}, data xor {:02x}, r/w {}, /CS {}, extra {}), {:.2} s",
            self.m.ops, self.m.errors, self.m.xor_or, self.t.seen, self.t.errs, self.t.axor, self.t.dxor, self.t.rwerr, self.t.cserr,
            self.t.extra, self.m.us as f64 / 1e6
        );
        if self.m.status != 0 {
            s += &format!(" [master refused: {}]", if self.m.status == 1 { "locked" } else { "not ready" });
        }
        if self.m.errors != 0 {
            s += &format!("\n      first read error: op {} addr {:04x} expected {:02x} read {:02x}", self.m.f_idx, self.m.f_addr, self.m.f_exp, self.m.f_got);
        }
        if self.t.errs != 0 {
            s += &format!(
                "\n      first target error: cycle {} saw {} {:04x} d {:02x} /CS {}, expected {} {:04x} d {:02x} /CS {}",
                self.t.f_idx,
                if self.t.f_flags & 1 != 0 { "W" } else { "R" }, self.t.f_oa, self.t.f_od, self.t.f_flags >> 2 & 1,
                if self.t.f_flags & 2 != 0 { "W" } else { "R" }, self.t.f_ea, self.t.f_ed, self.t.f_flags >> 3 & 1
            );
        }
        if !self.ok(count) && self.m.errors == 0 && self.t.errs == 0 {
            s += " [count mismatch]";
        }
        s
    }
}

impl Bench {
    fn sleep(&self, hw: f64) {
        std::thread::sleep(Duration::from_secs_f64(if self.window < 1.0 { hw * 0.01 } else { hw }));
    }

    /// power the slot and unlock the master (target in ID mode)
    fn setup(&mut self) -> Result<(), String> {
        let s = self.m.power_up()?;
        self.t.drive(false, 0)?;
        self.t.rst_drv(false)?;
        self.m.rst_force(false)?;
        self.m.static_pins(false, 0, 0x27, 0)?;
        if !s.unlocked() {
            self.t.mode(0, 0)?;
            let (ok, got) = self.m.handshake()?;
            if !ok {
                return Err(format!("handshake failed (read {got:02x?}): is the target in the slot and running eda/cart_target?"));
            }
        }
        Ok(())
    }

    fn run(&mut self, op: u8, cart: bool, seed: u32, count: u32, dly: u8) -> Result<RunReport, String> {
        self.t.mode(if cart { 2 } else { 1 }, dly)?;
        self.t.arm(op, cart, seed, count)?;
        let m = self.m.run(op, cart, seed, count)?;
        let t = self.t.status()?;
        Ok(RunReport { m, t })
    }

    /// L0: returns the failures
    fn pins(&mut self) -> Result<Vec<String>, String> {
        let mut bad = Vec::new();
        self.t.mode(3, 0)?;
        let names = |i: usize| -> String {
            match i {
                0..=15 => format!("A{i}"),
                16 => "/RD".into(),
                17 => "/WR".into(),
                18 => "/CS".into(),
                _ => "PHI".into(),
            }
        };
        // console -> target: A0-A15, /RD, /WR, /CS, PHI (D not driven)
        let mut pats: Vec<u32> = vec![0, 0xFFFFF];
        for i in 0..20 {
            pats.push(1 << i);
            pats.push(0xFFFFF ^ (1 << i));
        }
        let mut seen_bad = 0u32;
        for &p in &pats {
            let ctl = ((p >> 16) & 0xF) as u8 | 0x20;
            self.m.static_pins(true, p as u16, ctl, 0)?;
            let s = self.t.status()?;
            let got = s.a as u32 | ((s.ctl as u32 & 0xF) << 16);
            seen_bad |= got ^ p;
        }
        for i in 0..20 {
            if seen_bad >> i & 1 != 0 {
                bad.push(format!("{} (console -> target) does not follow", names(i)));
            }
        }
        // console -> target: D
        let mut dpats: Vec<u8> = vec![0x00, 0xFF];
        for i in 0..8 {
            dpats.push(1 << i);
            dpats.push(!(1u8 << i));
        }
        let mut dbad = 0u8;
        for &p in &dpats {
            self.m.static_pins(true, 0, 0x17, p)?;
            let s = self.t.status()?;
            dbad |= s.d ^ p;
        }
        for i in 0..8 {
            if dbad >> i & 1 != 0 {
                bad.push(format!("D{i} (console -> target) does not follow"));
            }
        }
        // target -> console: D
        self.m.static_pins(true, 0, 0x27, 0)?;
        let mut rbad = 0u8;
        for &p in &dpats {
            self.t.drive(true, p)?;
            self.m.static_pins(true, 0, 0x27, 0)?;
            let got = self.m.static_pins(true, 0, 0x27, 0)?;
            rbad |= got ^ p;
        }
        self.t.drive(false, 0)?;
        for i in 0..8 {
            if rbad >> i & 1 != 0 {
                bad.push(format!("D{i} (target -> console) does not follow"));
            }
        }
        self.m.static_pins(false, 0, 0x27, 0)?;
        // /RST: target pulls it, the console sees it; the console holds it, the target sees it
        self.t.rst_drv(true)?;
        self.sleep(0.01);
        if self.m.status()?.rst_high {
            bad.push("RST_DRV: the console does not see /RST Low".into());
        }
        self.t.rst_drv(false)?;
        self.sleep(0.01);
        if !self.m.status()?.rst_high {
            bad.push("/RST stays Low after RST_DRV is released".into());
        }
        self.m.rst_force(true)?;
        self.sleep(0.01);
        if self.t.status()?.ctl & 0x10 != 0 {
            bad.push("/RST (console -> target) Low not seen".into());
        }
        self.m.rst_force(false)?;
        self.sleep(0.01);
        if self.t.status()?.ctl & 0x10 == 0 {
            bad.push("/RST (console -> target) High not seen".into());
        }
        // the static mode may have dropped the unlock if the slot went off: check
        if !self.m.status()?.unlocked() {
            return Err("the master is no longer unlocked after the pin test".into());
        }
        Ok(bad)
    }

    fn phi(&mut self) -> Result<(f64, f64), String> {
        self.sleep(2.2);
        let s = self.t.status()?;
        let f = s.phi_edges as f64 / self.window;
        // the target counts PHI-High samples at its clock over one window (100 MHz x window)
        let duty = s.phi_high as f64 / (self.window * 100e6);
        Ok((f, duty))
    }
}

fn parse_list(s: &str) -> Result<Vec<u8>, String> {
    s.split(',').map(|x| x.trim().parse::<u8>().map_err(|e| format!("{x}: {e}"))).collect()
}

fn run_cli(b: &mut Bench, cmd: &Cmd) -> Result<bool, String> {
    match cmd {
        Cmd::Status => {
            println!("master: {}", b.m.status()?.describe());
            let t = b.t.status()?;
            println!(
                "target: mode {} dly {} / a {:04x} ctl {:05b} (/RST PHI /CS /WR /RD) d {:02x} / reads {} writes {} / PHI {} edges per window",
                t.mode, t.dly, t.a, t.ctl, t.d, t.rd_cnt, t.wr_cnt, t.phi_edges
            );
            Ok(true)
        }
        Cmd::Pins => {
            b.setup()?;
            let bad = b.pins()?;
            if bad.is_empty() {
                println!("L0: all 28 lines and /RST follow in both directions");
            } else {
                for x in &bad {
                    println!("L0 FAIL: {x}");
                }
            }
            Ok(bad.is_empty())
        }
        Cmd::Phi => {
            b.setup()?;
            let (f, d) = b.phi()?;
            println!("PHI {:.0} Hz, duty {:.1} %", f, d * 100.0);
            Ok(true)
        }
        Cmd::Run { op, region, count, seed, dly, timing } => {
            b.setup()?;
            if let Some(t) = timing {
                let v = parse_list(t)?;
                if v.len() != 4 {
                    return Err("--timing cyc,sample,wr_on,wr_off".into());
                }
                b.m.timing(v[0], v[1], v[2], v[3])?;
            }
            let op = op_of(op)?;
            let cart = region == "cart";
            let r = b.run(op, cart, *seed, *count, *dly)?;
            println!("{} {} {}: {}", op_name(op), region, if r.ok(*count) { "PASS" } else { "FAIL" }, r.line(*count));
            Ok(r.ok(*count))
        }
        Cmd::Suite { mix, no_pins } => {
            b.setup()?;
            let mut all_ok = true;
            if !no_pins {
                let bad = b.pins()?;
                if bad.is_empty() {
                    println!("PASS L0 pins: 28 lines + /RST, both directions");
                } else {
                    all_ok = false;
                    for x in &bad {
                        println!("FAIL L0 {x}");
                    }
                }
            }
            let (f, d) = b.phi()?;
            println!("info PHI {:.0} Hz, duty {:.1} % (idle bus)", f, d * 100.0);
            for (name, cyc, sample) in [("1 us", 60u8, 57u8), ("0.5 us", 30, 27)] {
                let (on, off) = timing_for(cyc);
                b.m.timing(cyc, sample, on, off)?;
                for (cart, size) in [(false, 65536u32), (true, 40960)] {
                    let reg = if cart { "cart" } else { "all " };
                    let seed = 0x1234_5678 ^ cyc as u32 ^ (cart as u32) << 8;
                    for (op, count) in [(OP_FILL, size), (OP_VERIFY, size), (OP_MIX, *mix)] {
                        let r = b.run(op, cart, seed, count, 0)?;
                        let ok = r.ok(count);
                        all_ok &= ok;
                        println!("{} L1 {name} {reg} {:6} {}", if ok { "PASS" } else { "FAIL" }, op_name(op), r.line(count));
                    }
                }
            }
            b.m.timing(60, 57, 28, 56)?;
            println!("{}", if all_ok { "SUITE PASS" } else { "SUITE FAIL" });
            Ok(all_ok)
        }
        Cmd::Shmoo { cycles, dly, count } => {
            b.setup()?;
            let cycles = parse_list(cycles)?;
            let dlys = parse_list(dly)?;
            for &dl in &dlys {
                println!("target response delay {dl} (x10 ns); rows: cycle (60 MHz clocks / ns), columns: sample point; . = 0 errors, X = errors, w = write failed");
                for &cyc in &cycles {
                    let (on, off) = timing_for(cyc);
                    let mut row = format!("{cyc:3} {:5.0} ns |", cyc as f64 * 1000.0 / 60.0);
                    // writes at the safest sample (the sample point does not matter for writes)
                    b.m.timing(cyc, cyc - 1, on, off)?;
                    let w = b.run(OP_FILL, false, 0xC0FFEE ^ cyc as u32, *count, dl)?;
                    let wok = w.ok(*count);
                    for s in 2..cyc {
                        b.m.timing(cyc, s, on, off)?;
                        let r = b.run(OP_VERIFY, false, 0xC0FFEE ^ cyc as u32, *count, dl)?;
                        row.push(if !wok { 'w' } else if r.ok(*count) { '.' } else { 'X' });
                    }
                    println!("{row}");
                }
            }
            b.m.timing(60, 57, 28, 56)?;
            Ok(true)
        }
    }
}

fn main() {
    let cli = Cli::parse();
    let res = (|| -> Result<bool, String> {
        match &cli.sim {
            Some(exe) => {
                let (sim, mc, tg) = Sim::spawn(exe)?;
                let mut b = Bench { m: Master { link: Box::new(mc) }, t: Target { link: Box::new(tg) }, window: 0.001 };
                let r = run_cli(&mut b, &cli.cmd);
                drop(b);
                let fin = sim.finish();
                let ok = r?;
                fin?;
                Ok(ok)
            }
            None => {
                let mut b = Bench {
                    m: Master { link: Box::new(UsbLink::open()?) },
                    t: Target { link: Box::new(SerialLink::open(&cli.tty, cli.baud)?) },
                    window: 1.0,
                };
                run_cli(&mut b, &cli.cmd)
            }
        }
    })();
    match res {
        Ok(true) => {}
        Ok(false) => std::process::exit(1),
        Err(e) => {
            eprintln!("error: {e}");
            std::process::exit(2);
        }
    }
}
