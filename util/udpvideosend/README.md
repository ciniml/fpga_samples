
ffmpeg -y -i ~/wk/白聖女と黒牧師　#1「ふたりの関係」.mp4 -f rawvideo -pix_fmt rgb24 -vf "eq=gamma=0.5,scale=64:64" -r 30 -an video_fifo -f s16le -ar 48000 -acodec pcm_s16le audio_fifo
cat video_fifo | cargo run&