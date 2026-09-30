`timescale 1ns / 1ps
// AXI4-Lite testbench for sockit_owm_axi (3 wires, typ/min/max slaves)
module axilite_owm_tb;

localparam real FRQ = 6_000_000;
localparam real TCP = (10.0**9)/FRQ;
localparam OWN = 3;
localparam integer CDR_N = 5*FRQ/1_000_000 - 1;   // 29
localparam integer CDR_O = 1*FRQ/1_000_000 - 1;   // 5
localparam [31:0]  DIVS  = (CDR_O << 16) | CDR_N;  // expected divider register value

reg         clk = 1'b1, aresetn = 1'b0;
reg  [3:0]  awaddr = 0;  reg awvalid = 0;  wire awready;
reg  [31:0] wdata = 0;   reg [3:0] wstrb = 4'hf; reg wvalid = 0; wire wready;
wire [1:0]  bresp;       wire bvalid;      reg bready = 0;
reg  [3:0]  araddr = 0;  reg arvalid = 0;  wire arready;
wire [31:0] rdata;       wire [1:0] rresp; wire rvalid; reg rready = 0;
wire        irq;
wire [OWN-1:0] owr;

reg         slave_ena = 0, slave_ovd = 0, slave_dat_r = 1;
wire [OWN-1:0] slave_dat_w;

integer error = 0, n, i, sel;
reg [31:0] rd;
reg [1:0]  resp;

always #(TCP/2) clk = ~clk;
initial begin repeat (3) @(posedge clk); #1 aresetn = 1'b1; end

sockit_owm_axi #(.AW(4), .OWN(OWN), .CDR_N(CDR_N), .CDR_O(CDR_O)) dut (
  .s_axi_aclk(clk), .s_axi_aresetn(aresetn),
  .s_axi_awaddr(awaddr), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
  .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wvalid(wvalid), .s_axi_wready(wready),
  .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
  .s_axi_araddr(araddr), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
  .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid), .s_axi_rready(rready),
  .irq(irq), .owr(owr));

pullup pu [OWN-1:0] (owr);

// slaves: normal-mode typ/min/max on wires 0..2 (ena gated by ovd, as in onewire_tb)
onewire_slave_model #(.TS(30))      s_n0 (.ena(slave_ena & ~slave_ovd), .ovd(slave_ovd), .dat_r(slave_dat_r), .dat_w(slave_dat_w[0]), .owr(owr[0]));
onewire_slave_model #(.TS(15+0.1))  s_n1 (.ena(slave_ena & ~slave_ovd), .ovd(slave_ovd), .dat_r(slave_dat_r), .dat_w(slave_dat_w[1]), .owr(owr[1]));
onewire_slave_model #(.TS(60-0.1))  s_n2 (.ena(slave_ena & ~slave_ovd), .ovd(slave_ovd), .dat_r(slave_dat_r), .dat_w(slave_dat_w[2]), .owr(owr[2]));
onewire_slave_model #(.TS(30))      s_o0 (.ena(slave_ena &  slave_ovd), .ovd(slave_ovd), .dat_r(slave_dat_r), .dat_w(slave_dat_w[0]), .owr(owr[0]));
onewire_slave_model #(.TS(16))      s_o1 (.ena(slave_ena &  slave_ovd), .ovd(slave_ovd), .dat_r(slave_dat_r), .dat_w(slave_dat_w[1]), .owr(owr[1]));
onewire_slave_model #(.TS(47))      s_o2 (.ena(slave_ena &  slave_ovd), .ovd(slave_ovd), .dat_r(slave_dat_r), .dat_w(slave_dat_w[2]), .owr(owr[2]));

// ---------------- AXI4-Lite master tasks ----------------
// write: AW and W presented together; every handshake is sampled at the clock
// edge (values just before the edge), valids are dropped 1ns after the edge
task axi_write (input [3:0] a, input [31:0] d, input [3:0] s, output [1:0] r);
  reg aw_hs, w_hs, b_done;
begin
  @(negedge clk);
  awaddr = a; awvalid = 1; wdata = d; wstrb = s; wvalid = 1; bready = 1;
  b_done = 0;
  while (!b_done) begin
    @(posedge clk);
    aw_hs = awvalid && awready;
    w_hs  = wvalid  && wready;
    if (bvalid && bready) begin r = bresp; b_done = 1; end
    #1;
    if (aw_hs) awvalid = 0;
    if (w_hs)  wvalid  = 0;
  end
  @(negedge clk); bready = 0;
end endtask

task axi_read (input [3:0] a, output [31:0] d, output [1:0] r);
  reg ar_hs, r_done;
begin
  @(negedge clk);
  araddr = a; arvalid = 1; rready = 1;
  r_done = 0;
  while (!r_done) begin
    @(posedge clk);
    ar_hs = arvalid && arready;
    if (rvalid && rready) begin d = rdata; r = rresp; r_done = 1; end
    #1;
    if (ar_hs) arvalid = 0;
  end
  @(negedge clk); rready = 0;
end endtask

// ---------------- helpers matching onewire_tb ----------------
task owr_request (input [15:0] pwr, input [3:0] sel, input [2:0] cmd);
  reg [1:0] r;
begin
  axi_write (4'h0, {pwr<<sel, 4'h0, sel, 3'b000, pwr[0], 1'b1, cmd}, 4'hf, r);
  if (r !== 2'b00) begin error = error+1; $display("ERROR: (t=%0t) bad bresp %b", $time, r); end
end endtask

task owr_polling (input integer dly, output integer cnt);
  reg [1:0] r;
begin
  cnt = 0; rd = 32'h08;
  while (rd & 32'h08) begin
    repeat (dly) @(posedge clk);
    axi_read (4'h0, rd, r); cnt = cnt + 1;
  end
end endtask

initial begin
  wait (aresetn); repeat (5) @(posedge clk); $display("NOTE: reset released");

  // register readback through the AXI address map (0x4 = dividers)
  axi_write (4'h4, DIVS, 4'hf, resp);
  axi_read  (4'h4, rd, resp);
  if (rd !== DIVS || resp !== 2'b00) begin
    error = error+1; $display("ERROR: divider readback %h resp %b", rd, resp); end
  axi_write (4'h4, {16'h0001, 16'h0003}, 4'hf, resp);          // odd value
  axi_read  (4'h4, rd, resp);
  if (rd !== 32'h0001_0003) begin error = error+1; $display("ERROR: divider readback2 %h", rd); end
  axi_write (4'h4, DIVS, 4'hf, resp);      // restore

  // partial-strobe write must be rejected with SLVERR and must not change the register
  axi_write (4'h4, 32'hdead_beef, 4'h3, resp);
  if (resp !== 2'b10) begin error = error+1; $display("ERROR: expected SLVERR, got %b", resp); end
  axi_read  (4'h4, rd, resp);
  if (rd !== DIVS) begin error = error+1; $display("ERROR: partial write leaked: %h", rd); end

  for (sel = 0; sel < OWN; sel = sel + 1)
  for (i = 0; i < 2; i = i + 1) begin
    slave_ovd = i[0];
    $display("NOTE: Loop: speed=%s, ovd=%b", (sel==0)?"typ":(sel==1)?"min":"max", slave_ovd);

    slave_ena = 0; slave_dat_r = 1;
    owr_request (16'd0, sel, {slave_ovd, 2'b10}); owr_polling (8, n);
    if (rd[0] !== 1'b1) begin error = error+1; $display("ERROR: (t=%0t) presence '1' expected", $time); end

    slave_ena = 1; slave_dat_r = 1;
    owr_request (16'd0, sel, {slave_ovd, 2'b10}); owr_polling (8, n);
    if (rd[0] !== 1'b0) begin error = error+1; $display("ERROR: (t=%0t) presence '0' expected", $time); end

    owr_request (16'd0, sel, {slave_ovd, 2'b00}); owr_polling (8, n);      // write 0
    if (slave_dat_w[sel] !== 1'b0) begin error = error+1; $display("ERROR: (t=%0t) write 0", $time); end
    if (rd[0] !== 1'b0)            begin error = error+1; $display("ERROR: (t=%0t) read after write 0", $time); end

    slave_dat_r = 1;
    owr_request (16'd0, sel, {slave_ovd, 2'b01}); owr_polling (8, n);      // write 1, read 1
    if (slave_dat_w[sel] !== 1'b1) begin error = error+1; $display("ERROR: (t=%0t) write 1", $time); end
    if (rd[0] !== 1'b1)            begin error = error+1; $display("ERROR: (t=%0t) read 1", $time); end

    slave_dat_r = 0;
    owr_request (16'd0, sel, {slave_ovd, 2'b01}); owr_polling (8, n);      // write 1, read 0
    if (slave_dat_w[sel] !== 1'b0) begin error = error+1; $display("ERROR: (t=%0t) write 1/read 0 line", $time); end
    if (rd[0] !== 1'b0)            begin error = error+1; $display("ERROR: (t=%0t) read 0", $time); end
  end

  repeat (10) @(posedge clk);
  if (error == 0) $display("PASS: no errors");
  else            $display("FAIL: %0d errors", error);
  $finish;
end

initial begin #20_000_000; $display("TIMEOUT at %0t", $time); $finish; end   // 50 ms guard
endmodule
