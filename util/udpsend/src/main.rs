use std::io;
use std::net::{Ipv4Addr, UdpSocket};
use std::time::Duration;

fn main() -> io::Result<()> {
    let socket = UdpSocket::bind("0.0.0.0:10001")?;
    socket.set_read_timeout(Some(Duration::from_secs(2)))?;

    let mut data = [0u8; 1024];
    for i in 0..data.len() {
        data[i] = (i & 0xff) as u8;
    }
    let patterns = [
        [
            0b0101_0101u8,
            0b0111_0000u8,
            0b1000_0000u8,
            0b1000_0000u8,
            0b1000_0110u8,
            0b0111_1001u8,
            0b0000_1001u8,
            0b0000_0110u8,
            0b0000_0011u8,
        ],
        [
            0b1010_1010u8,
            0b0000_0110u8,
            0b0000_1001u8,
            0b0000_1001u8,
            0b0111_0110u8,
            0b1000_0011u8,
            0b1000_0000u8,
            0b1000_0000u8,
            0b0111_0000u8,
        ],
    ];

    let mut pattern_index = 0;
    let mut buffer = [0u8; 1024];
    loop {
        if let Err(error) = socket.send_to(&patterns[pattern_index], "192.168.10.2:10001") {
            println!("send error: {}", error);
        } else {
            match socket.recv_from(&mut buffer) {
                Err(_) => {},
                Ok((length, src_addr)) => {
                    println!("receive {} bytes from {}", length, src_addr);
                    if length > 0 {
                        println!("gpio in = {:02X}", buffer[0]);
                    }
                }
            }
            pattern_index ^= 1;
        }
        std::thread::sleep(Duration::from_millis(1000));
    }
}
