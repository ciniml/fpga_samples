`default_nettype none
module serv_system #(
    parameter INIT_INST_RAM = "",
    parameter int IMEM_SIZE_BYTES = 128,
    parameter int DMEM_SIZE_BYTES = 64
)(
    input  wire clock,
    input  wire reset,
    output wire [2:0] gpio
);
    logic        i_timer_irq;

    logic        o_rf_rreq;
    logic        o_rf_wreq;
    logic        i_rf_ready;
    logic [5:0]  o_wreg0;
    logic [5:0]  o_wreg1;
    logic        o_wen0;
    logic        o_wen1;
    logic        o_wdata0;
    logic        o_wdata1;
    logic [5:0]  o_rreg0;
    logic [5:0]  o_rreg1;
    logic        i_rdata0;
    logic        i_rdata1;

    wishbone_if #(.ADDRESS_BITS(32), .DATA_BYTES(4)) ibus_imem_if(.clk(clock), .rst(reset));
    //wishbone_if #(.ADDRESS_BITS(32), .DATA_BYTES(4)) dbus_imem_if(.clk(clock), .rst(reset));
    wishbone_if #(.ADDRESS_BITS(32), .DATA_BYTES(4)) dbus_dmem_if(.clk(clock), .rst(reset));
    wishbone_if #(.ADDRESS_BITS(32), .DATA_BYTES(4)) dbus_gpio_if(.clk(clock), .rst(reset));
    wishbone_if #(.ADDRESS_BITS(32), .DATA_BYTES(4)) dbus_if(.clk(clock), .rst(reset));

    wb_mux #(
        .NUMBER_OF_PORTS(2),
        .BASE_ADDRESS({64'h20000000_2000ffff, 64'h30000000_3000ffff})
    ) wb_dbus_mux (
        .bus_in(dbus_if),
        .bus_out({dbus_dmem_if, dbus_gpio_if})
    );

    serv_top #(
        .RESET_PC(32'h0800_0000)
    ) serv_top_inst (
        .clk(clock),
        .i_rst(reset),
        .i_timer_irq(i_timer_irq),

        // Instruction bus
        .o_ibus_adr(ibus_imem_if.adr),
        .o_ibus_cyc(ibus_imem_if.cyc),
        .i_ibus_rdt(ibus_imem_if.dat_i),
        .i_ibus_ack(ibus_imem_if.ack),
        
        // Data bus
        .o_dbus_adr(dbus_if.adr),
        .o_dbus_dat(dbus_if.dat_o),
        .o_dbus_sel(dbus_if.sel),
        .o_dbus_we (dbus_if.we),
        .o_dbus_cyc(dbus_if.cyc),
        .i_dbus_rdt(dbus_if.dat_i),
        .i_dbus_ack(dbus_if.ack),
        
        // Register IF
        .o_rf_rreq(o_rf_rreq),
        .o_rf_wreq(o_rf_wreq),
        .i_rf_ready(i_rf_ready),
        .o_wreg0(o_wreg0),
        .o_wreg1(o_wreg1),
        .o_wen0(o_wen0),
        .o_wen1(o_wen1),
        .o_wdata0(o_wdata0),
        .o_wdata1(o_wdata1),
        .o_rreg0(o_rreg0),
        .o_rreg1(o_rreg1),
        .i_rdata0(i_rdata0),
        .i_rdata1(i_rdata1)
    );

    assign i_timer_irq = 0;

    logic [31:0] gpio_out;
    assign gpio = ~gpio_out[2:0];

    // Register file IF
    logic [7:0] rf_waddr;
    logic       rf_wen;
    logic [7:0] rf_wdata;
    logic [7:0] rf_raddr;
    logic [7:0] rf_rdata;
    serv_rf_ram_if rf_ram_if (
        .i_clk(clock),
        .i_rst(reset),
        .i_wreq(o_rf_wreq),
        .i_rreq(o_rf_rreq),
        .o_ready(i_rf_ready),
        .i_wreg0(o_wreg0),
        .i_wreg1(o_wreg1),
        .i_wen0(o_wen0),
        .i_wen1(o_wen1),
        .i_wdata0(o_wdata0),
        .i_wdata1(o_wdata1),
        .i_rreg0(o_rreg0),
        .i_rreg1(o_rreg1),
        .o_rdata0(i_rdata0),
        .o_rdata1(i_rdata1),

        .o_waddr(rf_waddr),
        .o_wen  (rf_wen),
        .o_wdata(rf_wdata),
        .o_raddr(rf_raddr),
        .i_rdata(rf_rdata)
    );

    bit [7:0] rf_mem [0:255];
    always_ff @(posedge clock) begin
        if( rf_wen ) begin
            rf_mem[rf_waddr] <= rf_wdata;
        end
        rf_rdata <= rf_mem[rf_raddr];
    end

    ram32 #(
        .INITIAL_FILE(INIT_INST_RAM),
        .RAM_SIZE(IMEM_SIZE_BYTES)
    ) iram (
        .wb_slave(ibus_imem_if),
        .*
    );

    ram32_16 #(
        .RAM_SIZE(DMEM_SIZE_BYTES)
    ) dram (
        .wb_slave(dbus_dmem_if),
        .*
    );
    
    assign dbus_gpio_if.dat_i = gpio_out;
    always_ff @(posedge clock) begin
        dbus_gpio_if.ack <= 0;
        if( dbus_gpio_if.cyc ) begin
            if( dbus_gpio_if.we ) begin
                gpio_out <=  dbus_gpio_if.dat_o;
            end
            dbus_gpio_if.ack <= 1;
        end
    end
endmodule