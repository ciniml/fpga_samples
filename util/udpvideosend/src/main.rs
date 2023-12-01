use std::{io::Read, net::UdpSocket, time::Duration};

use clap::Parser;

#[derive(Parser, Debug)]
struct Cli {
    #[arg(long, default_value = "192.168.10.1:10004")]
    bind_to: String,
    #[arg(long, default_value = "192.168.10.2:10004")]
    destination: String,
    #[arg(long, default_value = "64")]
    width: u16,
    #[arg(long, default_value = "64")]
    height: u16,
    #[arg(long, default_value = "false")]
    test_pattern: bool,
    #[arg(long, default_value = "false")]
    clear: bool,
}

fn rgb888_to_565(r: u8, g: u8, b: u8) -> u16 {
    let pixel565 = ((r >> 3) as u16) << 11
                     | ((g >> 2) as u16) << 5
                     | ((b >> 3) as u16) << 0;
    pixel565
}

fn main() -> anyhow::Result<()> {
    env_logger::init();
    let args: Cli = Cli::parse();
    let socket = UdpSocket::bind(&args.bind_to)?;
    socket.set_read_timeout(Some(Duration::from_millis(100)))?;
    let (sender, receiver) = std::sync::mpsc::channel();

    let frame_pixels = args.width as usize * args.height as usize;
    const HEADER_SIZE: usize = 2;
    let frame_bytes = frame_pixels * 2;
    let packet_payload_size = 1024;
    let packet_size = HEADER_SIZE + packet_payload_size;
    let number_of_packets = (frame_bytes + packet_payload_size - 1) / packet_payload_size;

    let (buffer_return, buffer_acquire) = std::sync::mpsc::channel();
    for _ in 0..128 {
        let mut buffer = Vec::new();
        buffer.resize(packet_size * number_of_packets, 0u8);
        buffer_return.send(buffer).unwrap();
    }

    if args.test_pattern || args.clear {
        std::thread::spawn(move || {
            let mut counter = 0u8;
            loop {
                let mut buf = buffer_acquire.recv().unwrap();
                for i in 0..frame_pixels {
                    let value = if args.clear {
                        0
                    } else {
                        let line = ((i / (args.width as usize)) & 0xff) as u8;
                        let pixel_value = counter.wrapping_add(line).wrapping_mul(4);
                        let value = rgb888_to_565(pixel_value, pixel_value, pixel_value);
                        value
                    };
                    let packet_index = i * 2 / packet_payload_size;
                    let payload_offset = HEADER_SIZE * (packet_index + 1);
                    buf[payload_offset + i * 2] = (value & 0xff) as u8;
                    buf[payload_offset + i * 2 + 1] = (value >> 8) as u8;
                }
                // Set the header for each packet
                for packet_index in 0..number_of_packets {
                    let packet_offset = packet_index * packet_size;
                    let packet_start_address = (packet_index * packet_payload_size) as u16;
                    buf[packet_offset + 0] = (packet_start_address >> 8) as u8;
                    buf[packet_offset + 1] = (packet_start_address & 0xff) as u8;
                }
                sender.send(buf).unwrap();
                counter = counter.wrapping_add(1);
            }
        });
    } else {
        std::thread::spawn(move || {
            let mut counter = 0u8;
            let mut input_buffer = vec![0u8; frame_pixels * 3]; // RGB888 frame buffer.
            'outer: loop {
                {
                    let mut bytes_read = 0;
                    while bytes_read < input_buffer.len() {
                        if let Ok(bytes) = std::io::stdin().read(&mut input_buffer[bytes_read..]) {
                            bytes_read += bytes;
                            if bytes == 0 {
                                break 'outer;
                            }
                        } else {
                            break 'outer;
                        }
                    }
                }
                let mut buf = buffer_acquire.recv().unwrap();
                for i in 0..frame_pixels {
                    let packet_index = i * 2 / packet_payload_size;
                    let payload_offset = HEADER_SIZE * (packet_index + 1);
                    let value = rgb888_to_565(input_buffer[i*3 + 0], input_buffer[i*3 + 1], input_buffer[i*3 + 2]);
                    buf[payload_offset + i * 2] = (value & 0xff) as u8;
                    buf[payload_offset + i * 2 + 1] = (value >> 8) as u8;
                }
                // Set the header for each packet
                for packet_index in 0..number_of_packets {
                    let packet_offset = packet_index * packet_size;
                    let packet_start_address = (packet_index * packet_payload_size) as u16;
                    buf[packet_offset + 0] = (packet_start_address >> 8) as u8;
                    buf[packet_offset + 1] = (packet_start_address & 0xff) as u8;
                }
                sender.send(buf).unwrap();
                counter = counter.wrapping_add(1);
            }
        });
    }
    // std::thread::spawn(move || loop {
    //     let mut buf = buffer_acquire.recv().unwrap();
    //     let bytes_read = std::io::stdin().read(&mut buf).unwrap();
    //     buf.truncate(bytes_read);
    //     sender.send(buf).unwrap();
    // });

    let start_time = std::time::Instant::now();
    let mut packets_sent = 0usize;
    loop {
        let packet = receiver.recv().unwrap();
        
        for packet_index in 0..number_of_packets {
            let packet_offset = packet_index * packet_size;
            if let Err(error) = socket.send_to(&packet[packet_offset..packet_offset+packet_size], &args.destination) {
                log::error!("pattern send error: {}", error);
            }
        }

        let elapsed = start_time.elapsed();
        log::debug!("{} fps ({} frames)", (packets_sent as f32) / elapsed.as_secs_f32(), packets_sent);
        packets_sent += 1;
        buffer_return.send(packet).unwrap();
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
