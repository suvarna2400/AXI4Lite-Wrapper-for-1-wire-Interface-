//////////////////////////////////////////////////////////////////////////////
//                                                                          //
//  1-wire (owr) slave model                                                //
//                                                                          //
//  Copyright (C) 2010  Iztok Jeras                                         //
//                                                                          //
//////////////////////////////////////////////////////////////////////////////
//                                                                          //
//  This HDL is free hardware: you can redistribute it and/or modify        //
//  it under the terms of the GNU Lesser General Public License             //
//  as published by the Free Software Foundation, either                    //
//  version 3 of the License, or (at your option) any later version.        //
//                                                                          //
//  This RTL is distributed in the hope that it will be useful,             //
//  but WITHOUT ANY WARRANTY; without even the implied warranty of          //
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the           //
//  GNU General Public License for more details.                            //
//                                                                          //
//  You should have received a copy of the GNU General Public License       //
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.   //
//                                                                          //
//////////////////////////////////////////////////////////////////////////////
 
`timescale 1us / 1ns

module onewire_slave_model #(
  // time slot (min=15.0, typ=30.0, max=60.0)
  parameter TS = 30.0
)(
  // configuration
  input  wire ena,    // response enable
  input  wire ovd,    // overdrive mode select
  input  wire dat_r,  // read data
  output wire dat_w,  // write data
  // 1-wire
  inout wire owr
);

// IO
reg pul;
reg dat;

// events
event sample_dat;
event sample_rst;

// reset timeout bookkeeping (replaces fork/join + disable of the original,
// which Vivado XSim does not execute like Icarus/ModelSim do)
integer epoch;      // id of the latest timeout request
integer tmo;        // receives the id of a timeout request when it expires
integer my_id;      // id of the timeout request of the current transfer
reg     got_rise;   // line was released (data cycle)
reg     got_tmo;    // line stayed low for 7 time slots (reset cycle)

//////////////////////////////////////////////////////////////////////////////
// IO
//////////////////////////////////////////////////////////////////////////////

// onewire open collector signal
assign owr = pul & ena ? 1'b0 : 1'bz;

// read data output
assign dat_w = ena ? dat : 1'bz;

//////////////////////////////////////////////////////////////////////////////
// events inside a cycle
//////////////////////////////////////////////////////////////////////////////

// power up state
initial begin
  pul   <= 1'b0;
  epoch =  0;
  tmo   =  0;
end

always @ (negedge owr)  if (ena) begin
  // provide read data response
  pul = ~dat_r;
  // wait 1 time slot
  if (ovd)  #(1*TS/8);
  else      #(1*TS);
  // write data is sampled here
  -> sample_dat;
  dat = owr;
  // release the wire
  pul = 1'b0;

  // request a timeout 7 time slots from now (reset detection)
  epoch = epoch + 1;
  my_id = epoch;
  if (ovd)  tmo <= #(7*TS/8) my_id;
  else      tmo <= #(7*TS)   my_id;

  // wait for the line to be released (data cycle) or for the timeout (reset)
  got_rise = 1'b0;
  got_tmo  = 1'b0;
  if (~owr) begin
    while (~got_rise & ~got_tmo) begin
      @ (posedge owr or tmo);
      if      (owr === 1'b1)  got_rise = 1'b1;
      else if (tmo == my_id)  got_tmo  = 1'b1;
    end
  end else begin
    got_rise = 1'b1;
  end

  // line still low after 7 time slots: this is a reset cycle
  if (got_tmo) begin
    -> sample_rst;
    // wait for reset low to end
    @ (posedge owr);
    // wait 1 time slot
    if (ovd)  #(1*TS/8);
    else      #(1*TS);
    // provide presence pulse
    pul = 1'b1;
    // wait 4 time slot
    if (ovd)  #(4*TS/8);
    else      #(4*TS);
    // release the wire
    pul = 1'b0;
  end
end

endmodule
