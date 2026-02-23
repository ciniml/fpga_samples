<div class="mermaid">
stateDiagram-v2
    [*] --> IDLE: reset
    IDLE --> READ: pixel buffer is empty
    READ --> READ: byte counter < 3
    READ --> IDLE: byte counter == 3
</div>