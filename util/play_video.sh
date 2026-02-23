#!/bin/bash
pkill udpaudiosend
pkill udpvideosend
pkill ffmpeg
if [ ! -f /tmp/video_fifo ]; then mkfifo /tmp/video_fifo; fi
if [ ! -f /tmp/audio_fifo ]; then mkfifo /tmp/audio_fifo; fi
#(cd udpvideosend; cat /tmp/video_fifo | cargo run --release) &
(cd udpvideosend; cat /tmp/video_fifo | cargo run --release -- --width 128 --height 128) &
(cd udpaudiosend; cat /tmp/audio_fifo | cargo run --release) &
#ffmpeg -y -stream_loop -1 -i ${VIDEO_FILE} -f rawvideo -pix_fmt rgb24 -vf "eq=gamma=0.5,scale=64:64" -r 30 /tmp/video_fifo -f s16le -acodec pcm_s16le /tmp/audio_fifo
ffmpeg -y -stream_loop -1 -i ${VIDEO_FILE} -f rawvideo -pix_fmt rgb24 -vf "eq=gamma=0.5,scale=128:128" -r 20 /tmp/video_fifo -f s16le -acodec pcm_s16le /tmp/audio_fifo
