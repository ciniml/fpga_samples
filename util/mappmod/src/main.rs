use std::{path::Path, str::FromStr};

use anyhow::{Result, anyhow};
use clap::{Parser, ValueEnum};

const MAX_PMOD_PORTS: usize = 20;

const PMOD_SIGNAL_PIN_MAP: [usize; 8] = [1, 2, 3, 4, 7, 8, 9, 10];

#[derive(Debug, Clone, ValueEnum)]
enum PmodDirection {
    LeftToRight,
    RightToLeft,
}

#[derive(Parser, Debug)]
struct Cli {
    #[arg(long)]
    pmod_port_def: String,
    #[arg(long = "pmod")]
    pmods: Vec<String>,
    #[arg(long, default_value = "left-to-right")]
    direction: PmodDirection,   // unimplemented
    #[arg(long, default_value_t = 0)]
    port_offset: usize,
    #[arg(long)]
    output: Option<String>,
}

#[derive(Debug, Default)]
struct PmodPort {
    pins: [String; 8],
}

type PmodPorts = Vec<PmodPort>;

#[derive(Debug, Default)]
struct PmodUsage {
    pins: [Option<String>; 8],
}

#[derive(Debug, Default)]
struct PmodIndexAndPin {
    index: usize,
    pin: usize,
}

type PmodModule = Vec<PmodUsage>;


impl FromStr for PmodIndexAndPin {
    type Err = anyhow::Error;
    fn from_str(s: &str) -> std::result::Result<Self, Self::Err> {
        static PATTERN: once_cell::sync::OnceCell<regex::Regex> = once_cell::sync::OnceCell::new();
        let pattern = PATTERN.get_or_init(|| { regex::Regex::new(r"pmod(\d+)_(10|1|2|3|4|7|8|9)").unwrap() });
        let captures = pattern.captures(s).ok_or(anyhow!("invalid Pmod pin name"))?;
        let index = captures.get(1).unwrap();
        let pin = captures.get(2).unwrap();
        Ok(Self {
            index: str::parse(index.as_str()).map_err(|_| anyhow!("invalid Pmod index"))?,
            pin: str::parse(pin.as_str()).map_err(|_| anyhow!("invalid Pmod pin number"))?,
        })
    }
}

fn read_pmod_module(path: &Path) -> Result<PmodModule> {
    let mut reader = csv::Reader::from_path(path)?;
    let mut module = PmodModule::new();
    for result in reader.records() {
        let row = result?;
        let signal_name = &row[0];
        let pmod_pin = &row[1];
        let index_and_pin = PmodIndexAndPin::from_str(pmod_pin)?;
        if index_and_pin.index >= MAX_PMOD_PORTS {
            anyhow::bail!("Pmod index must be from 0 to {}, got {}", MAX_PMOD_PORTS-1, index_and_pin.index);
        }
        let index = index_and_pin.index;
        let pin_index = PMOD_SIGNAL_PIN_MAP.iter().enumerate().find(|(_, pin)| **pin == index_and_pin.pin).unwrap().0;
        while module.len() < index_and_pin.index + 1 {
            module.extend([PmodUsage::default()]);
        }
        module[index].pins[pin_index] = Some(signal_name.trim().into());
    }
    Ok(module)
}

fn read_pmod_ports(path: &Path) -> Result<PmodPorts> {
    let mut reader = csv::Reader::from_path(path)?;
    let mut defs = PmodPorts::new();
    for result in reader.records() {
        let row = result?;
        let pmod_pin = &row[0];
        let fpga_pin = &row[1];
        let index_and_pin = PmodIndexAndPin::from_str(pmod_pin)?;
        if index_and_pin.index >= MAX_PMOD_PORTS {
            anyhow::bail!("Pmod index must be from 0 to {}, got {}", MAX_PMOD_PORTS-1, index_and_pin.index);
        }
        let index = index_and_pin.index;
        let pin_index = PMOD_SIGNAL_PIN_MAP.iter().enumerate().find(|(_, pin)| **pin == index_and_pin.pin).unwrap().0;
        while defs.len() < index_and_pin.index + 1 {
            defs.extend([PmodPort::default()]);
        }
        defs[index].pins[pin_index] = fpga_pin.trim().into();
    }
    for (index, def) in defs.iter().enumerate() {
        for (pin_index, pin) in def.pins.iter().enumerate() {
            if pin.is_empty() {
                anyhow::bail!("pin#{} of Pmod {} is undefined.", PMOD_SIGNAL_PIN_MAP[pin_index], index);
            }
        }
    }
    Ok(defs)
}

fn assign_pmod_modules_to_ports(ports: &PmodPorts, modules: &Vec<PmodModule>, port_offset: usize, direction: PmodDirection) -> Result<Vec<(String, String)>> {
    let required_ports: usize = modules.iter().map(|module| module.len()).sum();
    if required_ports + port_offset > ports.len() {
        anyhow::bail!("Too few Pmod ports available. required: {}, available: {}", required_ports + port_offset, ports.len());
    }

    let mut pin_map = Vec::new();
    let modules_ports_iter: Box<dyn Iterator<Item = &PmodUsage>> = match direction {
        PmodDirection::LeftToRight => Box::new(modules.iter().map(|module| module.iter()).flatten()),
        PmodDirection::RightToLeft => Box::new(modules.iter().map(|module| module.iter()).flatten().rev()),
    };
    let ports_iter = ports.iter().skip(port_offset);
    for (module_port, port) in modules_ports_iter.zip(ports_iter) {
        for (module_pin, port_pin) in module_port.pins.iter().zip(port.pins.iter()) {
            match module_pin.as_ref() {
                Some(module_pin_name) => {
                    pin_map.push((module_pin_name.clone(), port_pin.clone()));
                },
                None => {},
            }
        }
    }
    Ok(pin_map)
}

fn write_pins_as_gowin_loc<W: std::io::Write>(writer: &mut W, pins: &Vec<(String, String)>) -> Result<()> {
    for (signal_name, location) in pins {
        writeln!(writer, "IO_LOC \"{}\" {}", signal_name, location)?;
    }
    Ok(())
}

fn main() {
    let args = Cli::parse();
    if args.pmods.len() == 0 {
        panic!("At least one Pmod modules must be specified with `--pmod` parameter.")
    }
    let pmod_ports = read_pmod_ports(&Path::new(args.pmod_port_def.as_str())).unwrap();
    let pmod_modules: Vec<PmodModule> = args.pmods.iter().map(|pmod| {
        read_pmod_module(&Path::new(pmod.as_str())).unwrap()
    }).collect();
    let pins = assign_pmod_modules_to_ports(&pmod_ports, &pmod_modules, args.port_offset, args.direction).unwrap();
    match args.output {
        Some(output) => write_pins_as_gowin_loc(&mut std::fs::File::create(&Path::new(output.as_str())).unwrap(), &pins).unwrap(),
        None => write_pins_as_gowin_loc(&mut std::io::stdout(), &pins).unwrap(),
    }
}