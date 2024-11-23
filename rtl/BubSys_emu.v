module BubSys_emu (
    input   wire            i_EMU_CLK72M,
    input   wire            i_EMU_CLK57M,
    input   wire            i_EMU_CLK48M,
    input   wire            i_EMU_INITRST,
    input   wire            i_EMU_SOFTRST,

    //video syncs
    output  wire            o_HBLANK,
    output  wire            o_VBLANK,
    output  wire            o_HSYNC,
    output  wire            o_VSYNC,
    output  wire            o_VIDEO_CEN, //video clock enable
    output  wire            o_VIDEO_DEN, //video data enable
    output  wire            o_VIDEO_ROT, //only for twinbee

    output  wire    [4:0]   o_VIDEO_R,
    output  wire    [4:0]   o_VIDEO_G,
    output  wire    [4:0]   o_VIDEO_B,

    input   wire    [15:0]  i_VOL,
    output  wire signed      [15:0]  o_SND_L,
    output  wire signed      [15:0]  o_SND_R,

    input   wire            i_MAINCPU_SWAPIRQ,
    output  wire            o_BMC_ACC,

    input   wire    [15:0]  i_JOYSTICK0,
    input   wire    [15:0]  i_JOYSTICK1,

    //mister ioctl
    input   wire    [15:0]  ioctl_index,
    input   wire            ioctl_download,
    input   wire    [26:0]  ioctl_addr,
    input   wire    [7:0]   ioctl_data,
    input   wire            ioctl_wr, 
    output  wire            ioctl_wait,

    //mister sdram
    inout   wire    [15:0]  sdram_dq,
    output  wire    [12:0]  sdram_a,
    output  wire            sdram_dqml,
    output  wire            sdram_dqmh,
    output  wire    [1:0]   sdram_ba,
    output  wire            sdram_nwe,
    output  wire            sdram_ncas,
    output  wire            sdram_nras,
    output  wire            sdram_ncs,
    output  wire            sdram_cke,

    output  wire            debug
);



///////////////////////////////////////////////////////////
//////  ROM DISTRIBUTOR
////

//start addr    length        comp num     mame rom     parts num     location     description
//0x0000_0000   0x0004_0FFF                             FBM54DB       BANK0        bubble memory user page
//0x0004_1000   0x0000_2000   5l           400-a~e03    27C64         BRAM         sound program(bootloader/base)
//0x0004_3000   0x0000_0200                             FBM54DB       BRAM         bubble memory bootloader
//0x0004_3200   0x0000_0100   2a           400-a01      82S129        BRAM         wavetable
//0x0004_3300   0x0000_0100   1a           400-a02      82S129        BRAM         wavetable
//0x0004_3400          <-----------------ROM END----------------->

//dipsw bank
reg     [7:0]   DIPSW1 = 8'hFF;
reg     [7:0]   DIPSW2 = 8'h42;
reg     [7:0]   DIPSW3 = 8'hFF;
reg     [7:0]   CORECONFIG = 8'h00;

assign  o_VIDEO_ROT = CORECONFIG[1:0] == 2'd0;



///////////////////////////////////////////////////////////
//////  SDRAM/BRAM DOWNLOADER INTERFACE
////

//download complete
reg             rom_download_done = 1'b0;

//enables
reg             prog_sdram_en = 1'b0;
reg             prog_bram_en = 1'b0;

//sdram control
wire            sdram_init;
reg             prog_sdram_wr_busy = 1'b0;
wire            prog_sdram_ack;
assign          ioctl_wait = sdram_init | prog_sdram_wr_busy;
//assign          ioctl_wait = 1'b0;

reg     [1:0]   prog_sdram_bank_sel;
reg     [21:0]  prog_sdram_addr;
reg     [1:0]   prog_sdram_mask;
reg     [15:0]  prog_sdram_din_buf;

//bram control
reg     [13:0]  prog_bram_addr;
reg     [7:0]   prog_bram_din_buf;
reg             prog_bram_wr;
reg     [3:0]   prog_bram_csreg;

wire            prog_bram_wave2_cs = prog_bram_csreg[3];
wire            prog_bram_wave1_cs = prog_bram_csreg[2];
wire            prog_bram_bootrom_cs = prog_bram_csreg[1];
wire            prog_bram_sndrom_cs = prog_bram_csreg[0];
assign          debug = rom_download_done;

//state machine
always @(posedge i_EMU_CLK72M) begin
    if((i_EMU_INITRST | rom_download_done) == 1'b1) begin
        if(i_EMU_INITRST) rom_download_done <= 1'b0;

        //enables
        prog_sdram_en <= 1'b0;
        prog_bram_en <= 1'b0;
        
        //sdram
        prog_sdram_addr <= 22'h3F_FFFF;
        prog_sdram_wr_busy <= 1'b0;
        prog_sdram_bank_sel <= 2'd0;
        prog_sdram_mask <= 2'b00;
        prog_sdram_din_buf <= 16'hFFFF;

        //bram
        prog_bram_din_buf <= 8'hFF;
        prog_bram_addr <= 14'h3FFF;
        prog_bram_wr <= 1'b0;
        prog_bram_csreg <= 4'b0000;

        if(ioctl_index == 16'd254) begin //DIP SWITCH
            if(ioctl_wr == 1'b1) begin
                     if(ioctl_addr[2:0] == 3'd0) DIPSW1 <= ioctl_data;
                else if(ioctl_addr[2:0] == 3'd1) DIPSW2 <= ioctl_data;
                else if(ioctl_addr[2:0] == 3'd2) DIPSW3 <= ioctl_data;
                else if(ioctl_addr[2:0] == 3'd3) CORECONFIG <= ioctl_data;
            end
        end
    end
    else begin
        //  ROM DATA UPLOAD
        if(ioctl_index == 16'd0) begin //ROM DATA
            //  BLOCK RAM REGION
            if(ioctl_addr[19:12] > 8'h4_0 ) begin
                prog_sdram_en <= 1'b0;
                prog_bram_en <= 1'b1;

                if(ioctl_wr == 1'b1) begin
                    prog_bram_din_buf <= ioctl_data;
                    prog_bram_addr <= ioctl_addr[13:0] - 14'h1000;
                    prog_bram_wr <= 1'b1;

                    if(ioctl_addr[13:12] == 2'd1 || ioctl_addr[13:12] == 2'd2) prog_bram_csreg <= 4'b0001; //sound rom
                    else begin
                        if(ioctl_addr[9:8] == 2'd0 || ioctl_addr[9:8] == 2'd1) prog_bram_csreg <= 4'b0010;
                        else if(ioctl_addr[9:8] == 2'd2) prog_bram_csreg <= 4'b0100; //wavetable 1(400-A 01)
                        else if(ioctl_addr[9:8] == 2'd3) prog_bram_csreg <= 4'b1000;
                    end
                end
                else begin
                    prog_bram_wr <= 1'b0;
                end
            end

            //  SDRAM REGION
            else begin
                prog_sdram_en <= 1'b1;
                prog_bram_en <= 1'b0;
                
                if(prog_sdram_wr_busy == 1'b0) begin
                    if(ioctl_wr == 1'b1) begin
                        prog_sdram_wr_busy <= 1'b1;
                        prog_sdram_bank_sel <= 2'd0;
                        prog_sdram_addr <= {4'b00_00, ioctl_addr[18:1]};
                        prog_sdram_din_buf <= {ioctl_data, ioctl_data};
                        prog_sdram_mask <= ioctl_addr[0] ? 2'b10 : 2'b01; //lo : hi(68k big endian)
                    end
                end
                else begin
                    if(prog_sdram_ack == 1'b1) begin  
                        prog_sdram_wr_busy <= 1'b0;
                    end
                end
            end
        end

        else if(ioctl_index == 16'd254) begin //DIP SWITCH
            prog_sdram_en <= 1'b0;
            prog_bram_en <= 1'b0;
            rom_download_done <= 1'b1;
        end
    end
end



///////////////////////////////////////////////////////////
//////  BUBBLE MEMORY(BOOTLOADER)
////

wire    [17:0]  bubrom_addr;
wire            bubrom_boot_cs;
wire    [15:0]  bubrom_boot_q;
reg     [7:0]   prog_bram_din_hi;
always @(posedge i_EMU_CLK72M) if(prog_bram_wr & ~prog_bram_addr[0]) prog_bram_din_hi <= prog_bram_din_buf;

BubSys_PROM_DC #(.AW(8), .DW(16), .simhexfile()) u_bootrom_lo (
    .i_PROG_CLK                 (i_EMU_CLK72M               ),
    .i_PROG_ADDR                (prog_bram_addr[8:1]        ),
    .i_PROG_DIN                 ({prog_bram_din_hi, prog_bram_din_buf}),
    .i_PROG_CS                  (prog_bram_bootrom_cs       ),
    .i_PROG_WR                  (prog_bram_wr & prog_bram_addr[0]),

    .i_MCLK                     (i_EMU_CLK48M               ),
    .i_ADDR                     (bubrom_addr[7:0]           ),
    .o_DOUT                     (bubrom_boot_q              ),
    .i_RD                       (bubrom_boot_cs             )
);



///////////////////////////////////////////////////////////
//////  SDRAM CONTROLLER
////

wire    [21:0]  ba0_addr;
wire    [21:0]  ba1_addr;
wire    [21:0]  ba2_addr;
wire    [3:0]   rd;           
wire    [3:0]   ack;
wire    [3:0]   dst;
wire    [3:0]   rdy;
wire    [15:0]  data_read;

reg     [8:0]   rfsh_cntr;
wire            rfsh = rfsh_cntr == 9'd384;
always @(posedge i_EMU_CLK72M) begin
    if(i_EMU_INITRST) begin
        rfsh_cntr <= 9'd0;
    end
    else begin if(o_VIDEO_CEN) begin
        if(rfsh_cntr < 9'd384) rfsh_cntr <= rfsh_cntr + 9'd1;
        else rfsh_cntr <= 9'd0;
    end end
end

jtframe_sdram64 #(.HF(0)) sdram_controller (
    .rst                        (i_EMU_INITRST              ),
    .clk                        (i_EMU_CLK72M               ),
    .init                       (sdram_init                 ),

    .ba0_addr                   (ba0_addr                   ),
    .ba1_addr                   (ba1_addr                   ),
    .ba2_addr                   (22'h00_0000                ),
    .ba3_addr                   (22'h00_0000                ),
    .rd                         ({3'b000, rd[0]}            ),
    .wr                         (4'b0000                    ),
    .din                        (prog_sdram_din_buf         ),
    .din_m                      (2'b00                      ),

    .prog_en                    (prog_sdram_en              ),
    .prog_addr                  (prog_sdram_addr            ),
    .prog_rd                    (1'b0                       ),
    .prog_wr                    (prog_sdram_wr_busy         ),
    .prog_din                   (prog_sdram_din_buf         ),
    .prog_din_m                 (prog_sdram_mask            ),
    .prog_ba                    (prog_sdram_bank_sel        ),
    .prog_dst                   (                           ),
    .prog_dok                   (                           ),
    .prog_rdy                   (                           ),
    .prog_ack                   (prog_sdram_ack             ),

    .rfsh                       (rfsh                       ),

    .ack                        (ack                        ),
    .dst                        (dst                        ),
    .dok                        (                           ),
    .rdy                        (rdy                        ),
    .dout                       (data_read                  ),

    .sdram_dq                   (sdram_dq                   ),
    .sdram_a                    (sdram_a                    ),
    .sdram_dqml                 (sdram_dqml                 ),
    .sdram_dqmh                 (sdram_dqmh                 ),
    .sdram_ba                   (sdram_ba                   ),
    .sdram_nwe                  (sdram_nwe                  ),
    .sdram_ncas                 (sdram_ncas                 ),
    .sdram_nras                 (sdram_nras                 ),
    .sdram_ncs                  (sdram_ncs                  ),
    .sdram_cke                  (sdram_cke                  )
);



///////////////////////////////////////////////////////////
//////  ROM SLOTS
////

wire            bubrom_rd;
wire            bubrom_page_cs;
wire    [15:0]  bubrom_page_q;

reg             slot0_rdrq_z, slot0_rdrq_zz; //48MHz -> 72MHz
always @(posedge i_EMU_CLK72M) slot0_rdrq_z <= bubrom_rd & bubrom_page_cs;
always @(posedge i_EMU_CLK72M) slot0_rdrq_zz <= slot0_rdrq_z;

wire            slot0_ok;
reg     [3:0]   slot0_ok_dly;
always @(posedge i_EMU_CLK72M) begin
    slot0_ok_dly[0] <= slot0_ok;
    slot0_ok_dly[3:1] <= slot0_ok_dly[2:0];
end
reg             slot0_ok_z, slot0_ok_zz; //72MHz -> 48MHz
always @(posedge i_EMU_CLK48M) slot0_ok_z <= |{slot0_ok_dly[3:0]};
always @(posedge i_EMU_CLK48M) slot0_ok_zz <= slot0_ok_z;

jtframe_rom_2slots #(
    // Slot 0: Bubble Memory user pages
    .SLOT0_AW                   (18                         ),
    .SLOT0_DW                   (16                         ),
    .SLOT0_OFFSET               (22'h00_0000                ),
    
    // Slot 1: No ROM
    .SLOT1_AW                   (4                          ),
    .SLOT1_DW                   (16                         ),
    .SLOT1_OFFSET               (22'h02_0800                )
) bank0 (
    .rst                        (~rom_download_done         ),
    .clk                        (i_EMU_CLK72M               ),

    .slot0_cs                   (slot0_rdrq_zz              ),
    .slot1_cs                   (1'b0                       ),

    .slot0_ok                   (slot0_ok                   ),
    .slot1_ok                   (                           ),

    .slot0_addr                 (bubrom_addr                ),
    .slot1_addr                 (4'b0000                    ),

    .slot0_dout                 (bubrom_page_q              ),
    .slot1_dout                 (                           ),

    .sdram_addr                 (ba0_addr                   ),
    .sdram_req                  (rd[0]                      ),
    .sdram_ack                  (ack[0]                     ),
    .data_dst                   (dst[0]                     ),
    .data_rdy                   (rdy[0]                     ),
    .data_read                  (data_read                  )
);



///////////////////////////////////////////////////////////
//////  INPUT MAPPER
////

/*
    MiSTer joystick(SNES)
    bit   
    0   right
    1   left
    2   down
    3   up
    4   service(SELECT)
    5   coin(R)
    6   start(START)
    7   btn1(A)
    8   btn2(B)
    9   btn3(X)
*/

wire    [7:0]   IN0, IN1, IN2;

//System control
assign          IN0[0]  = ~i_JOYSTICK0[5]; //p1 coin
assign          IN0[1]  = ~i_JOYSTICK1[5]; //p2 coin
assign          IN0[2]  = ~i_JOYSTICK0[4]; //service
assign          IN0[3]  = ~i_JOYSTICK0[6]; //p1 start
assign          IN0[4]  = ~i_JOYSTICK1[6]; //p2 start
assign          IN0[5]  = 1'b1;
assign          IN0[6]  = 1'b1;
assign          IN0[7]  = 1'b1;

//Player 1 control
assign          IN1[0]  = ~i_JOYSTICK0[1];
assign          IN1[1]  = ~i_JOYSTICK0[0];
assign          IN1[2]  = ~i_JOYSTICK0[3];
assign          IN1[3]  = ~i_JOYSTICK0[2];
assign          IN1[4]  = ~i_JOYSTICK0[7];
assign          IN1[5]  = ~i_JOYSTICK0[8];
assign          IN1[6]  = ~i_JOYSTICK0[9];
assign          IN1[7]  = 1'b1;

//Player 2 control
assign          IN2[0]  = ~i_JOYSTICK1[1];
assign          IN2[1]  = ~i_JOYSTICK1[0];
assign          IN2[2]  = ~i_JOYSTICK1[3];
assign          IN2[3]  = ~i_JOYSTICK1[2];
assign          IN2[4]  = ~i_JOYSTICK1[7]; //btn 1
assign          IN2[5]  = ~i_JOYSTICK1[8]; //btn 2
assign          IN2[6]  = ~i_JOYSTICK1[9];
assign          IN2[7]  = 1'b1;



///////////////////////////////////////////////////////////
//////  GAME BOARD
////

reg     [15:0]  bubrom_data;
reg             bubrom_data_rdy;

always @(*) begin
    bubrom_data = 16'h0000;
    if(bubrom_boot_cs) bubrom_data = bubrom_boot_q;
    else if(bubrom_page_cs) bubrom_data = bubrom_page_q;

    bubrom_data_rdy = 1'b0;
    if(bubrom_boot_cs) bubrom_data_rdy = 1'b1;
    else if(bubrom_page_cs) bubrom_data_rdy = slot0_ok_zz;
end

BubSys_top gameboard_top (
    .i_EMU_CLK72M               (i_EMU_CLK72M               ),
    .i_EMU_CLK57M               (i_EMU_CLK57M               ),
    .i_EMU_CLK48M               (i_EMU_CLK48M               ),
    .i_EMU_INITRST_n            (~i_EMU_INITRST             ),
    .i_EMU_SOFTRST_n            (~i_EMU_SOFTRST & rom_download_done),

    .o_HBLANK                   (o_HBLANK                   ),
    .o_VBLANK                   (o_VBLANK                   ),
    .o_HSYNC                    (o_HSYNC                    ),
    .o_VSYNC                    (o_VSYNC                    ),
    .o_VIDEO_CEN                (o_VIDEO_CEN                ),
    .o_VIDEO_DEN                (o_VIDEO_DEN                ),

    .o_VIDEO_R                  (o_VIDEO_R                  ),
    .o_VIDEO_G                  (o_VIDEO_G                  ),
    .o_VIDEO_B                  (o_VIDEO_B                  ),

    .i_VOL                      (i_VOL                      ),
    .o_SND_L                    (o_SND_L                    ),
    .o_SND_R                    (o_SND_R                    ),

    .i_MAINCPU_SWAPIRQ          (i_MAINCPU_SWAPIRQ          ),
    .o_BMC_ACC                  (o_BMC_ACC                  ),

    .i_IN0                      (IN0                        ),
    .i_IN1                      (IN1                        ),
    .i_IN2                      (IN2                        ),
    .i_DIPSW1                   (DIPSW1                     ),
    .i_DIPSW2                   (DIPSW2                     ),
    .i_DIPSW3                   (DIPSW3                     ),

    //DRAM request, 48MHz
    .o_BUBROM_BOOT_CS           (bubrom_boot_cs             ),
    .o_BUBROM_PAGE_CS           (bubrom_page_cs             ),
    .o_BUBROM_ADDR              (bubrom_addr                ),
    .i_BUBROM_DATA              (bubrom_data                ),
    .o_BUBROM_RD                (bubrom_rd                  ),
    .i_BUBROM_DATA_RDY          (bubrom_data_rdy            ),

    //PROM programming
    .i_EMU_PROM_ADDR            (prog_bram_addr             ),
    .i_EMU_PROM_DATA            (prog_bram_din_buf          ),
    .i_EMU_PROM_WR              (prog_bram_wr               ),
    .i_EMU_PROM_WAVE1_CS        (prog_bram_wave1_cs         ),
    .i_EMU_PROM_WAVE2_CS        (prog_bram_wave2_cs         ),
    .i_EMU_PROM_SNDROM_CS       (prog_bram_sndrom_cs        )
);

endmodule