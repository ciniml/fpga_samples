use std::{io, time};
use std::net::{Ipv4Addr, UdpSocket};
use std::time::Duration;


fn to_hub75_data(image: &bmp::Image) -> [u8; 1026*2] {
    let mut data = [0u8; 1026*2];
    for y in 0..32 {
        for x in 0..64 {
            let index = y * 64 + x + if y < 16 { 2 } else { 4 };
            //data[index] = (y & 7) as u8; //((y + x) & 7) as u8;
            let pixel = image.get_pixel(x as u32, y as u32);
            let mut byte_pixel = 0u8;
            if pixel.r >= 128 { byte_pixel |= 4; }
            if pixel.g >= 128 { byte_pixel |= 2; }
            if pixel.b >= 128 { byte_pixel |= 1; }
            data[index] = byte_pixel;
        }
    }
    data[0] = 0;
    data[1] = 0;
    data[1026] = (1024 >> 8) as u8;
    data[1027] = (1024 & 0xff) as u8;
    data
}

#[derive(Copy, Clone, Debug, Default)]
struct PushButton {
    current: bool,
    previous: bool,
}

impl PushButton {
    fn new() -> Self {
        Self::default()
    }
    fn is_pressed(&self) -> bool { self.current }
    fn is_pushed(&self) -> bool { self.current && !self.previous }
    fn is_released(&self) -> bool { !self.current && self.previous }
    fn update(&mut self, current: bool) {
        self.previous = self.current;
        self.current = current;
    }
}

fn main() -> io::Result<()> {
    let socket = UdpSocket::bind("0.0.0.0:10001")?;
    socket.set_read_timeout(Some(Duration::from_secs(2)))?;
    
    let mut buttons = [PushButton::default(); 6];

    let images = [
        to_hub75_data(&bmp::open("assets/hoge.bmp").unwrap()),
        to_hub75_data(&bmp::open("assets/fuga.bmp").unwrap()),
        to_hub75_data(&bmp::open("assets/fpga.bmp").unwrap()),
    ];

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
    let mut image_index = 0;
    let mut manual_update = false;
    let mut last_auto_updated = time::Instant::now();

    loop {
        if let Err(error) = socket.send_to(&patterns[pattern_index], "192.168.10.2:10001") {
            println!("pattern send error: {}", error);
        } else {
            match socket.recv_from(&mut buffer) {
                Err(_) => {},
                Ok((length, src_addr)) => {
                    println!("receive {} bytes from {}", length, src_addr);
                    if length > 0 {
                        let gpio_in = buffer[0];
                        println!("gpio in = {:02X}", gpio_in);
                        for i in 0..buttons.len() {
                            buttons[i].update((gpio_in & (1 << i)) != 0);
                        }
                    }
                }
            }
            pattern_index ^= 1;
        }

        if buttons[1].is_pushed() {
            manual_update = !manual_update
        }

        let elapsed = time::Instant::now() - last_auto_updated;
        if manual_update && buttons[0].is_pushed() || !manual_update && elapsed.as_secs() >= 5 {
            image_index = (image_index + 1) % images.len();
        
            let data = &images[image_index];
            if let Err(error) = socket.send_to(&data[0..1026], "192.168.10.2:10002") {
                println!("data send error: {}", error);
            }
            if let Err(error) = socket.send_to(&data[1026..], "192.168.10.2:10002") {
                println!("data send error: {}", error);
            }

            last_auto_updated = time::Instant::now();
        }
        std::thread::sleep(Duration::from_millis(100));
    }
}
