
interface axis_if #(
    parameter DATA_WIDTH = 1,   // TDATA width in bytes
    parameter USER_WIDTH = 1    // TUSER width in bits
) (
    input logic clock,
    input logic aresetn
);
    typedef logic [DATA_WIDTH*8-1:0] tdata_port_t;
    typedef logic [DATA_WIDTH-1:0]   tkeep_port_t;
    typedef logic [USER_WIDTH-1:0]   tuser_port_t;

    typedef bit [DATA_WIDTH*8-1:0] tdata_t;
    typedef bit [DATA_WIDTH-1:0]   tkeep_t;
    typedef bit [USER_WIDTH-1:0]   tuser_t;

    tdata_port_t tdata;
    logic tvalid;
    logic tready;
    logic tlast;
    tkeep_port_t tkeep;
    tuser_port_t tuser;
    
    task automatic master_init;
        tvalid <= 0;
        tlast <= 0;
        tkeep <= {DATA_WIDTH {1'b1}};
        tuser <= 0;
    endtask

    task automatic master_send(input tdata_t data, tkeep_t keep, bit last, tuser_t user );
        tdata <= data;
        tkeep <= keep;
        tlast <= last;
        tuser <= user;
        tvalid <= 1;
        do @(posedge clock); while(tready == 0);
        tvalid <= 0;
    endtask
    task automatic master_send_data(input tdata_t data);
        master_send(data, {DATA_WIDTH {1'b1}}, 0, 0);
    endtask

    task automatic slave_init;
        tready <= 0;
    endtask
    task automatic slave_receive(output tdata_t data, tkeep_t keep, bit last, tuser_t user, input int tready_deassert_factor );
        bit tready_value;
        forever begin
            tready_value = $urandom() >= tready_deassert_factor;
            tready <= tready_value;
            @(posedge clock);
            if( tready_value ) break;
        end
        while(tvalid == 0) @(posedge clock);
        data = tdata;
        keep = tkeep;
        last = tlast;
        user = tuser;
        tready <= 0;
    endtask
    task automatic slave_receive_data(output tdata_t data, input int tready_deassert_factor );
        tkeep_t keep;
        tuser_t user;
        bit     last;
        slave_receive(data, keep, last, user, tready_deassert_factor);
    endtask

    modport master(
        input  tready,
        output tdata, tvalid, tlast, tkeep, tuser,
        import master_init, master_send, master_send_data
    );
    
    modport slave(
        input  tdata, tvalid, tlast, tkeep, tuser,
        output tready,
        import slave_init, slave_receive, slave_receive_data
    );
endinterface