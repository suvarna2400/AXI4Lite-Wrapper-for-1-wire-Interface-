//////////////////////////////////////////////////////////////////////////////
//  AXI4-Lite slave to sockit_owm native bus bridge                         //
//                                                                          //
//  Register map (BDW=32, byte addresses):                                  //
//    0x0  control/status + power/select                                    //
//    0x4  clock dividers {CDR_O[15:0], CDR_N[15:0]}                        //
//                                                                          //
//  The core has no wait states: bus_wen / bus_ren are single clock pulses, //
//  bus_wdt must be valid in the same cycle as bus_wen, and bus_rdt is a    //
//  combinational function of bus_adr.                                      //
//////////////////////////////////////////////////////////////////////////////
module axilite2bus #(
    parameter AW  = 4,    // AXI byte address width (>= 2+BAW)
    parameter BAW = 1,    // sockit_owm bus address width (BDW=32 -> 1)
    parameter DW  = 32    // data width, must be 32 (AXI4-Lite) and = sockit_owm BDW
)(
    input  wire              s_axi_aclk,
    input  wire              s_axi_aresetn,

    // write address channel
    input  wire [AW-1:0]     s_axi_awaddr,
    input  wire              s_axi_awvalid,
    output reg               s_axi_awready,

    // write data channel
    input  wire [DW-1:0]     s_axi_wdata,
    input  wire [(DW/8)-1:0] s_axi_wstrb,
    input  wire              s_axi_wvalid,
    output reg               s_axi_wready,

    // write response channel
    output reg  [1:0]        s_axi_bresp,
    output reg               s_axi_bvalid,
    input  wire              s_axi_bready,

    // read address channel
    input  wire [AW-1:0]     s_axi_araddr,
    input  wire              s_axi_arvalid,
    output reg               s_axi_arready,

    // read data channel
    output reg  [DW-1:0]     s_axi_rdata,
    output reg  [1:0]        s_axi_rresp,
    output reg               s_axi_rvalid,
    input  wire              s_axi_rready,

    // sockit_owm native bus
    output wire              bus_wen,   // one-cycle pulse
    output wire              bus_ren,   // one-cycle pulse
    output wire [BAW-1:0]    bus_adr,
    output wire [DW-1:0]     bus_wdt,
    input  wire [DW-1:0]     bus_rdt
);

    // ---------------- write ----------------
    // Same policy as wishbone2bus: only full-width writes are accepted,
    // a partial write is answered with SLVERR and does not reach the core.
    wire full_strb    = &s_axi_wstrb;
    wire write_accept = s_axi_awvalid & s_axi_wvalid & ~s_axi_bvalid;

    assign bus_wen = write_accept & full_strb;
    assign bus_wdt = s_axi_wdata;          // combinational: valid together with bus_wen

    always @ (posedge s_axi_aclk or negedge s_axi_aresetn)
    if (~s_axi_aresetn) begin
        s_axi_awready <= 1'b0;
        s_axi_wready  <= 1'b0;
    end else begin
        s_axi_awready <= write_accept;
        s_axi_wready  <= write_accept;
    end

    always @ (posedge s_axi_aclk or negedge s_axi_aresetn)
    if (~s_axi_aresetn) begin
        s_axi_bvalid <= 1'b0;
        s_axi_bresp  <= 2'b00;
    end else if (write_accept) begin
        s_axi_bvalid <= 1'b1;
        s_axi_bresp  <= full_strb ? 2'b00 : 2'b10;   // OKAY / SLVERR
    end else if (s_axi_bvalid & s_axi_bready) begin
        s_axi_bvalid <= 1'b0;
    end

    // ---------------- read ----------------
    // a read waits one cycle if a write is accepted in the same cycle
    wire read_accept = s_axi_arvalid & ~s_axi_rvalid & ~write_accept;
    assign bus_ren = read_accept;

    always @ (posedge s_axi_aclk or negedge s_axi_aresetn)
    if (~s_axi_aresetn) s_axi_arready <= 1'b0;
    else                s_axi_arready <= read_accept;

    // ---------------- address ----------------
    // AXI addresses are byte addresses, the core registers are 32-bit words
    assign bus_adr = write_accept ? s_axi_awaddr[2 +: BAW] :
                     read_accept  ? s_axi_araddr[2 +: BAW] : {BAW{1'b0}};

    always @ (posedge s_axi_aclk or negedge s_axi_aresetn)
    if (~s_axi_aresetn) begin
        s_axi_rvalid <= 1'b0;
        s_axi_rresp  <= 2'b00;
        s_axi_rdata  <= {DW{1'b0}};
    end else if (read_accept) begin
        s_axi_rvalid <= 1'b1;
        s_axi_rresp  <= 2'b00;
        s_axi_rdata  <= bus_rdt;           // bus_rdt follows bus_adr combinationally
    end else if (s_axi_rvalid & s_axi_rready) begin
        s_axi_rvalid <= 1'b0;
    end

endmodule
