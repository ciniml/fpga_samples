use std::{io::Read, net::UdpSocket, time::Duration};

use clap::Parser;

#[derive(Parser, Debug)]
struct Cli {
    #[arg(long, default_value = "192.168.10.1:10002")]
    bind_to: String,
    #[arg(long, default_value = "192.168.10.2:10002")]
    destination: String,
    #[arg(long)]
    frequency: Option<f32>,
    #[arg(long, default_value = "48000")]
    sampling_rate: u32,
}

fn main() -> anyhow::Result<()> {
    env_logger::init();
    let args: Cli = Cli::parse();
    let socket = UdpSocket::bind(&args.bind_to)?;
    socket.set_read_timeout(Some(Duration::from_millis(10)))?;
    let (sender, receiver) = std::sync::mpsc::channel();
    let (buffer_return, buffer_acquire) = std::sync::mpsc::channel();
    for _ in 0..128 {
        buffer_return.send(vec![0; 1024]).unwrap();
    }

    if let Some(frequency) = args.frequency {
        let counter_max = (args.sampling_rate as f32 / frequency) as u32;
        std::thread::spawn(move || {
            let mut counter = 0;
            loop {
                let mut buf = buffer_acquire.recv().unwrap();
                for i in 0..256 {
                    counter = if counter < counter_max { counter + 1 } else { 0 };
                    let value = ((65535.0 * (counter as f32 / counter_max as f32) - 32768.0) as i16) as u16;
                    buf[i * 4 + 0] = (value & 0xff) as u8;
                    buf[i * 4 + 1] = (value >> 8) as u8;
                    buf[i * 4 + 2] = (value & 0xff) as u8;
                    buf[i * 4 + 3] = (value >> 8) as u8;
                    
                }
                sender.send(buf).unwrap();
            }
        });
    } else {
        std::thread::spawn(move || loop {
            let mut buf = buffer_acquire.recv().unwrap();
            let mut bytes_read = 0;
            while bytes_read < buf.len() {
                bytes_read += std::io::stdin().read(&mut buf[bytes_read..]).unwrap();
            }
            buf.truncate(bytes_read);
            sender.send(buf).unwrap();
        });
    }

    struct BufferUsage {
        pub remaining: u16,
        pub maximum: u16,
    }

    let mut buffer_usage: Option<BufferUsage> = None;
    const BUFFER_SIZE: u16 = 1024/4;
    loop {
        loop {
            let (new_buffer_usage, need_send, exit) = match buffer_usage {
                None => (None, true, true),
                Some(usage) if usage.maximum - usage.remaining < BUFFER_SIZE => (Some(usage), false, true),
                Some(usage) => {
                    (Some(BufferUsage {
                        remaining: usage.remaining + BUFFER_SIZE,
                        maximum: usage.maximum,
                    }), true, usage.maximum - usage.remaining - BUFFER_SIZE >= BUFFER_SIZE)
                },
            };
            buffer_usage = new_buffer_usage;
            if need_send {
                let packet = receiver.recv().unwrap();
                if let Err(error) = socket.send_to(&packet, &args.destination) {
                    log::error!("pattern send error: {}", error);
                }
                buffer_return.send(packet).unwrap();
                if let Some(usage) = &buffer_usage {
                    log::debug!("{}/{}", usage.remaining, usage.maximum);
                }
            }
            if exit {
                break;
            }
        }
        let mut buf = [0u8; 5];
        if let Ok((size, from)) = socket.recv_from(&mut buf) {
            if size == 5 {
                let remaining = u16::from_be_bytes([buf[1], buf[2]]);
                let maximum = u16::from_be_bytes([buf[3], buf[4]]);
                log::debug!("{}/{} from {}", remaining, maximum, from);
                buffer_usage = Some(BufferUsage { remaining, maximum })
            }
        }
        else {
            buffer_usage = None;
        }
    }
}
