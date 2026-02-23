#!/bin/sh

cargo run -- --port /dev/ttyACM0 \
    --signal advanceRenderingBufferIndex:1 \
    --signal backPressureValid:1 \
    --signal sendContextValid:1 \
    --signal sendContextReady:1 \
    --signal sendDataValid:1 \
    --signal sendDataReady:1 \
    --signal renderingBufferIndex:2 \
    --signal receivingBuferIndex:2 \
    --csv output.csv \
    --count 1 \
    && code output.0.csv