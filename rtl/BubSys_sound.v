module BubSys_sound (
    input   wire            i_EMU_MCLK,
    input   wire            i_EMU_CLK3M58_PCEN,
    input   wire            i_EMU_CLK3M58_NCEN,
    input   wire            i_EMU_CLK1M79_PCEN,
    input   wire            i_EMU_CLK1M79_NCEN,

    input   wire            i_EMU_INITRST_n,
    input   wire            i_EMU_SOFTRST_n,

    //reset control by the sound CPU
    output  wire            o_MAINCPU_RSTCTRL,
    input   wire            i_MAINCPU_RSTSTAT,

    input   wire            i_SND_NMI,
    input   wire            i_SND_INT,
    input   wire    [7:0]   i_SND_CODE,
    input   wire            i_SND_DMA_BR,
    output  wire            o_SND_DMA_BG_n,
    input   wire    [14:1]  i_SND_DMA_ADDR,
    input   wire    [7:0]   i_SND_DMA_DO,
    output  wire    [7:0]   o_SND_DMA_DI,
    input   wire            i_SND_DMA_RnW,
    input   wire            i_SND_DMA_LDS_n,
    input   wire            i_SND_DMA_SNDRAM_CS,

    output  wire            o_TIMER_IRQ,

    input   wire    [15:0]  i_VOL,
    output  wire signed     [15:0]  o_SND_R, o_SND_L,

    input   wire            i_EMU_PROM_CLK,
    input   wire    [13:0]  i_EMU_PROM_ADDR,
    input   wire    [7:0]   i_EMU_PROM_DATA,
    input   wire            i_EMU_PROM_WR,
    
    input   wire            i_EMU_PROM_WAVE1_CS,
    input   wire            i_EMU_PROM_WAVE2_CS,
    input   wire            i_EMU_PROM_SNDROM_CS
);



///////////////////////////////////////////////////////////
//////  CLOCK AND RESET
////

wire            sndcpu_rst = ~i_EMU_INITRST_n | ~i_EMU_SOFTRST_n;
wire            mclk = i_EMU_MCLK;
wire            clk3m58_pcen = i_EMU_CLK3M58_PCEN;
wire            clk3m58_ncen = i_EMU_CLK3M58_NCEN;
wire            clk1m79_pcen = i_EMU_CLK1M79_PCEN;
wire            clk1m79_ncen = i_EMU_CLK1M79_NCEN;




///////////////////////////////////////////////////////////
//////  SOUND CPU
////

wire    [15:0]  sndcpu_addr;
reg     [7:0]   sndbus_di;
wire    [7:0]   sndcpu_do;
wire            sndcpu_wr_n, sndcpu_rd_n;

wire            sndcpu_mreq_n;
wire            sndcpu_iorq_n;
wire            sndcpu_rfsh_n;
reg             sndcpu_int_n;
wire            sndcpu_nmi_n;
wire            sndcpu_br_n;

T80pa u_sndcpu (
    .RESET_n                    (~sndcpu_rst                ),
    .CLK                        (mclk                       ),
    .CEN_p                      (clk1m79_pcen               ),
    .CEN_n                      (clk1m79_ncen               ),
    .WAIT_n                     (1'b1                       ),
    .INT_n                      (sndcpu_int_n               ),
    .NMI_n                      (sndcpu_nmi_n               ),
    .RD_n                       (sndcpu_rd_n                ),
    .WR_n                       (sndcpu_wr_n                ),
    .A                          (sndcpu_addr                ),
    .DI                         (sndbus_di                  ),
    .DO                         (sndcpu_do                  ),
    .IORQ_n                     (sndcpu_iorq_n              ),
    .M1_n                       (                           ),
    .MREQ_n                     (sndcpu_mreq_n              ),
    .BUSRQ_n                    (sndcpu_br_n                ),
    .BUSAK_n                    (o_SND_DMA_BG_n             ),
    .RFSH_n                     (sndcpu_rfsh_n              ),
    .out0                       (1'b0                       ), //?????
    .HALT_n                     (                           )
);



///////////////////////////////////////////////////////////
//////  DMA
////

reg     [1:0]   snd_dma_br_sync;
assign  sndcpu_br_n = ~snd_dma_br_sync[1];
always @(posedge mclk) begin
    snd_dma_br_sync[0] <= i_SND_DMA_BR;
    snd_dma_br_sync[1] <= snd_dma_br_sync[0];
end

//68k bus control synchronizer/negedge detector <- CDC!!
reg     [3:0]   snd_dma_wr_n_sync, snd_dma_rd_n_sync;
reg             snd_dma_wrrq_n, snd_dma_rdrq_n;
always @(posedge mclk) begin
    //synchronize read/write strobe only, the address/data is guaranteed to be stable before the strobe is asserted
    snd_dma_wr_n_sync[0] <=  i_SND_DMA_RnW | i_SND_DMA_LDS_n;
    snd_dma_wr_n_sync[3:1] <= snd_dma_wr_n_sync[2:0];

    snd_dma_rd_n_sync[0] <=  ~i_SND_DMA_RnW | i_SND_DMA_LDS_n;
    snd_dma_rd_n_sync[3:1] <= snd_dma_rd_n_sync[2:0];

    snd_dma_wrrq_n <= ~(snd_dma_wr_n_sync[3] && !snd_dma_wr_n_sync[2]);
    snd_dma_rdrq_n <= ~(snd_dma_rd_n_sync[3] && !snd_dma_rd_n_sync[2]);
end

wire            is_dma_acc = ~o_SND_DMA_BG_n;
wire    [15:0]  sndbus_addr     = is_dma_acc ? {2'b01, i_SND_DMA_ADDR} : sndcpu_addr;
wire    [7:0]   sndbus_do       = is_dma_acc ? i_SND_DMA_DO : sndcpu_do;
wire            sndbus_wr_n     = is_dma_acc ? snd_dma_wrrq_n : sndcpu_wr_n;
wire            sndbus_rd_n     = is_dma_acc ? snd_dma_rdrq_n : sndcpu_rd_n;
wire            sndbus_mreq_n   = is_dma_acc ? ~i_SND_DMA_SNDRAM_CS : sndcpu_mreq_n;
wire            sndbus_rfsh_n   = is_dma_acc ? 1'b1 : sndcpu_rfsh_n;
assign  o_SND_DMA_DI = sndbus_di;


///////////////////////////////////////////////////////////
//////  SOUND IRQ
////

reg     [3:0]   snd_int_sync; //CDC!!!
reg     [1:0]   snd_nmi_sync;
assign  sndcpu_nmi_n = ~snd_nmi_sync[1];
always @(posedge mclk) begin
    snd_int_sync[0] <= i_SND_INT;
    snd_int_sync[3:1] <= snd_int_sync[2:0];

    if(sndcpu_rst | ~sndcpu_iorq_n) sndcpu_int_n <= 1'b1;
    else begin
        if(snd_int_sync[3:2] == 2'b01) sndcpu_int_n <= 1'b0;
    end

    snd_nmi_sync[0] <= i_SND_NMI;
    snd_nmi_sync[1] <= snd_nmi_sync[0];
end



///////////////////////////////////////////////////////////
//////  ADDRESS DECODER
////

reg             sndrom_rd, sndram_cs, voiceram_cs, wave1_wr, wave2_wr;
reg             vlmctrl_wr, sndcode_rd, wave1_tg, wave2_tg, psg1_cs, psg2_cs, fltctrl_wr;

always @(*) begin
    sndrom_rd = 1'b0;
    sndram_cs = 1'b0;
    voiceram_cs = 1'b0;
    wave1_wr = 1'b0;
    wave2_wr = 1'b0;
    
    vlmctrl_wr = 1'b0;
    sndcode_rd = 1'b0;
    wave1_tg = 1'b0;
    wave2_tg = 1'b0;
    psg1_cs = 1'b0;
    psg2_cs = 1'b0;
    fltctrl_wr = 1'b0;

    //1st LS138
    if(!sndbus_mreq_n && sndbus_rfsh_n) begin
        case(sndbus_addr[15:13])
            3'd0: sndrom_rd = 1'b1;
            3'd2: sndram_cs = 1'b1;
            3'd3: sndram_cs = 1'b1;
            3'd4: voiceram_cs = 1'b1;
            3'd5: wave1_wr = 1'b1;
            3'd6: wave2_wr = 1'b1;
            default: ;
        endcase
    end

    //2nd LS138
    if(!sndbus_mreq_n && sndbus_rfsh_n && sndbus_addr[15:13] == 3'd7) begin
        case(sndbus_addr[2:0])
            3'd0: vlmctrl_wr = 1'b1;
            3'd1: sndcode_rd = 1'b1;
            3'd3: wave1_tg = 1'b1;
            3'd4: wave2_tg = 1'b1;
            3'd5: psg2_cs = 1'b1;
            3'd6: psg1_cs = 1'b1;
            3'd7: fltctrl_wr = 1'b1;
            default: ;
        endcase
    end
end



///////////////////////////////////////////////////////////
//////  SOUND PROGRAM SPACE
////

wire    [7:0]   sndrom_q;
BubSys_PROM_DC #(.AW(13), .DW(8), .simhexfile()) u_sndrom (
    .i_PROG_CLK                 (i_EMU_PROM_CLK             ),
    .i_PROG_ADDR                (i_EMU_PROM_ADDR[12:0]      ),
    .i_PROG_DIN                 (i_EMU_PROM_DATA            ),
    .i_PROG_CS                  (i_EMU_PROM_SNDROM_CS       ),
    .i_PROG_WR                  (i_EMU_PROM_WR              ),

    .i_MCLK                     (i_EMU_MCLK                 ),
    .i_ADDR                     (sndbus_addr[12:0]          ),
    .o_DOUT                     (sndrom_q                   ),
    .i_RD                       (sndrom_rd                  )
);

wire    [7:0]  sndram_q;
BubSys_SRAM #(.AW(14), .DW(8), .simhexfile()) u_sndram (
    .i_MCLK                     (i_EMU_MCLK                 ),
    .i_ADDR                     (sndbus_addr[13:0]          ),
    .i_DIN                      (sndbus_do                  ),
    .o_DOUT                     (sndram_q                   ),
    .i_WR                       (sndram_cs && !sndbus_wr_n  ),
    .i_RD                       (sndram_cs && !sndbus_rd_n  )
);



///////////////////////////////////////////////////////////
//////  SOUND TIMER
////

//14.31818MHz clocked four LS393 half blocks, take [13:0] MSBs
reg     [12:0]  snd_timer;
always @(posedge mclk) begin
    //if(sndcpu_rst) snd_timer <= 13'd0; //doesn't have reset originally
    //else begin 
    if(clk1m79_ncen) snd_timer <= snd_timer == 13'd8191 ? 13'd0 : snd_timer + 13'd1;
    //end end
end

assign  o_TIMER_IRQ = snd_timer[12];



///////////////////////////////////////////////////////////
//////  VLM5030
////

//VLM5030 control latches
reg     [7:0]   vlm_param_latch; //LS373 transparent latch
reg     [3:0]   vlm_ctrl_latch = 4'b0010; //{vlm_rst, vlm_start, /vlm_param_latch_oe, vlm_param_latch_en}

always @(posedge mclk) begin
    if(vlmctrl_wr && !sndbus_wr_n) vlm_ctrl_latch <= sndbus_addr[6:3];

    if(vlm_ctrl_latch[0]) vlm_param_latch <= sndbus_do;
end

//VLM5030 side wires
wire            vlm_rst = vlm_ctrl_latch[3];
wire            vlm_st = vlm_ctrl_latch[2];
wire            vlm_busy;

wire    [15:0]  vlm_addr;
wire            vlm_me_n; //Memory Enable
wire signed     [9:0]   vlm_sound;

//VLM5030 command rom
wire    [10:0]  voiceram_addr = voiceram_cs ? sndbus_addr[10:0] : vlm_addr[10:0];
wire    [7:0]   voiceram_q;
BubSys_SRAM #(.AW(11), .DW(8), .simhexfile()) u_voiceram (
    .i_MCLK                     (i_EMU_MCLK                 ),
    .i_ADDR                     (voiceram_addr              ),
    .i_DIN                      (vlm_param_latch            ),
    .o_DOUT                     (voiceram_q                 ),
    .i_WR                       (voiceram_cs && !sndbus_wr_n),
    .i_RD                       (1'b1                       )
);


//VLM5030 bus
wire    [7:0]   vlm_di = vlm_me_n ? vlm_param_latch : voiceram_q; //negative logic

//main chip
vlm5030_gl u_vlm (
    .i_clk                      (i_EMU_MCLK                 ),
    .i_oscen                    (clk3m58_pcen               ),
    .i_rst                      (vlm_rst                    ),
    .i_start                    (vlm_st                     ),
    .i_vcu                      (1'b0                       ),
    .i_tst1                     (1'b0                       ),
    .i_d                        (vlm_di                     ),
    .o_a                        (vlm_addr                   ),
    .o_me_l                     (vlm_me_n                   ),
    .o_bsy                      (vlm_busy                   ),
    .o_audio                    (vlm_sound                  )
);



///////////////////////////////////////////////////////////
//////  AY-3-8910
////

wire    [7:0]   psg1_q, psg2_q;
wire    [7:0]   psg1_iob_out, psg2_ioa_out, psg2_iob_out;
wire    [9:0]   psg1_sound, psg2_sound;
assign  o_MAINCPU_RSTCTRL = ~psg1_iob_out[7];

//MAME PSG1(4F on the board)
jt49_bus u_psg1 (
    .rst_n                      (~sndcpu_rst                ),
    .clk                        (mclk                       ),
    .clk_en                     (clk1m79_pcen               ),
    .bdir                       (psg1_cs & (~sndcpu_rd_n | ~sndcpu_wr_n) & ~sndbus_addr[7]),
    .bc1                        (psg1_cs & (~sndcpu_rd_n | ~sndcpu_wr_n) & ~sndbus_addr[8]),
    .din                        (sndbus_do                  ),

    .sel                        (1'b1                       ),
    .dout                       (psg1_q                     ),
    .sound                      (psg1_sound                 ),
    .A                          (                           ),
    .B                          (                           ),
    .C                          (                           ),
    .sample                     (                           ),

    .IOA_in                     ({~i_MAINCPU_RSTSTAT, 1'b1, vlm_busy, 1'b1, snd_timer[12:9]}),
    .IOA_out                    (                           ),
    .IOA_oe                     (                           ),

    .IOB_in                     (                           ),
    .IOB_out                    (psg1_iob_out               ),
    .IOB_oe                     (                           )
);

//MAME PSG2(4H on the board)
jt49_bus u_psg2 (
    .rst_n                      (~sndcpu_rst                ),
    .clk                        (mclk                       ),
    .clk_en                     (clk1m79_pcen               ),
    .bdir                       (psg2_cs & (~sndcpu_rd_n | ~sndcpu_wr_n) & ~sndbus_addr[9]),
    .bc1                        (psg2_cs & (~sndcpu_rd_n | ~sndcpu_wr_n) & ~sndbus_addr[10]),
    .din                        (sndbus_do                  ),

    .sel                        (1'b1                       ),
    .dout                       (psg2_q                     ),
    .sound                      (psg2_sound                 ),
    .A                          (                           ),
    .B                          (                           ),
    .C                          (                           ),
    .sample                     (                           ),

    .IOA_in                     (                           ),
    .IOA_out                    (psg2_ioa_out               ),
    .IOA_oe                     (                           ),

    .IOB_in                     (                           ),
    .IOB_out                    (psg2_iob_out               ),
    .IOB_oe                     (                           )
);



///////////////////////////////////////////////////////////
//////  K005289 WAVETABLE
////

wire    [4:0]   prom1_addr, prom2_addr;
wire    [3:0]   prom1_q, prom2_q;
wire    [7:0]   wave1_sound, wave2_sound;

//wavetable address generator
K005289 u_K005289(
    .i_RST_n                    (~sndcpu_rst                ),
    .i_CLK                      (mclk                       ),
    .i_CEN                      (clk3m58_pcen               ),

    .i_LD1                      (wave1_wr                   ),
    .i_TG1                      (wave1_tg                   ),

    .i_LD2                      (wave2_wr                   ),
    .i_TG2                      (wave2_tg                   ),

    .i_COUNTER                  (sndbus_addr[11:0]          ),

    .o_Q1                       (prom1_addr                 ),
    .o_Q2                       (prom2_addr                 )
);

//wavetable ROMs
BubSys_PROM_DC #(.AW(8), .DW(4), .simhexfile()) u_waverom1 (
    .i_PROG_CLK                 (i_EMU_PROM_CLK             ),
    .i_PROG_ADDR                (i_EMU_PROM_ADDR[7:0]       ),
    .i_PROG_DIN                 (i_EMU_PROM_DATA[3:0]       ),
    .i_PROG_CS                  (i_EMU_PROM_WAVE1_CS        ),
    .i_PROG_WR                  (i_EMU_PROM_WR              ),

    .i_MCLK                     (i_EMU_MCLK                 ),
    .i_ADDR                     ({psg2_ioa_out[7:5], prom1_addr}),
    .o_DOUT                     (prom1_q                    ),
    .i_RD                       (1'b1                       )
);

BubSys_PROM_DC #(.AW(8), .DW(4), .simhexfile()) u_waverom2 (
    .i_PROG_CLK                 (i_EMU_PROM_CLK             ),
    .i_PROG_ADDR                (i_EMU_PROM_ADDR[7:0]       ),
    .i_PROG_DIN                 (i_EMU_PROM_DATA[3:0]       ),
    .i_PROG_CS                  (i_EMU_PROM_WAVE2_CS        ),
    .i_PROG_WR                  (i_EMU_PROM_WR              ),

    .i_MCLK                     (i_EMU_MCLK                 ),
    .i_ADDR                     ({psg2_iob_out[7:5], prom2_addr}),
    .o_DOUT                     (prom2_q                    ),
    .i_RD                       (1'b1                       )
);

//volume LUT, replaces 4066 switches
BubSys_PROM #(.AW(8), .DW(8), .simhexfile("./rtl/ipcores/vollut.txt")) u_vollut1 (
    .i_MCLK                     (i_EMU_MCLK                 ),

    .i_PROG_ADDR                (                           ),
    .i_PROG_DIN                 (                           ),
    .i_PROG_CS                  (1'b1                       ),
    .i_PROG_WR                  (                           ),

    .i_ADDR                     ({psg2_ioa_out[3:0], prom1_q}),
    .o_DOUT                     (wave1_sound                ),
    .i_RD                       (1'b1                       )
);

BubSys_PROM #(.AW(8), .DW(8), .simhexfile("./rtl/ipcores/vollut.txt")) u_vollut2 (
    .i_MCLK                     (i_EMU_MCLK                 ),

    .i_PROG_ADDR                (                           ),
    .i_PROG_DIN                 (                           ),
    .i_PROG_CS                  (1'b1                       ),
    .i_PROG_WR                  (                           ),

    .i_ADDR                     ({psg2_iob_out[3:0], prom2_q}),
    .o_DOUT                     (wave2_sound                ),
    .i_RD                       (1'b1                       )
);



///////////////////////////////////////////////////////////
//////  SOUND MIXER
////

/*
    psg_sound = 10-bit unsigned
    vlm_sound = 10-bit signed
    wavex_sound = 8-bit(normally 7-bit) unsigned
*/

wire signed [9:0]   psg1_sound_ac, psg2_sound_ac;
jt49_dcrm2 #(.sw(10)) psg1_accap (.clk(mclk), .cen(clk3m58_pcen), .rst(sndcpu_rst), .din(psg1_sound), .dout(psg1_sound_ac));
jt49_dcrm2 #(.sw(10)) psg2_accap (.clk(mclk), .cen(clk3m58_pcen), .rst(sndcpu_rst), .din(psg2_sound), .dout(psg2_sound_ac));

wire signed [7:0]   wave1_sound_ac, wave2_sound_ac;
jt49_dcrm2 #(.sw(8)) wave1_accap (.clk(mclk), .cen(clk3m58_pcen), .rst(sndcpu_rst), .din(wave1_sound), .dout(wave1_sound_ac));
jt49_dcrm2 #(.sw(8)) wave2_accap (.clk(mclk), .cen(clk3m58_pcen), .rst(sndcpu_rst), .din(wave2_sound), .dout(wave2_sound_ac));

reg signed  [13:0]  psg1_sound_vol, psg2_sound_vol;
reg signed  [13:0]  vlm_sound_vol;
reg signed  [13:0]  wave1_sound_vol, wave2_sound_vol;
reg signed  [15:0]  final_sound;
assign  o_SND_L = final_sound;
assign  o_SND_R = final_sound;

always @(posedge mclk) begin
    psg1_sound_vol  <= psg1_sound_ac  * (6'sd8  + $signed(i_VOL[11:8]));
    psg2_sound_vol  <= psg2_sound_ac  * (6'sd12 + $signed(i_VOL[15:12]));
    vlm_sound_vol   <= vlm_sound      * (6'sd10 + $signed(i_VOL[7:4]));
    wave1_sound_vol <= wave1_sound_ac * (6'sd8  + $signed(i_VOL[3:0]));
    wave2_sound_vol <= wave2_sound_ac * (6'sd8  + $signed(i_VOL[3:0]));
    final_sound <= (psg1_sound_vol + psg2_sound_vol + vlm_sound_vol + wave1_sound_vol + wave2_sound_vol) * 3'sd2;
end



///////////////////////////////////////////////////////////
//////  BUS MUX
////

always @(*) begin
    sndbus_di = 8'hFF;

    if(sndrom_rd) begin
        sndbus_di = sndrom_q;
    end
    else if(sndram_cs) sndbus_di = sndram_q;
    else if(sndcode_rd) sndbus_di = i_SND_CODE;
    else if(psg1_cs) sndbus_di = psg1_q;
    else if(psg2_cs) sndbus_di = psg2_q;
end



endmodule