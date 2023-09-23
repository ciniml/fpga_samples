use std::net::UdpSocket;

use clap::Parser;

#[derive(Parser, Debug)]
struct Cli {
    #[arg(long = "l0", default_value = "32768")]
    volume_left_0: u16,
    #[arg(long = "r0", default_value = "32768")]
    volume_right_0: u16,
    #[arg(long = "l1", default_value = "32768")]
    volume_left_1: u16,
    #[arg(long = "r1", default_value = "32768")]
    volume_right_1: u16,
    
    #[arg(long, default_value = "192.168.10.1:10001")]
    bind_to: String,

    #[arg(long, default_value = "192.168.10.2:10001")]
    destination: String,
}

fn main() -> anyhow::Result<()> {
    let args: Cli = Cli::parse();
    let socket = UdpSocket::bind(&args.bind_to)?;
    
    let mut packet = [0u8; 9];
    packet[1..3].copy_from_slice(&args.volume_left_0.to_le_bytes());
    packet[3..5].copy_from_slice(&args.volume_right_0.to_le_bytes());
    packet[5..7].copy_from_slice(&args.volume_left_1.to_le_bytes());
    packet[7..9].copy_from_slice(&args.volume_right_1.to_le_bytes());
    if let Err(error) = socket.send_to(&packet, &args.destination) {
        println!("pattern send error: {}", error);
    } 
    Ok(())
}
