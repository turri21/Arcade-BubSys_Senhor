//================================================================================
//  K0005289 Pre-SCC Wavetable Sound Generator
//
//  Nemesis sound module
//  Copyright © 2020-2022 LMN-san (@LmnSama),
//                        Olivier Scherler (@oscherler),
//                        Raki (Sehyeon Kim, @RCAVictorCo)
//  
//  Commercial use is prohibited. 
//================================================================================

// CUSTOM CHIP pinout:
/*        _____________
        _|             |_
GND(0) |_|1          42|_| VCC
        _|             |_                     
A(0)   |_|2          41|_| /RESET
        _|             |_
A(1)   |_|3          40|_| 1QE(4)
        _|             |_
A(2)   |_|4          39|_| 1QD(3)
        _|             |_
A(3)   |_|5          38|_| 1QC(2)
        _|             |_
A(4)   |_|6          37|_| 1QB(1)
        _|             |_
A(5)   |_|7          36|_| 1QA(0)
        _|             |_
A(6)   |_|8          35|_| 2QE(4)
        _|             |_
A(7)   |_|9          34|_| 2QD(3)
        _|             |_                     
A(8)   |_|10   8A    33|_| 2QC(2)
        _|             |_
A(9)   |_|11         32|_| 2QB(1)
        _|             |_
A(10)  |_|12         31|_| 2QA(0)
        _|             |_
A(11)  |_|13         30|_| T1(connect to gnd)
        _|             |_
CLK()  |_|14         29|_| T0(connect to gnd)
        _|             |_
LD1()  |_|15         28|_| 
        _|             |_
TG1()  |_|16         27|_| 
        _|             |_
LD2()  |_|17         26|_| 
        _|             |_
TG2()  |_|18         25|_| 
        _|             |_
       |_|19         24|_| 
        _|             |_
       |_|20         23|_| 
        _|             |_
GND    |_|21         22|_| GND
         |_____________|
*/

module K005289
(
	input               i_RST_n,          // RESET signal
	input               i_CLK,            // Main clock
	input               i_CEN,            // Clock enable

	input               i_LD1,            // 
	input               i_TG1,            //

	input               i_LD2,            //
	input               i_TG2,            //

	input     [11:0]    i_COUNTER,        // 12 bits input counter to play frequency

	output     [4:0]    o_Q1,             // 5 bits output
	output     [4:0]    o_Q2              // 5 bits output
);

////////////////////////////////////////////////////////////////////////////////////////////////////

wire      [11:0]    addrLD1, addrTG1, addrLD2, addrTG2;

// the 17 bits counters will serve 2 purposes count on the lower part on 12 bits and output
// the accumulated upper 5 bits part
reg	      [16:0]    r_count1, r_count2;

////////////////////////////////////////////////////////////////////////////////////////////////////
// Channel 1 LATCH


bus_ff #( .W( 12 ) ) ch1_ld_latch(
	.rst     ( ~i_RST_n     ),
	.clk     ( i_CLK        ),
	.trig    ( ~i_LD1       ),
	.d       ( i_COUNTER    ),
	.q       ( addrLD1      ),
	.q_n     (              )
);

bus_ff #( .W( 12 ) ) ch1_tg_latch(
	.rst     ( ~i_RST_n     ),
	.clk     ( i_CLK        ),
	.trig    ( ~i_TG1       ),
	.d       ( addrLD1      ),
	.q       ( addrTG1      ),
	.q_n     (              )
);

// Channel 2 LATCH

bus_ff #( .W( 12 ) ) ch2_ld_latch(
	.rst     ( ~i_RST_n     ),
	.clk     ( i_CLK        ),
	.trig    ( ~i_LD2       ),
	.d       ( i_COUNTER    ),
	.q       ( addrLD2      ),
	.q_n     (              )
);

bus_ff #( .W( 12 ) ) ch2_tg_latch(
	.rst     ( ~i_RST_n     ),
	.clk     ( i_CLK        ),
	.trig    ( ~i_TG2       ),
	.d       ( addrLD2      ),
	.q       ( addrTG2      ),
	.q_n     (              )
);


////////////////////////////////////////////////////////////////////////////////////////////////////
// Channel 1 COUNTERS

// addrTG1  = IN  : 12 bits data input
// i_CLK    = IN  : clock input
// i_CEN    = IN  : clock enable
// i_RST_n  = IN  : reset at 0
always @( posedge i_CLK ) begin
	if (~i_RST_n) begin // if n_reset = 0
		r_count1 <=  17'd0;                       // 12 bits + 5 bits for the counter output
		r_count2 <=  17'd0;                       // 12 bits + 5 bits for the counter output
	end else if (i_CEN) begin                     // if i_CEN pulse = 1
		// COUNTER 1
		if(r_count1[11:0] == 12'hFFF) begin
			r_count1 <= r_count1 + 17'd1;         // we need to add 1 before the re-set of the lower value to be sure we increment the upper part for the output
			r_count1[11:0] <= addrTG1;            // re-set to the tone in addrTG1 memory register
		end else begin
			r_count1 <= r_count1 + 17'd1;
		end

		// COUNTER 2
		if(r_count2[11:0] == 12'hFFF) begin
			r_count2 <= r_count2 + 17'd1;         // we need to add 1 before the re-set of the lower value to be sure we increment the upper part for the output
			r_count2[11:0] <= addrTG2;            // re-set to the tone in addrTG2 memory register
		end else begin
			r_count2 <= r_count2 + 17'd1;
		end
	end
end

assign o_Q1 = r_count1[16:12];                   // we output only the upper part of the counter
assign o_Q2 = r_count2[16:12];                   // we output only the upper part of the counter

endmodule


module bus_ff #( parameter W=1 ) (
	input          clk,
	input          rst,
	input          trig,
	input  [W-1:0] d,

	output [W-1:0] q,
	output [W-1:0] q_n
);

reg         trig_prev;
reg [W-1:0] state;

always @( posedge clk ) begin
	if( rst ) begin
		state <= {W{1'b0}};
		trig_prev <= 1'b1;
	end else begin
		if( trig & ~trig_prev ) begin
			state <= d;
		end

		trig_prev <= trig;
	end
end

assign q   = state;
assign q_n = ~state;

endmodule
