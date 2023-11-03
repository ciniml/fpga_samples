
```shell
cat video_fifo | cargo run&
cat audio_fifo | ../udpaudiosend/target/debug/udpaudiosend &
ffmpeg -y -stream_loop -1 -i ${VIDEO_FILE} -f rawvideo -pix_fmt rgb24 -vf "eq=gamma=0.5,scale=64:64" -r 30 -an video_fifo -f s16le -ar 48000 -acodec pcm_s16le audio_fifo
```