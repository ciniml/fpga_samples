// Copied from ~/repos/riscv-veryl/src/line_bus_if.veryl (commit 78e2537, 2026-09-10) for the NVMe DDR3 namespace.
// Keep in sync with the RISC-V project; local changes should be upstreamed there.
// Cache-line bus: the 128-bit (16-byte line) sibling of `BusIf`, used
// between the caches and the memory side (external DRAM controller, or
// `LineToBusBridge` for the 32-bit BSRAM `Memory`).
//
// The protocol is exactly that of `BusIf` (src/bus_if.veryl) with a wider
// payload:
//   • request handshake `valid`/`ready`, payload held stable until the
//     handshake; `addr` is a byte address aligned to 16 bytes (the low
//     4 bits are ignored by slaves);
//   • writes are posted — they complete at the handshake; `wstrb` selects
//     the bytes of the line to write (a cache write-through of one 32-bit
//     word sets 4 of the 16 strobes), `wdata` byte lane k is line byte k;
//   • reads return the whole line on `rdata` with `rvalid`, at least one
//     cycle after the handshake; one read outstanding per master;
//   • a slave must process requests in the order it accepted them, so a
//     read that follows a posted write sees the written data.
//
// A DDR3 controller with BL8 × 16-bit data pins delivers exactly one
// line per burst, which is why the line is 16 bytes.
interface LineBusIf;
    logic           valid ;
    logic           ready ;
    logic [32-1:0]  addr  ;
    logic           we    ;
    logic [16-1:0]  wstrb ;
    logic [128-1:0] wdata ;
    logic           rvalid;
    logic [128-1:0] rdata ;

    modport master (
        output valid ,
        output addr  ,
        output we    ,
        output wstrb ,
        output wdata ,
        input  ready ,
        input  rvalid,
        input  rdata 
    );

    modport slave (
        input  valid ,
        output ready ,
        input  addr  ,
        input  we    ,
        input  wstrb ,
        input  wdata ,
        output rvalid,
        output rdata 
    );
endinterface
//# sourceMappingURL=line_bus_if.sv.map
