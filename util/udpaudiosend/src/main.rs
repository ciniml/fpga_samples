use std::{io::Read, net::UdpSocket, time::Duration};

use clap::Parser;

#[derive(Parser, Debug)]
struct Cli {
    #[arg(long, default_value = "192.168.10.1:10002")]
    bind_to: String,
    #[arg(long, default_value = "192.168.10.2:10002")]
    destination: String,
}

fn main() -> anyhow::Result<()> {
    env_logger::init();
    let args: Cli = Cli::parse();
    let socket = UdpSocket::bind(&args.bind_to)?;
    socket.set_read_timeout(Some(Duration::from_millis(10)))?;
    let (sender, receiver) = std::sync::mpsc::channel();

    std::thread::spawn(move || loop {
        let mut buf = vec![0; 1024];
        let bytes_read = std::io::stdin().read(&mut buf).unwrap();
        buf.truncate(bytes_read);
        sender.send(buf).unwrap();
    });

    loop {
        let packet = receiver.recv().unwrap();
        if let Err(error) = socket.send_to(&packet, &args.destination) {
            log::error!("pattern send error: {}", error);
        }
        let mut buf = [0u8; 5];
        if let Ok((size, from)) = socket.recv_from(&mut buf) {
            if size == 5 {
                let remaining = u16::from_be_bytes([buf[1], buf[2]]);
                let maximum = u16::from_be_bytes([buf[3], buf[4]]);
                log::debug!("{}/{} from {}", remaining, maximum, from);
            }
        }
    }
}
