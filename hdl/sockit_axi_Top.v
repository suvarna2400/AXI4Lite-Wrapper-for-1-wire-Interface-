//////////////////////////////////////////////////////////////////////////////
//  Top: AXI4-Lite slave + sockit_owm 1-wire master                         //
//////////////////////////////////////////////////////////////////////////////
module sockit_owm_axi #(
    parameter AW    = 4,        // AXI byte address width
    parameter OWN   = 1,        // number of 1-wire ports
    parameter OVD_E = 1,
    parameter CDR_E = 1,
    parameter BTP_N = "5.0",
    parameter BTP_O = "1.0",
    parameter CDR_N = 5-1,      // reset value of the normal-mode divider
    parameter CDR_O = 1-1       // reset value of the overdrive divider
)(
    input  wire              s_axi_aclk,
    input  wire              s_axi_aresetn,

    input  wire [AW-1:0]     s_axi_awaddr,
    input  wire              s_axi_awvalid,
    output wire              s_axi_awready,

    input  wire [31:0]       s_axi_wdata,
    input  wire [3:0]        s_axi_wstrb,
    input  wire              s_axi_wvalid,
    output wire              s_axi_wready,

    output wire [1:0]        s_axi_bresp,
    output wire              s_axi_bvalid,
    input  wire              s_axi_bready,

    input  wire [AW-1:0]     s_axi_araddr,
    input  wire              s_axi_arvalid,
    output wire              s_axi_arready,

    output wire [31:0]       s_axi_rdata,
    output wire [1:0]        s_axi_rresp,
    output wire              s_axi_rvalid,
    input  wire              s_axi_rready,

    output wire              irq,
    inout  wire [OWN-1:0]    owr        // 1-wire line(s), needs an external pull-up
);

    localparam BDW = 32;
    localparam BAW = 1;

    wire           bus_wen, bus_ren;
    wire [BAW-1:0] bus_adr;
    wire [BDW-1:0] bus_wdt, bus_rdt;
    wire [OWN-1:0] owr_p, owr_e, owr_i;

    axilite2bus #(.AW(AW), .BAW(BAW), .DW(BDW)) axi_bridge (
        .s_axi_aclk    (s_axi_aclk),    .s_axi_aresetn (s_axi_aresetn),
        .s_axi_awaddr  (s_axi_awaddr),  .s_axi_awvalid (s_axi_awvalid), .s_axi_awready (s_axi_awready),
        .s_axi_wdata   (s_axi_wdata),   .s_axi_wstrb   (s_axi_wstrb),
        .s_axi_wvalid  (s_axi_wvalid),  .s_axi_wready  (s_axi_wready),
        .s_axi_bresp   (s_axi_bresp),   .s_axi_bvalid  (s_axi_bvalid),  .s_axi_bready  (s_axi_bready),
        .s_axi_araddr  (s_axi_araddr),  .s_axi_arvalid (s_axi_arvalid), .s_axi_arready (s_axi_arready),
        .s_axi_rdata   (s_axi_rdata),   .s_axi_rresp   (s_axi_rresp),
        .s_axi_rvalid  (s_axi_rvalid),  .s_axi_rready  (s_axi_rready),
        .bus_wen (bus_wen), .bus_ren (bus_ren), .bus_adr (bus_adr),
        .bus_wdt (bus_wdt), .bus_rdt (bus_rdt)
    );

    sockit_owm #(
        .OVD_E (OVD_E), .CDR_E (CDR_E), .BDW (BDW), .BAW (BAW), .OWN (OWN),
        .BTP_N (BTP_N), .BTP_O (BTP_O), .CDR_N (CDR_N), .CDR_O (CDR_O)
    ) onewire_master (
        .clk     (s_axi_aclk),
        .rst     (~s_axi_aresetn),      // core reset is active high
        .bus_ren (bus_ren), .bus_wen (bus_wen), .bus_adr (bus_adr),
        .bus_wdt (bus_wdt), .bus_rdt (bus_rdt), .bus_irq (irq),
        .owr_p   (owr_p),   .owr_e   (owr_e),   .owr_i   (owr_i)
    );

    // open-drain line driver with optional strong pull-up (same as the testbench)
    genvar i;
    generate for (i = 0; i < OWN; i = i + 1) begin : owr_io
        assign owr[i]   = (owr_e[i] | owr_p[i]) ? owr_p[i] : 1'bz;
        assign owr_i[i] = owr[i];
    end endgenerate

endmodule
