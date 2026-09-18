// ////axilite2bus.v

module axilite2bus #(
    parameter AW = 1,   // matching sockit_owm's BAW
    parameter DW = 32   // matching sockit_owm's BDW
)(
    input  wire            s_axi_aclk,
    input  wire            s_axi_aresetn,

    // AXI4-Lite write address channel 
    input  wire [AW-1:0]   s_axi_awaddr,
    input  wire            s_axi_awvalid,
    output reg             s_axi_awready,

    // AXI4-Lite write data channel 
    input  wire [DW-1:0]   s_axi_wdata,
    input  wire [(DW/8)-1:0] s_axi_wstrb,   // accepted but unused
    input  wire            s_axi_wvalid,
    output reg             s_axi_wready,

    // AXI4-Lite write response channel 
    output reg  [1:0]      s_axi_bresp,
    output reg             s_axi_bvalid,
    input  wire            s_axi_bready,

    // AXI4-Lite read address channel 
    input  wire [AW-1:0]   s_axi_araddr,
    input  wire            s_axi_arvalid,
    output reg             s_axi_arready,

    // AXI4-Lite read data channel 
    output reg  [DW-1:0]   s_axi_rdata,
    output reg  [1:0]      s_axi_rresp,
    output reg             s_axi_rvalid,
    input  wire            s_axi_rready,

    // sockit_owm native bus interface 
    output wire            bus_wen,   
    output wire            bus_ren,   
    output wire [AW-1:0]   bus_adr,
    output reg  [DW-1:0]   bus_wdt,
    input  wire [DW-1:0]   bus_rdt
);

   
    // ////////////Write channel 
    wire write_accept = s_axi_awvalid & s_axi_wvalid & ~s_axi_bvalid;
    assign bus_wen = write_accept;

    always @ (posedge s_axi_aclk or negedge s_axi_aresetn)
    if (~s_axi_aresetn) begin
        s_axi_awready <= 1'b0;
        s_axi_wready  <= 1'b0;
        bus_wdt       <= {DW{1'b0}};
    end else begin
        s_axi_awready <= write_accept;
        s_axi_wready  <= write_accept;
        if (write_accept)
            bus_wdt <= s_axi_wdata;
    end

    always @ (posedge s_axi_aclk or negedge s_axi_aresetn)
    if (~s_axi_aresetn) begin
        s_axi_bvalid <= 1'b0;
        s_axi_bresp  <= 2'b00;
    end else if (write_accept) begin
        s_axi_bvalid <= 1'b1;
        s_axi_bresp  <= 2'b00;              // OKAY -- sockit_owm has no error response of its own
    end else if (s_axi_bvalid & s_axi_bready) begin
        s_axi_bvalid <= 1'b0;
    end

    
    // ///////////// Read channel
    wire read_accept = s_axi_arvalid & ~s_axi_rvalid;
    assign bus_ren = read_accept;

    always @ (posedge s_axi_aclk or negedge s_axi_aresetn)
    if (~s_axi_aresetn) begin
        s_axi_arready <= 1'b0;
        s_axi_rvalid  <= 1'b0;
        s_axi_rresp   <= 2'b00;
        s_axi_rdata   <= {DW{1'b0}};
    end else begin
        s_axi_arready <= read_accept;
        if (read_accept) begin
            s_axi_rvalid <= 1'b1;
            s_axi_rresp  <= 2'b00;       // OKAY
            s_axi_rdata  <= bus_rdt;    
        end else if (s_axi_rvalid & s_axi_rready) begin
            s_axi_rvalid <= 1'b0;
        end
    end

    // /////////bus_adr -- single combinational driver 
    assign bus_adr = write_accept ? s_axi_awaddr : read_accept  ? s_axi_araddr : {AW{1'b0}};

endmodule