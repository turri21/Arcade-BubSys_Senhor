//============================================================================
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//
//============================================================================

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [48:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	//if VIDEO_ARX[12] or VIDEO_ARY[12] is set then [11:0] contains scaled size instead of aspect ratio.
	output [12:0] VIDEO_ARX,
	output [12:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output [1:0]  VGA_SL,
	output        VGA_SCALER, // Force VGA scaler
	output        VGA_DISABLE, // analog out is off

	input  [11:0] HDMI_WIDTH,
	input  [11:0] HDMI_HEIGHT,
	output        HDMI_FREEZE,
	output        HDMI_BLACKOUT,

`ifdef MISTER_FB
	// Use framebuffer in DDRAM
	// FB_FORMAT:
	//    [2:0] : 011=8bpp(palette) 100=16bpp 101=24bpp 110=32bpp
	//    [3]   : 0=16bits 565 1=16bits 1555
	//    [4]   : 0=RGB  1=BGR (for 16/24/32 modes)
	//
	// FB_STRIDE either 0 (rounded to 256 bytes) or multiple of pixel size (in bytes)
	output        FB_EN,
	output  [4:0] FB_FORMAT,
	output [11:0] FB_WIDTH,
	output [11:0] FB_HEIGHT,
	output [31:0] FB_BASE,
	output [13:0] FB_STRIDE,
	input         FB_VBL,
	input         FB_LL,
	output        FB_FORCE_BLANK,

`ifdef MISTER_FB_PALETTE
	// Palette control for 8bit modes.
	// Ignored for other video modes.
	output        FB_PAL_CLK,
	output  [7:0] FB_PAL_ADDR,
	output [23:0] FB_PAL_DOUT,
	input  [23:0] FB_PAL_DIN,
	output        FB_PAL_WR,
`endif
`endif

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	// I/O board button press simulation (active high)
	// b[1]: user button
	// b[0]: osd button
	output  [1:0] BUTTONS,

	input         CLK_AUDIO, // 24.576 MHz
	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)

	//ADC
	inout   [3:0] ADC_BUS,

	//SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,

`ifdef MISTER_DUAL_SDRAM
	//Secondary SDRAM
	//Set all output SDRAM_* signals to Z ASAP if SDRAM2_EN is 0
	input         SDRAM2_EN,
	output        SDRAM2_CLK,
	output [12:0] SDRAM2_A,
	output  [1:0] SDRAM2_BA,
	inout  [15:0] SDRAM2_DQ,
	output        SDRAM2_nCS,
	output        SDRAM2_nCAS,
	output        SDRAM2_nRAS,
	output        SDRAM2_nWE,
`endif

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT,

	input         OSD_STATUS
);

///////// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;

assign LED_DISK = 0;
assign LED_POWER = 0;
assign BUTTONS = 0;



///////////////////////////////////////////////////////////
//////  PLL
////

wire            CLK72M, CLK57M, CLK48M;
wire            pll_locked;

pll pll(
    .refclk                     (CLK_50M                    ),
    .rst                        (RESET                      ),
    .outclk_0                   (CLK72M                     ),
    .outclk_1                   (SDRAM_CLK                  ),
	.outclk_2                   (CLK57M                     ),
	.outclk_3                   (CLK48M                     ),
    .locked                     (pll_locked                 )
);



///////////////////////////////////////////////////////////
//////  HPS_IO
////

// Status Bit Map:
//             Upper                             Lower              
// 0         1         2         3          4         5         6   
// 01234567890123456789012345678901 23456789012345678901234567890123
// 0123456789ABCDEFGHIJKLMNOPQRSTUV 0123456789ABCDEFGHIJKLMNOPQRSTUV
// X XXXXXXX X XXXXXXXXXXXXXXXXX

wire    [127:0] status; //status bits

`include "build_id.v" 
localparam CONF_STR = {
    "BubSysROM;",
    "-;",
    "P1,Scaler Settings;",
    "P1-;",
    "P1O23,Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
    "h0P1O4,Orientation,Horizontal,Vertical;",
    "P1O5,VGA Scaler,off,on;",
    "P1O68,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
    "-;",
    "P2,Game Settings;",
    "P2-;",
    "P2OA,Gamma,original,user;",
    "P2OS,Swap IRQ,default,IRQ2<=>IRQ1;",
    "P2OCF,K5289 volume,0,+1,+2,+3,+4,+5,+6,+7,-8,-7,-6,-5,-4,-3,-2,-1;",
    "P2OGJ,VLM volume,0,+1,+2,+3,+4,+5,+6,+7,-8,-7,-6,-5,-4,-3,-2,-1;",
    "P2OKN,PSG1 volume,0,+1,+2,+3,+4,+5,+6,+7,-8,-7,-6,-5,-4,-3,-2,-1;",
    "P2OOR,PSG2 volume,0,+1,+2,+3,+4,+5,+6,+7,-8,-7,-6,-5,-4,-3,-2,-1;",
    "-;",
    "DIP;",
    "-;",
    "R0,Reset and close OSD;",
    "J1,Button 1,Button 2,Button 3,Coin,Start,Service;",
    "jn,A,B,X,R,Start,Select;",

    "V,v",`BUILD_DATE 
};


//ioctl
wire    [15:0]  ioctl_index;
wire            ioctl_download;
wire    [26:0]  ioctl_addr;
wire    [7:0]   ioctl_data;
wire            ioctl_wr;
wire            ioctl_wait;

wire    [1:0]   buttons; //hardware button
wire    [15:0]  joystick_0;
wire    [15:0]  joystick_1;

wire            forced_scandoubler; //?
wire    [21:0]  gamma_bus;

wire            direct_video;

wire            video_rotation; //output from the core

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
    .clk_sys                    (CLK72M                     ),
    .HPS_BUS                    (HPS_BUS                    ),
    .EXT_BUS                    (                           ),

    .buttons                    (buttons                    ),
    .status                     (status                     ),
    .status_in                  (128'h0                     ),

    .status_menumask            ({15'd0, video_rotation}    ),
    .direct_video               (direct_video               ),
    .new_vmode                  (1'b0                       ), 

    .forced_scandoubler         (forced_scandoubler         ),
    .gamma_bus                  (gamma_bus                  ),

    .ioctl_download             (ioctl_download             ),
    .ioctl_upload               (                           ),
    .ioctl_upload_req           (1'b0                       ),
    .ioctl_wr                   (ioctl_wr                   ),
    .ioctl_addr                 (ioctl_addr                 ),
    .ioctl_dout                 (ioctl_data                 ),
    .ioctl_din                  (                           ),
    .ioctl_index                (ioctl_index                ),
    .ioctl_wait                 (ioctl_wait                 ),
    
    .joystick_0                 (joystick_0                 ),
    .joystick_1                 (joystick_1                 )
);



///////////////////////////////////////////////////////////
//////  CORE
////

wire            hsync, vsync;
wire            hblank, vblank;
wire    [4:0]   video_r_5bpp, video_g_5bpp, video_b_5bpp; //need to use color conversion LUT
wire            vcen;

reg     [3:0]   por_delay;
reg             soft_reset;
always @(posedge CLK72M) begin
    if(RESET | status[0] | buttons[1]) begin
        por_delay <= 4'd0;
        soft_reset <= 1'b1;
    end
    else begin
        por_delay <= por_delay == 4'd15 ? 4'd15 : por_delay + 4'd1;
        soft_reset <= soft_reset != 4'd15;
    end
end

assign          AUDIO_S = 1'b1;
assign          AUDIO_MIX = 2'd0;

BubSys_emu gameboard_top (
    .i_EMU_CLK72M               (CLK72M                     ),
    .i_EMU_CLK57M               (CLK57M                     ),
    .i_EMU_CLK48M               (CLK48M                     ),
    .i_EMU_INITRST              (RESET                      ),
    .i_EMU_SOFTRST              (RESET | status[0] | buttons[1]         ),

    .o_HBLANK                   (hblank                     ),
    .o_VBLANK                   (vblank                     ),
    .o_HSYNC                    (hsync                      ),
    .o_VSYNC                    (vsync                      ),
    .o_VIDEO_CEN                (vcen                       ),
    .o_VIDEO_DEN                (                           ),
    .o_VIDEO_ROT                (video_rotation             ),

    .o_VIDEO_R                  (video_r_5bpp               ),
    .o_VIDEO_G                  (video_g_5bpp               ),
    .o_VIDEO_B                  (video_b_5bpp               ),

    .i_VOL                      (status[27:12]              ),
    .o_SND_L                    (AUDIO_L                    ),
    .o_SND_R                    (AUDIO_R                    ),

    .i_MAINCPU_SWAPIRQ          (status[28]                 ),
    .o_BMC_ACC                  (LED_USER                   ),

    .i_JOYSTICK0                (joystick_0                 ),
    .i_JOYSTICK1                (joystick_1                 ),

    .ioctl_index                (ioctl_index                ),
    .ioctl_download             (ioctl_download             ),
    .ioctl_addr                 (ioctl_addr                 ),
    .ioctl_data                 (ioctl_data                 ),
    .ioctl_wr                   (ioctl_wr                   ),
    .ioctl_wait                 (ioctl_wait                 ),

    .sdram_dq                   (SDRAM_DQ                   ),
    .sdram_a                    (SDRAM_A                    ),
    .sdram_dqml                 (SDRAM_DQML                 ),
    .sdram_dqmh                 (SDRAM_DQMH                 ),
    .sdram_ba                   (SDRAM_BA                   ),
    .sdram_nwe                  (SDRAM_nWE                  ),
    .sdram_ncas                 (SDRAM_nCAS                 ),
    .sdram_nras                 (SDRAM_nRAS                 ),
    .sdram_ncs                  (SDRAM_nCS                  ),
    .sdram_cke                  (SDRAM_CKE                  ),

    .debug                      (                           )
);

//Bubble System resistor network gamma LUT, caculated by MAME's resnet.cpp
function [7:0] bubsys_gamma (input [4:0] bubsys_5bpp); begin
case(bubsys_5bpp)
    5'd0 : bubsys_gamma = 8'h00;
    5'd1 : bubsys_gamma = 8'h01;
    5'd2 : bubsys_gamma = 8'h02;
    5'd3 : bubsys_gamma = 8'h04;
    5'd4 : bubsys_gamma = 8'h05;
    5'd5 : bubsys_gamma = 8'h06;
    5'd6 : bubsys_gamma = 8'h08;
    5'd7 : bubsys_gamma = 8'h09;
    5'd8 : bubsys_gamma = 8'h0B;
    5'd9 : bubsys_gamma = 8'h0D;
    5'd10: bubsys_gamma = 8'h0F;
    5'd11: bubsys_gamma = 8'h12;
    5'd12: bubsys_gamma = 8'h14;
    5'd13: bubsys_gamma = 8'h16;
    5'd14: bubsys_gamma = 8'h19;
    5'd15: bubsys_gamma = 8'h1C;
    5'd16: bubsys_gamma = 8'h21;
    5'd17: bubsys_gamma = 8'h24;
    5'd18: bubsys_gamma = 8'h29;
    5'd19: bubsys_gamma = 8'h2E;
    5'd20: bubsys_gamma = 8'h33;
    5'd21: bubsys_gamma = 8'h39;
    5'd22: bubsys_gamma = 8'h40;
    5'd23: bubsys_gamma = 8'h49;
    5'd24: bubsys_gamma = 8'h50;
    5'd25: bubsys_gamma = 8'h5B;
    5'd26: bubsys_gamma = 8'h68;
    5'd27: bubsys_gamma = 8'h78;
    5'd28: bubsys_gamma = 8'h8E;
    5'd29: bubsys_gamma = 8'hA8;
    5'd30: bubsys_gamma = 8'hCC;
    5'd31: bubsys_gamma = 8'hFF;
endcase
end endfunction

wire    [7:0]   video_r_8bpp = status[10] ? {video_r_5bpp, 3'd0} : bubsys_gamma(video_r_5bpp);
wire    [7:0]   video_g_8bpp = status[10] ? {video_g_5bpp, 3'd0} : bubsys_gamma(video_g_5bpp);
wire    [7:0]   video_b_8bpp = status[10] ? {video_b_5bpp, 3'd0} : bubsys_gamma(video_b_5bpp);



///////////////////////////////////////////////////////////
//////  SCALER
////

assign VGA_F1 = 0;
assign VGA_SCALER = status[5];
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;

wire [1:0] ar = status[3:2];
wire            no_rotate = direct_video | ~status[4];
assign VIDEO_ARX = (!ar) ? no_rotate ? 12'd4 : 12'd3 : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? no_rotate ? 12'd3 : 12'd4 : 12'd0;

arcade_video #(256,24) arcade_video (
    .clk_video                  (CLK72M                     ),
    .ce_pix                     (vcen                       ),
     
    .RGB_in                     ({video_r_8bpp, video_g_8bpp, video_b_8bpp}),
    .HBlank                     (hblank                     ),
    .VBlank                     (vblank                     ),
    .HSync                      (hsync                      ),
    .VSync                      (vsync                      ),

    .CLK_VIDEO                  (CLK_VIDEO                  ),
    .CE_PIXEL                   (CE_PIXEL                   ),
    .VGA_R                      (VGA_R                      ),
    .VGA_G                      (VGA_G                      ),
    .VGA_B                      (VGA_B                      ),
    .VGA_HS                     (VGA_HS                     ),
    .VGA_VS                     (VGA_VS                     ),
    .VGA_DE                     (VGA_DE                     ),
    .VGA_SL                     (VGA_SL                     ),

    .fx                         (status[8:6]                ), //3bit
    .forced_scandoubler         (forced_scandoubler         ),
    .gamma_bus                  (gamma_bus                  ) //22bit
);

reg             flip = 1'b0;
reg             rotate_ccw = 1'b0;
wire            video_rotated;
screen_rotate screen_rotate ( .* );


endmodule
