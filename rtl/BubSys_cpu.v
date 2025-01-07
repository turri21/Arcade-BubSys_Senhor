`timescale 10ns/10ns
module BubSys_cpu (
    input   wire            i_EMU_MCLK,
    input   wire            i_EMU_CLK9M_PCEN,
    input   wire            i_EMU_CLK9M_NCEN,
    input   wire            i_EMU_CLK6M_PCEN,
    input   wire            i_EMU_CLK6M_NCEN,

    input   wire            i_EMU_INITRST_n,
    input   wire            i_EMU_SOFTRST_n,

    //reset control by the sound CPU
    input   wire            i_MAINCPU_RSTCTRL,
    output  wire            o_MAINCPU_RSTSTAT,
    input   wire            i_MAINCPU_SWAPIRQ,

    //bubble memory subsystem
    input   wire            i_BMC_MCLK, //48MHz
    input   wire            i_BMC_TEMPLO_n,
    output  wire            o_BMC_ACC,

    output  wire    [14:0]  o_GFX_ADDR,
    input   wire    [15:0]  i_GFX_DO,
    output  wire    [15:0]  o_GFX_DI, 
    output  wire            o_GFX_RnW,
    output  wire            o_GFX_UDS_n,
    output  wire            o_GFX_LDS_n,

    output  reg             o_VZCS_n,
    output  reg             o_VCS1_n,
    output  reg             o_VCS2_n,
    output  reg             o_CHACS_n,
    output  reg             o_OBJRAM_n,
    
    output  wire            o_HFLIP,
    output  wire            o_VFLIP,

    input   wire            i_ABS_1H_n,
    input   wire            i_ABS_2H,
    input   wire            i_ABS_32H,

    input   wire            i_VBLANK_n,
    input   wire            i_FRAMEPARITY,

    input   wire            i_BLK,

    input   wire    [10:0]  i_CD,

    //sound interrupts/DMA
    output  wire            o_SND_NMI,
    output  wire            o_SND_INT,
    output  wire    [7:0]   o_SND_CODE,
    output  wire            o_SND_DMA_BR,
    input   wire            i_SND_DMA_BG_n,
    output  wire    [14:1]  o_SND_DMA_ADDR,
    output  wire    [7:0]   o_SND_DMA_DO,
    input   wire    [7:0]   i_SND_DMA_DI,
    output  wire            o_SND_DMA_RnW,
    output  wire            o_SND_DMA_LDS_n,
    output  reg             o_SND_DMA_SNDRAM_CS,

    input   wire            i_TIMER_IRQ,

    input   wire    [7:0]   i_IN0, i_IN1, i_IN2, i_DIPSW1, i_DIPSW2, i_DIPSW3,

    output  wire    [4:0]   o_VIDEO_R,
    output  wire    [4:0]   o_VIDEO_G,
    output  wire    [4:0]   o_VIDEO_B,

    output  wire            o_BUBROM_BOOT_CS, o_BUBROM_PAGE_CS,
    output  wire    [17:0]  o_BUBROM_ADDR,
    input   wire    [15:0]  i_BUBROM_DATA,
    output  wire            o_BUBROM_RD,
    input   wire            i_BUBROM_DATA_RDY
);



///////////////////////////////////////////////////////////
//////  CLOCK AND RESET
////

//BMC region
wire            bmc_rst = ~i_EMU_INITRST_n | ~i_EMU_SOFTRST_n;
wire            bmc_maincpu_rstctrl_n;
wire            bclk = i_BMC_MCLK;
wire            clk4m_pcen;

//Main CPU region
wire            maincpu_pwrup = ~i_EMU_INITRST_n;
wire            maincpu_rst = ~i_EMU_INITRST_n | ~i_EMU_SOFTRST_n | i_MAINCPU_RSTCTRL | ~bmc_maincpu_rstctrl_n;
wire            mclk = i_EMU_MCLK;
wire            clk9m_pcen = i_EMU_CLK9M_PCEN;
wire            clk9m_ncen = i_EMU_CLK9M_NCEN;
wire            clk6m_pcen = i_EMU_CLK6M_PCEN;
wire            clk6m_ncen = i_EMU_CLK6M_NCEN;



assign  o_MAINCPU_RSTSTAT = maincpu_rst; //watchdog


///////////////////////////////////////////////////////////
//////  SYSTEM BUS
////

//dma synchronizer(72MHz/48MHz CDC)
wire            dma_br_n, dma_bg_n, dma_bgack_n;
reg     [1:0]   dma_br_n_sync, dma_bg_n_sync, dma_bgack_n_sync;
wire            dma_act = ~dma_bgack_n_sync[1];
always @(posedge mclk) begin //48MHz -> 72MHz
    dma_br_n_sync[0] <= dma_br_n;
    dma_br_n_sync[1] <= dma_br_n_sync[0];
    dma_bgack_n_sync[0] <= dma_bgack_n;
    dma_bgack_n_sync[1] <= dma_bgack_n_sync[0];
end
always @(posedge bclk) begin //72MHz -> 48MHz
    dma_bg_n_sync[0] <= dma_bg_n;
    dma_bg_n_sync[1] <= dma_bg_n_sync[0];
end

//Main 68k bus/control
wire    [15:0]  maincpu_do;
wire    [23:1]  maincpu_addr;
wire            maincpu_as_n, maincpu_r_nw, maincpu_lds_n, maincpu_uds_n;
wire    [2:0]   maincpu_fc;

//Bubble memory controller bus/control
wire    [15:0]  bmc_di, bmc_do;
wire            bmc_ale; //address latch enable(48MHz)
reg     [15:0]  bmc_al; //address latch LS272*2
reg     [2:0]   bmc_ale_sync;
always @(posedge mclk) begin
    bmc_ale_sync[0] <= bmc_ale;
    bmc_ale_sync[2:1] <= bmc_ale_sync[1:0];
    if(bmc_ale_sync[2:1] == 2'b01) bmc_al <= bmc_do;
end
wire    [7:1]   bmc_addr;
wire            bmc_as_n, bmc_r_nw, bmc_lds_n, bmc_uds_n;
reg     [1:0]   bmc_as_n_sync, bmc_r_nw_sync;
reg     [3:0]   bmc_lds_n_sync, bmc_uds_n_sync;
reg             bmc_lds_n_negedge, bmc_uds_n_negedge;
always @(posedge mclk) begin
    bmc_as_n_sync[0]  <= bmc_as_n;
    bmc_r_nw_sync[0]  <= bmc_r_nw;
    bmc_as_n_sync[1]  <= bmc_as_n_sync[0];
    bmc_r_nw_sync[1]  <= bmc_r_nw_sync[0];

    bmc_lds_n_sync[0] <= bmc_lds_n;
    bmc_uds_n_sync[0] <= bmc_uds_n;
    bmc_lds_n_sync[3:1] <= bmc_lds_n_sync[2:0];
    bmc_uds_n_sync[3:1] <= bmc_uds_n_sync[2:0];

    bmc_lds_n_negedge <= bmc_lds_n_sync[3] && !bmc_lds_n_sync[1];
    bmc_uds_n_negedge <= bmc_uds_n_sync[3] && !bmc_uds_n_sync[1];
end
wire    [2:0]   bmc_fc;

//Main bus/control, CPU+BMC multiplexed
reg     [15:0]  mainbus_di;
wire    [15:0]  mainbus_do    = dma_act ? bmc_do : maincpu_do; //no need to synchronize
wire    [23:1]  mainbus_addr  = dma_act ? {bmc_al, bmc_addr} : maincpu_addr; //no need to synchronize
wire            mainbus_as_n  = dma_act ? bmc_as_n_sync[1]   : maincpu_as_n;
wire            mainbus_r_nw  = dma_act ? bmc_r_nw_sync[1]   : maincpu_r_nw;
wire            mainbus_lds_n = dma_act ? ~bmc_lds_n_negedge : maincpu_lds_n;
wire            mainbus_uds_n = dma_act ? ~bmc_uds_n_negedge : maincpu_uds_n;
wire    [2:0]   mainbus_fc    = dma_act ? bmc_fc : maincpu_fc;

assign  bmc_di = dma_act ? mainbus_di : mainbus_do;

wire    [23:0]  debug_mainbus_addr = {mainbus_addr, mainbus_uds_n};

//send signals to the GFX board
assign  o_GFX_ADDR  = mainbus_addr[15:1];
assign  o_GFX_DI    = mainbus_do;
assign  o_GFX_RnW   = mainbus_r_nw;
assign  o_GFX_UDS_n = mainbus_uds_n;
assign  o_GFX_LDS_n = mainbus_lds_n;



///////////////////////////////////////////////////////////
//////  MAIN CPU
////

reg             maincpu_vpa_n;
reg             maincpu_dtack_n;
reg     [2:0]   maincpu_ipl;
fx68k u_maincpu (
    .clk                        (mclk                       ),
    .HALTn                      (1'b1                       ),
    .extReset                   (maincpu_rst                ),
    .pwrUp                      (maincpu_pwrup              ),
    .enPhi1                     (clk9m_pcen                 ),
    .enPhi2                     (clk9m_ncen                 ),

    .eRWn                       (maincpu_r_nw               ),
    .ASn                        (maincpu_as_n               ),
    .LDSn                       (maincpu_lds_n              ),
    .UDSn                       (maincpu_uds_n              ),
    .E                          (                           ),
    .VMAn                       (                           ),

    .iEdb                       (mainbus_di                 ), //data bus in
    .oEdb                       (maincpu_do                 ), //data bus out
    .eab                        (maincpu_addr               ), //23 downto 1

    .FC0                        (maincpu_fc[0]              ),
    .FC1                        (maincpu_fc[1]              ),
    .FC2                        (maincpu_fc[2]              ),
    
    .BGn                        (dma_bg_n                   ),
    .oRESETn                    (                           ),
    .oHALTEDn                   (                           ),

    .DTACKn                     (maincpu_dtack_n            ),
    .VPAn                       (maincpu_vpa_n              ),
    
    .BERRn                      (1'b1                       ),

    .BRn                        (dma_br_n_sync[1]           ),
    .BGACKn                     (dma_bgack_n_sync[1]        ),

    .IPL0n                      (maincpu_ipl[0]             ),
    .IPL1n                      (maincpu_ipl[1]             ),
    .IPL2n                      (maincpu_ipl[2]             )
);




///////////////////////////////////////////////////////////
//////  BUBBLE MEMORY
////

reg             bmc_cs;
wire            bmcclk_pcen; //generated by bubble memory emulator
wire            booten_n, bss_n, bsen_n, repen_n, swapen_n;
wire    [3:0]   bdo_n;

BubSys_bbd8 u_bbd8 (
    .i_EMUCLK                   (bclk                       ),
    .i_RST                      (bmc_rst                    ),

    .i_4BEN                     (1'b0                       ),
    .i_BDO_TSEL                 (1'b0                       ),

    .o_BMCCLK_PCEN              (bmcclk_pcen                ),

    .i_BOOTEN_n                 (booten_n                   ),
    .i_BSS_n                    (bss_n                      ),   
    .i_BSEN_n                   (bsen_n                     ),  
    .i_REPEN_n                  (repen_n                    ), 
    .i_SWAPEN_n                 (swapen_n                   ),

    .o_BDO_n                    (bdo_n                      ),
    .o_ACC                      (o_BMC_ACC                  ),

    .o_BUBROM_BOOT_CS           (o_BUBROM_BOOT_CS           ),
    .o_BUBROM_PAGE_CS           (o_BUBROM_PAGE_CS           ),
    .o_BUBROM_ADDR              (o_BUBROM_ADDR              ),
    .i_BUBROM_DATA              (i_BUBROM_DATA              ),
    .o_BUBROM_RD                (o_BUBROM_RD                ),
    .i_BUBROM_DATA_RDY          (i_BUBROM_DATA_RDY          )
);



///////////////////////////////////////////////////////////
//////  BUBBLE MEMORY CONTROLLER
////

wire            bmc_irq_n;

K005297 u_K005297 (
    .i_MCLK                     (bclk                       ),

    .i_CLK4M_PCEN_n             (~bmcclk_pcen & ~bmc_rst    ),
                         
    .i_MRST_n                   (~bmc_rst                   ),
                         
    .i_REGCS_n                  (~bmc_cs                    ),
    .i_DIN                      (bmc_di                     ), //write to BMC/BMC DMA read
    .i_AIN                      (mainbus_addr[3:1]          ), //write to BMC
    .i_R_nW                     (mainbus_r_nw               ),
    .i_UDS_n                    (mainbus_uds_n              ),
    .i_LDS_n                    (mainbus_lds_n              ),
    .i_AS_n                     (mainbus_as_n               ),
                         
    .o_DOUT                     (bmc_do                     ),
    .o_AOUT                     (bmc_addr                   ),
    .o_R_nW                     (bmc_r_nw                   ),
    .o_UDS_n                    (bmc_uds_n                  ),
    .o_LDS_n                    (bmc_lds_n                  ),
    .o_AS_n                     (bmc_as_n                   ),
    .o_ALE                      (bmc_ale                    ),
                         
    .o_BR_n                     (dma_br_n                   ),
    .i_BG_n                     (dma_bg_n_sync[1]           ),
    .o_BGACK_n                  (dma_bgack_n                ),
                         
    .o_CPURST_n                 (bmc_maincpu_rstctrl_n      ),
    .o_IRQ_n                    (bmc_irq_n                  ),
                         
    .o_FCOUT                    (bmc_fc                     ),
    .i_FCIN                     (mainbus_fc                 ),
                         
    .o_BDOUT_n                  (                           ),
    .i_BDIN_n                   ({bdo_n[1:0], 2'b11}        ),
    .o_BOOTEN_n                 (booten_n                   ),
    .o_BSS_n                    (bss_n                      ),
    .o_BSEN_n                   (bsen_n                     ),
    .o_REPEN_n                  (repen_n                    ),
    .o_SWAPEN_n                 (swapen_n                   ),
    .i_TEMPLO_n                 (1'b1                       ),
    .o_HEATEN_n                 (                           ),
    .i_4BEN_n                   (1'b1                       ),
                         
    .o_INT1_ACK_n               (                           ),
    .i_TST1                     (1'b1                       ),
    .i_TST2                     (1'b0                       ),
    .i_TST3                     (1'b1                       ),
    .i_TST4                     (1'b0                       ),
    .i_TST5                     (1'b1                       ),
                         
    .o_CTRL_DMAIO_OE_n          (                           ),
    .o_CTRL_DATA_OE_n           (                           )
);



///////////////////////////////////////////////////////////
//////  ADDRESS DECODER
////

reg             sharedram_cs, gamerom_rd, workram_cs, extram_cs;
reg             dmastat_cs, sndlatch_cs;
reg             palram_cs;
reg             syscfg_cs, dip_cs, btn_cs;
always @(*) begin
    sharedram_cs= 1'b0; //shared RAM between BMC/CPU
    gamerom_rd  = 1'b0;
    workram_cs  = 1'b0;
    bmc_cs      = 1'b0;
    extram_cs   = 1'b0;
    
    dmastat_cs  = 1'b0;
    sndlatch_cs = 1'b0;
    o_SND_DMA_SNDRAM_CS = 1'b0;

    syscfg_cs   = 1'b0;
    dip_cs      = 1'b0;
    btn_cs      = 1'b0;
    
    palram_cs   = 1'b0;
    o_VZCS_n    = 1'b1;
    o_VCS1_n    = 1'b1;
    o_VCS2_n    = 1'b1;
    o_CHACS_n   = 1'b1;
    o_OBJRAM_n  = 1'b1;

    maincpu_vpa_n = 1'b1;

    if(!mainbus_as_n && mainbus_addr[23:19] == 5'b00000) begin
        //1st LS138
        sharedram_cs=   mainbus_addr[18:16] == 3'b000;  //0x000000-0x000FFF, 6116*2
        workram_cs  =   mainbus_addr[18:16] == 3'b001;  //0x010000-0x01FFFF, 62256*2
        o_SND_DMA_SNDRAM_CS = mainbus_addr[18:16] == 3'b010;  //0x020000-0x027FFF, sound RAM address space
        o_CHACS_n   = ~(mainbus_addr[18:16] == 3'b011); //0x030000-0x03FFFF, 4416*8
        bmc_cs      =   mainbus_addr[18:16] == 3'b100;  //0x040000-0x04FFFF, bubble memory controller
        extram_cs   =   mainbus_addr[18:16] == 3'b111;  //0x070000-0x07FFFF, 6264*2(expansion RAM)
        
        //2nd LS138
        if(mainbus_addr[18:16] == 3'b101) begin
        o_VZCS_n    = ~(mainbus_addr[15:13] == 3'b000); //0x190000-0x190FFF, 16k*1, byte only
        o_VCS1_n    = ~(mainbus_addr[15:13] == 3'b001); //0x100000-0x101FFF, 32k*2, Toshiba 32kbit TC5533
        o_VCS2_n    = ~(mainbus_addr[15:13] == 3'b010); //0x102000-0x103FFF, 32k*1, byte only
        o_OBJRAM_n  = ~(mainbus_addr[15:13] == 3'b011); //0x180000-0x180FFF, 16k*1, byte only
        palram_cs   =   mainbus_addr[15:13] == 3'b101;  //0x090000-0x091FFF, 16k*2, byte only
        syscfg_cs   =   mainbus_addr[15:13] == 3'b111;
        end

        //3rd LS138
        if(mainbus_addr[18:13] == 6'b101_110 && !mainbus_lds_n) begin
        sndlatch_cs =   mainbus_addr[12:10] == 3'b000;
        dip_cs      =   mainbus_addr[12:10] == 3'b001;
        btn_cs      =   mainbus_addr[12:10] == 3'b011;
        dmastat_cs  =   mainbus_addr[12:10] == 3'b100;
        end
    end

    maincpu_vpa_n = mainbus_as_n | ~mainbus_addr[23];
end



///////////////////////////////////////////////////////////
//////  MAIN CPU DTACK
////

//work ram timings
reg             abs_32h_z;
wire            abs_32h_pe = i_ABS_32H & ~abs_32h_z;
always @(posedge mclk) if(clk6m_pcen) abs_32h_z <= i_ABS_32H;

reg     [2:0]   workram_rfsh_stat = 3'd0; //0 = idle, 1, 2, 3 = refresh, 4 = refresh pending
always @(posedge mclk) if(clk6m_pcen) begin
    if(workram_rfsh_stat == 3'd0) begin
        if(workram_cs) begin
            if(abs_32h_pe) workram_rfsh_stat <= 3'd4;
        end
        else begin
            if(abs_32h_pe) workram_rfsh_stat <= workram_rfsh_stat + 2'd1;
        end
    end
    else if(workram_rfsh_stat == 3'd4) begin
        if(!workram_cs) workram_rfsh_stat <= 3'd1;
    end
    else begin
        if(workram_rfsh_stat == 3'd3) workram_rfsh_stat <= 3'd0;
        else workram_rfsh_stat <= workram_rfsh_stat + 3'd1;
    end
end

//dtack generator
wire            dtack0_n = 1'b0;
reg             dtack1_n, dtack2_pre_n, dtack2_n;
wire            dtack3_n = ~((workram_rfsh_stat == 3'd0 | workram_rfsh_stat == 3'd4) & workram_cs);
always @(posedge mclk) begin
    if(maincpu_uds_n & maincpu_lds_n) begin
        dtack1_n <= 1'b1;
        dtack2_pre_n <= 1'b1;
        dtack2_n <= 1'b1;
    end
    else begin
        if(clk6m_pcen) begin
            if(!i_ABS_1H_n) dtack1_n <= 1'b0;
            dtack2_pre_n <= 1'b0;
        end

        if(clk6m_ncen) begin
            if({i_ABS_2H, ~i_ABS_1H_n} == 2'b00) dtack2_n <= dtack2_pre_n;
        end
    end
end

//DTACK selector
wire    [1:0]   dtack_sel;
assign  dtack_sel[1] = workram_cs | bmc_cs | o_SND_DMA_SNDRAM_CS | ~o_CHACS_n | ~o_VCS1_n | ~o_VCS2_n; // | exdtack <- not used, never used
assign  dtack_sel[0] = workram_cs | ~o_VZCS_n | ~o_OBJRAM_n;
always @(*) begin
    case(dtack_sel)
        2'd0: maincpu_dtack_n = dtack0_n; //bootloader ROM, program ROM(2Mbit), IO spaces
        2'd1: maincpu_dtack_n = dtack1_n; //scrollram, objram
        2'd2: maincpu_dtack_n = dtack2_n; //soundram, charram, vram1, vram2
        2'd3: maincpu_dtack_n = dtack3_n; //workram
    endcase
end



///////////////////////////////////////////////////////////
//////  MAIN CPU IRQ
////

wire            iack_vblank_n, iack_fparity_n, iack_timer_n;
reg             vblank_z, vblank_zz, fparity_z, fparity_zz, timer_z, timer_zz, bmc_irq_n_z, bmc_irq_n_zz;
reg             irq_vblank_n, irq_fparity_n, irq_timer_n;

always @(posedge mclk) begin
    vblank_z <= ~i_VBLANK_n;
    vblank_zz <= vblank_z;
    fparity_z <= i_FRAMEPARITY;
    fparity_zz <= fparity_z;
    timer_z <= i_TIMER_IRQ;
    timer_zz <= timer_z;
    bmc_irq_n_z <= bmc_irq_n;
    bmc_irq_n_zz <= bmc_irq_n_z;

    if(maincpu_rst) begin
        irq_vblank_n <= 1'b1;
        irq_fparity_n <= 1'b1;
        irq_timer_n <= 1'b1;
    end
    else begin
        if(!iack_vblank_n) irq_vblank_n <= 1'b1;
        else begin
            if({vblank_zz, vblank_z} == 2'b01) irq_vblank_n <= 1'b0;
        end
        if(!iack_fparity_n) irq_fparity_n <= 1'b1;
        else begin
            if({fparity_zz, fparity_z} == 2'b01) irq_fparity_n <= 1'b0;
        end
        if(!iack_timer_n) irq_timer_n <= 1'b1;
        else begin
            if({timer_zz, timer_z} == 2'b01) irq_timer_n <= 1'b0;
        end
    end
end

//Bubble System uses LS147 only, not make a delayed signal
always @(*) begin
    if(!bmc_irq_n_zz) maincpu_ipl = 3'b010;
    else begin
        if(!irq_timer_n) maincpu_ipl = 3'b011;
        else begin
            if(i_MAINCPU_SWAPIRQ ? !irq_fparity_n : !irq_vblank_n) maincpu_ipl = 3'b101;
            else begin
                if(i_MAINCPU_SWAPIRQ ? !irq_vblank_n : !irq_fparity_n) maincpu_ipl = 3'b110;
                else maincpu_ipl = 3'b111;
            end
        end
    end
end



///////////////////////////////////////////////////////////
//////  OUTLATCH(SYSTEM CONFIGURATION)
////

reg     [5:0]   syscfg[0:1];
always @(posedge mclk) begin
    if(maincpu_rst) begin
        syscfg[0] <= 6'h00;
        syscfg[1] <= 6'h00;
    end
    else begin if(syscfg_cs) begin
        if(!mainbus_uds_n && !mainbus_r_nw) begin
            case(mainbus_addr[3:1])
                //3'd0: syscfg[0][0] <= maincpu_do[8]; //coin counter 1
                //3'd1: syscfg[0][1] <= maincpu_do[8];
                3'd2: syscfg[0][2] <= mainbus_do[8]; //sound interrupt tick
                3'd3: syscfg[0][3] <= mainbus_do[8]; //dma_busrq
                3'd4: syscfg[0][4] <= mainbus_do[8]; //sound NMI
                3'd7: syscfg[0][5] <= mainbus_do[8]; //timerirq_ack_n
                default: ;
            endcase
        end
        if(!mainbus_lds_n && !mainbus_r_nw) begin
            case(mainbus_addr[3:1])
                3'd0: syscfg[1][0] <= mainbus_do[0]; //vblankirq_ack_n
                3'd1: syscfg[1][1] <= mainbus_do[0]; //frameirq_ack_n
                3'd2: syscfg[1][2] <= mainbus_do[0]; //gfx_hflip
                3'd3: syscfg[1][3] <= mainbus_do[0]; //gfx_vflip
                //3'd4: syscfg[1][4] <= maincpu_do[0]; //gfx_h288
                //3'd5: syscfg[1][5] <= maincpu_do[0]; //gfx_interlaced
                default: ;
            endcase
        end
    end end
end

assign  iack_vblank_n = syscfg[1][0];
assign  iack_fparity_n = syscfg[1][1];
assign  iack_timer_n = syscfg[0][5];
assign  o_HFLIP = syscfg[1][2];
assign  o_VFLIP = syscfg[1][3];
assign  o_SND_INT = syscfg[0][2];
assign  o_SND_NMI = syscfg[0][4];



///////////////////////////////////////////////////////////
//////  WORK RAM
////

wire    [15:0]  sharedram_q;
BubSys_SRAM #(.AW(11), .DW(8), .simhexfile()) u_sharedram_hi (
    .i_MCLK                     (i_EMU_MCLK                 ),
    .i_ADDR                     (mainbus_addr[11:1]         ),
    .i_DIN                      (mainbus_do[15:8]           ),
    .o_DOUT                     (sharedram_q[15:8]            ),
    .i_WR                       (sharedram_cs & ~mainbus_r_nw & ~mainbus_uds_n & mainbus_fc[2]),
    .i_RD                       (sharedram_cs &  mainbus_r_nw & ~mainbus_uds_n & mainbus_fc[2])
);
BubSys_SRAM #(.AW(11), .DW(8), .simhexfile()) u_sharedram_lo (
    .i_MCLK                     (i_EMU_MCLK                 ),
    .i_ADDR                     (mainbus_addr[11:1]         ),
    .i_DIN                      (mainbus_do[7:0]            ),
    .o_DOUT                     (sharedram_q[7:0]             ),
    .i_WR                       (sharedram_cs & ~mainbus_r_nw & ~mainbus_lds_n & mainbus_fc[2]),
    .i_RD                       (sharedram_cs &  mainbus_r_nw & ~mainbus_lds_n & mainbus_fc[2])
);

wire    [15:0]  workram_q;
BubSys_SRAM #(.AW(15), .DW(8), .simhexfile()) u_workram_hi (
    .i_MCLK                     (i_EMU_MCLK                 ),
    .i_ADDR                     (mainbus_addr[15:1]         ),
    .i_DIN                      (mainbus_do[15:8]           ),
    .o_DOUT                     (workram_q[15:8]            ),
    .i_WR                       (workram_cs & ~mainbus_r_nw & ~mainbus_uds_n),
    .i_RD                       (workram_cs &  mainbus_r_nw & ~mainbus_uds_n)
);
BubSys_SRAM #(.AW(15), .DW(8), .simhexfile()) u_workram_lo (
    .i_MCLK                     (i_EMU_MCLK                 ),
    .i_ADDR                     (mainbus_addr[15:1]         ),
    .i_DIN                      (mainbus_do[7:0]            ),
    .o_DOUT                     (workram_q[7:0]             ),
    .i_WR                       (workram_cs & ~mainbus_r_nw & ~mainbus_lds_n),
    .i_RD                       (workram_cs &  mainbus_r_nw & ~mainbus_lds_n)
);

//6264*2, gradius uses this
wire    [15:0]  extram_q;
BubSys_SRAM #(.AW(13), .DW(8), .simhexfile()) u_extram_hi (
    .i_MCLK                     (i_EMU_MCLK                 ),
    .i_ADDR                     (mainbus_addr[13:1]         ),
    .i_DIN                      (mainbus_do[15:8]           ),
    .o_DOUT                     (extram_q[15:8]            ),
    .i_WR                       (extram_cs & ~mainbus_r_nw & ~mainbus_uds_n),
    .i_RD                       (extram_cs &  mainbus_r_nw & ~mainbus_uds_n)
);
BubSys_SRAM #(.AW(13), .DW(8), .simhexfile()) u_extram_lo (
    .i_MCLK                     (i_EMU_MCLK                 ),
    .i_ADDR                     (mainbus_addr[13:1]         ),
    .i_DIN                      (mainbus_do[7:0]            ),
    .o_DOUT                     (extram_q[7:0]             ),
    .i_WR                       (extram_cs & ~mainbus_r_nw & ~mainbus_lds_n),
    .i_RD                       (extram_cs &  mainbus_r_nw & ~mainbus_lds_n)
);




///////////////////////////////////////////////////////////
//////  Palette RAM
////

//make palram wr signal
wire            palram_hi_cs = &{palram_cs, ~mainbus_uds_n};
wire            palram_lo_cs = &{palram_cs, ~mainbus_lds_n};

//make colorram address
wire    [10:0]  palram_addr = palram_cs ? mainbus_addr[11:1] : i_CD;

//declare COLORRAM
wire    [7:0]   palram_lo_q, palram_hi_q;
wire    [15:0]  palram_q = {palram_hi_q, palram_lo_q};

BubSys_SRAM #(.AW(11), .DW(8), .simhexfile()) u_palram_hi (
    .i_MCLK                     (i_EMU_MCLK                 ),
    .i_ADDR                     (palram_addr                ),
    .i_DIN                      (mainbus_do[15:8]           ),
    .o_DOUT                     (palram_hi_q                ),
    .i_WR                       (palram_hi_cs & ~mainbus_r_nw),
    .i_RD                       (1'b1                       )
);

BubSys_SRAM #(.AW(11), .DW(8), .simhexfile()) u_palram_lo (
    .i_MCLK                     (i_EMU_MCLK                 ),
    .i_ADDR                     (palram_addr                ),
    .i_DIN                      (mainbus_do[7:0]            ),
    .o_DOUT                     (palram_lo_q                ),
    .i_WR                       (palram_lo_cs & ~mainbus_r_nw),
    .i_RD                       (1'b1                       )
);

//rgb driver latch
reg     [14:0]  rgblatch;
always @(posedge mclk) if(clk6m_pcen) begin
    rgblatch <= {palram_hi_q[6:0], palram_lo_q};
end

assign  o_VIDEO_B = i_BLK ? rgblatch[14:10] : 5'd0;
assign  o_VIDEO_G = i_BLK ? rgblatch[9:5] : 5'd0;
assign  o_VIDEO_R = i_BLK ? rgblatch[4:0] : 5'd0;



///////////////////////////////////////////////////////////
////// SOUNDLATCH
////

reg     [7:0]   soundlatch = 8'h00;
assign  o_SND_CODE = soundlatch;
always @(posedge mclk) begin
    if(sndlatch_cs && !mainbus_r_nw && !mainbus_lds_n) soundlatch <= mainbus_do[7:0];
end



///////////////////////////////////////////////////////////
//////  DMA
////

assign  o_SND_DMA_BR = syscfg[0][3]; //sound cpu bus request
assign  o_SND_DMA_ADDR  = mainbus_addr[14:1];
assign  o_SND_DMA_DO    = mainbus_do[7:0];
assign  o_SND_DMA_RnW   = mainbus_r_nw;
assign  o_SND_DMA_LDS_n = mainbus_lds_n;




///////////////////////////////////////////////////////////
//////  READ BUS MUX
////

//assign o_BMC_ACC = mainbus_fc == 3'b110 && mainbus_addr == 23'h8000 /* synthesis keep */;

wire            gfx_cs = ~&{o_VZCS_n, o_VCS1_n, o_VCS2_n, o_CHACS_n, o_OBJRAM_n};

//CDC synchronizer
reg     [7:0]   snd_dma_di_sync[0:1];
reg     [1:0]   snd_dma_bg_n_sync;
always @(posedge mclk) begin
    snd_dma_di_sync[0] <= i_SND_DMA_DI;
    snd_dma_di_sync[1] <= snd_dma_di_sync[0];

    snd_dma_bg_n_sync[0] <= i_SND_DMA_BG_n;
    snd_dma_bg_n_sync[1] <= snd_dma_bg_n_sync[0];
end


always @(*) begin
    mainbus_di = 16'hFFFF;

         if(bmc_cs)       mainbus_di = bmc_do;
    else if(sharedram_cs) mainbus_di = sharedram_q;
    else if(workram_cs)   mainbus_di = workram_q;
    else if(extram_cs)    mainbus_di = extram_q;
    else if(palram_cs)    mainbus_di = palram_q;
    else if(gfx_cs)       mainbus_di = i_GFX_DO;
    else if(btn_cs) begin
        case(mainbus_addr[2:1])
            2'd0: mainbus_di = {8'hFF, i_IN0};
            2'd1: mainbus_di = {8'hFF, i_IN1};
            2'd2: mainbus_di = {8'hFF, i_IN2};
            2'd3: mainbus_di = {16'hFFFF};
        endcase
    end
    else if(dip_cs) begin
        case(mainbus_addr[2:1])
            2'd0: mainbus_di = {16'hFFFF};
            2'd1: mainbus_di = {8'hFF, i_DIPSW1};
            2'd2: mainbus_di = {8'hFF, i_DIPSW2};
            2'd3: mainbus_di = {8'hFF, i_DIPSW3};
        endcase
    end
    else if(o_SND_DMA_SNDRAM_CS) mainbus_di = {8'hFF, snd_dma_di_sync[1]};
    else if(dmastat_cs) mainbus_di = {{15{1'b1}}, snd_dma_bg_n_sync[1]};
end


endmodule
