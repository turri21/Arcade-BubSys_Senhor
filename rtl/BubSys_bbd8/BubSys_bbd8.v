module BubSys_bbd8 (
    //48MHz input clock
    input   wire            i_EMUCLK,

    //module enable
    input   wire            i_RST,

    //4bit width mode
    input   wire            i_4BEN,

    //BOUT timing select
    input   wire            i_BDO_TSEL,

    //4MHz output clock
    output  reg             o_BMCCLK_PCEN,

    //Bubble control signal inputs
    input   wire            i_BOOTEN_n,
    input   wire            i_BSS_n,
    input   wire            i_BSEN_n,
    input   wire            i_REPEN_n,
    input   wire            i_SWAPEN_n,

    output  wire    [3:0]   o_BDO_n,
    output  wire            o_ACC,

    //Data request
    output  wire            o_BUBROM_BOOT_CS, o_BUBROM_PAGE_CS,
    output  wire    [17:0]  o_BUBROM_ADDR,
    input   wire    [15:0]  i_BUBROM_DATA,
    output  wire            o_BUBROM_RD,
    input   wire            i_BUBROM_DATA_RDY
);

/*

    //////////////////////////////////////////////////////
    ////    INTERNAL ORGANIZATION OF FBM54DB
    //


        -1
    ----O---- DETECTOR 1
     \  |0 /   <------------ bubble output signal latched here(magnetic field -Y) by MB3908 sense amplifier; stretcher patterns exist here
      --O--   DETECTOR 0
        |                                                   ←     ←     ←     ←     ←         propagation direction
        |1    2         95    96    97    98    99    100   101               680   681
        O-----O   ...   O-----O-----O-----O-----O-----O-----O--             --O-----O
                              ↑     ↑     ↑     ↑     ↑     ↑                 ↑     ↑  
                            __^__ __^__ __^__ __^__ __^__ __^__             __^__ __^__  <-- "block" replicators; replicators for two bootloops
                         ↓  |   | |   | |   | |   | |   | |   |             |   | |   |       can be operated independantly from page replicators
                            |   | |   | |   | |   | |   | |   |             |   | |   | 
                         ↓  | L | | L | | L | | L | | L | | L |             | L | | L | 
                            | O | | O | | O | | O | | O | | O |             | O | | O | 
        ←                ↓  | O | | O | | O | | O | | O | | O |    .....    | O | | O |  <-- each loop can hold 2053 magnetic bubbles
     ↙                      | P | | P | | P | | P | | P | | P |             | P | | P | 
     ↓  ↑ EXTERNAL       ↓  |B 0| |B 1| |  0| |  1| |  2| |  3|             |582| |583| 
        | MAGNETIC          |   | |   | |   | |   | |   | |   |             |   | |   | 
          FIELD             ~   ~ ~   ~ ~   ~ ~   ~ ~   ~ ~   ~             ~   ~ ~O N~ 
                            |   | |   | |   | |   | |   | |   |             |   | |L E| 
                            |   | |   | |   | |   | |   | |   |             |   | |D W| 
                            ¯↓^↑¯ ¯↓^↑¯ ¯↓^↑¯ ¯↓^↑¯ ¯↓^↑¯ ¯↓^↑¯             ¯↓^↑¯ ¯↓^↑¯  <-- swap gate swaps an old bubble with a new bubble at the same time: -Y
                             / \   / \   / \   / \   / \   / \               / \   / \                    2     1
            O-- .... ---O---/-O-\-/-O-\-/-O-\-/-O-\-/-O-\-/-O-\-            /-O-\-/-O-\---O-----O   ...   O-----O
            |                 626   625   624   623   622   621               42    41    40    39              |
            ↓ discarded                                                                ↑              __________^_0________
                                                                                 -Y position          | G E N E R A T O R | <-- generates a bubble at +Y

    SEE JAPANESE PATENT:
    JPA 1992074376-000000 / 特許出願公開 平4-74376  ;contains replicator/swap gate diagram
    JPA 1989220199-000000 / 特許出願公開 平1-220199 ;explains bubble write procedure

    !!!! IMPORTANT NOTE !!!!
    Note that FBM54DB is organized with EVEN HALF and ODD HALF. The EVEN HALF
    has 1 even bootloop + 292 even minor loops and the ODD HALF has the same
    but they are odd numbered loops. Due to the physical width of minor loop,
    there is one position between a position and a position on read/write
    track. That is, there is one bubble for every two positions, like a diagram
    below:

            P   P   P   P   P   P   P   P
    ODD     O---*---O---*---O---*---O---*
            bubble  bubble  bubble  bubble

            P   P   P   P   P   P   P   P
    EVEN    *---O---*---O---*---O---*---O
                bubble  bubble  bubble  bubble

    Bubble moves one position every 10us, so in this case, 1 bit of data is
    transferred every 20us. Developers wanted to speed things up. So, they
    made another half that can be "interleaved". FBM54DB has two detectors
    and two MB3908 sense amplifiers. Each SA launches data 50kbps anyway 
    but its open collector(negative logic) outputs are interleaved outside,
    therefore the user can get 100kbps data. The BMC inverts negative logic
    data internally.

    I merged the EVEN HALF and the ODD HALF in the diagaram above, for my
    convenience. Therefore the diagram that represents the real organization
    will be like this:

    ODD HALF :

        -1
    ----O---- DETECTOR 1
     \  |0 /
      --O--   DETECTOR 0
        |                                                   ←     ←     ←     ←     ←         propagation direction
        |1    2         95    96    97    98    99    100   101               680   681
        O-----O   ...   O-----O-----O-----O-----O-----O-----O--             --O-----O
                                    ↑           ↑           ↑                       ↑  
                                  __^__       __^__       __^__                   __^__
                                  |   |       |   |       |   |                   |   |
                                  |   |       |   |       |   |                   |   | 
                                  | L |       | L |       | L |                   | L | 
                                  | O |       | O |       | O |                   | O | 
        ←                         | O |       | O |       | O |    .....          | O |
     ↙                            | P |       | P |       | P |                   | P | 
     ↓  ↑ EXTERNAL                |B 1|       |  1|       |  3|                   |583| 
        | MAGNETIC                |   |       |   |       |   |                   |   | 
          FIELD                   ~   ~       ~   ~       ~   ~                   ~O N~ 
                                  |   |       |   |       |   |                   |L E| 
                                  |   |       |   |       |   |                   |D W| 
                                  ¯↓^↑¯       ¯↓^↑¯       ¯↓^↑¯                   ¯↓^↑¯ 
                                   / \         / \         / \                     / \                    2     1
            O-- .... ---O-----O---/-O-\---O---/-O-\---O---/-O-\-            --O---/-O-\---O-----O   ...   O-----O
            |                 626   625   624   623   622   621               42    41    40    39              |
            ↓ discarded                                                                ↑              __________^_0________
                                                                                  -Y position         | G E N E R A T O R |

    EVEN HALF :

        -1
    ----O---- DETECTOR 1
     \  |0 /
      --O--   DETECTOR 0
        |                                                   ←     ←     ←     ←     ←         propagation direction
        |1    2         95    96    97    98    99    100   101               680   681
        O-----O   ...   O-----O-----O-----O-----O-----O-----O--             --O-----O
                              ↑           ↑           ↑                       ↑  
                            __^__       __^__       __^__                   __^__
                            |   |       |   |       |   |                   |   |
                            |   |       |   |       |   |                   |   |
                            | L |       | L |       | L |                   | L |
                            | O |       | O |       | O |                   | O |
        ←                   | O |       | O |       | O |          .....    | O |
     ↙                      | P |       | P |       | P |                   | P | 
     ↓  ↑ EXTERNAL          |B 0|       |  0|       |  2|                   |582|
        | MAGNETIC          |   |       |   |       |   |                   |   |
          FIELD             ~   ~       ~   ~       ~   ~                   ~   ~
                            |   |       |   |       |   |                   |   |
                            |   |       |   |       |   |                   |   |
                            ¯↓^↑¯       ¯↓^↑¯       ¯↓^↑¯                   ¯↓^↑¯
                             / \         / \         / \                     / \                          2     1
            O-- .... ---O---/-O-\---O---/-O-\---O---/-O-\---O---          --/-O-\---O-----O-----O   ...   O-----O
            |                 626   625   624   623   622   621               42    41    40    39              |
            ↓ discarded                                                                ↑             __________^_0________
                                                                                 -Y position         | G E N E R A T O R |


    //////////////////////////////////////////////////////
    ////    EXACT MINOR LOOP POSITION OF FBM54DB

    A good minor loop in FBM54DB can hold 2053 magnetic bubbles. This means
    that the total count of positions is 2053. Early bubble memories had put 
    a bubble every two positions to prevent bubble-bubble interaction, but
    FBM54DB doesn't require such action. In the diagram, it appears to be 
    the swap gate and the replicator exist in symmetrical positions, 
    but actually, it's not. 

                        1   0   2052
                ____  __O___O___O__
                |  |  |           |
                |  |  |           O 2051
                |  |  |           |
                |  |  |           O 2050
                |  |  |           |
                |  |  |           O 2049
                |  |  |           |
                |  ¯¯¯¯           O 2048
    same loops  ~~   partially   ~~~
    continue    ~~   magnified   ~~~
                |  ____           O 1541
                |  |  |           | 
          912+0 O  |  O           O 1540
                |  |  |    LOOP   | 
             +1 O  |  O    #584   O 1539    
                |  |  |           | 
             +2 O  |  O           O 1538
                |  |  |    +624   | 
                ¯¯¯¯  ¯¯O¯↓¯O¯↑¯O¯¯ 
                    +623 /     \ +625
                  42    /   41  \     40        39
                --O----↓----O----↑----O---------O
                    bubble    bubble   
                    goes OUT  goes IN 
                    on this   on this  
                    position  position 
                    at -Y     at -Y

    To increase loop capacity and density of each half, Fujitsu lengthened
    minor loops about twice. I assume they are shaped like "H".

    Replicator is on absolute position 0
    Swap gate is on absolute position 1536
*/

/*
    An MB3908 has two DFF with /Q OC output, and triggered on every positive
    edge of BOUTCLK from MB14506 timing generator. For example, the waveform
    below is showing a transfer of "6C 36 B1" 

                0us     0       0       0       0       0       0       0       0       0       0       0
    BOUTCLK     |¯|_____|¯|_____|¯|_____|¯|_____|¯|_____|¯|_____|¯|_____|¯|_____|¯|_____|¯|_____|¯|_____|¯|_____
    D1          ¯¯¯¯¯¯¯¯|_______________|¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯|_______|¯¯¯¯¯¯¯|_______________________|¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯
    D0          ________|¯¯¯¯¯¯¯|_______|¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯|_______________|¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯|_______|¯¯¯¯¯¯¯|_______
    bootloop          ^       ^       ^       ^       ^       ^       ^       ^       ^       ^       ^       ^
                   +7~8us
    user page     ^       ^       ^       ^       ^       ^       ^       ^       ^       ^       ^       ^     
               +0~1us

    Konami's BMC has different sampling timings for bootloop and user page, 
    respectively. I don't know how the unknown MCU inside the BMC 
    samples(or latches) data. I assume that MCU gets data from memory-mapped
    register once per bit, but there are several possibilities that the MCU
    gets several times, triggers flip-flops to sample data, or enables a kind
    of transparent latch for quite a long time.

    My friend Maki sent me a Bubble System PCB which has a deteriorated LS244.
    Total three LS244 are used as bubble memory control signal buffers, and 
    its propagation delay is often prolonged due to aging or the output 
    goes weak. Finally, it often became insufficient to drive a fairly long
    transmission line.

    Anyway, to prevent this missampling, bubble data should be launched 0-1us
    earlier when reading the bootloop, and 5-6us earlier when reading user
    pages.
*/



///////////////////////////////////////////////////////////
//////  CLOCK DIVIDER
////

reg     [3:0]   clk_div12;
always @(posedge i_EMUCLK) begin
    if(i_RST) clk_div12 <= 4'd0;
    else clk_div12 <= clk_div12 == 4'd11 ? 4'd0 : clk_div12 + 4'd1;

    o_BMCCLK_PCEN <= clk_div12 == 4'd4;
end



///////////////////////////////////////////////////////////
//////  MODULES
////

//TimingGenerator
wire    [2:0]   ACCTYPE;
wire    [12:0]  BOUTCYCLENUM;
wire    [11:0]  RELPAGE;
wire            nBINCLKEN;
wire            nBOUTCLKEN;

//SPILoader -> BubbleInterface
wire            nOUTBUFWRCLKEN;
wire    [14:0]  OUTBUFWRADDR;
wire            OUTBUFWRDATA;

assign o_ACC = ~i_BSEN_n;


BubSys_bbd8_TimingGenerator TimingGenerator_0 (
    .MCLK                       (i_EMUCLK                   ),

    .nEN                        (i_RST                      ),
    .TIMINGSEL                  (1'b0                       ),

    .CLKOUT                     (                           ),
    .nBSS                       (i_BSS_n                    ),
    .nBSEN                      (i_BSEN_n                   ),
    .nREPEN                     (i_REPEN_n                  ),
    .nBOOTEN                    (i_BOOTEN_n                 ),
    .nSWAPEN                    (i_SWAPEN_n                 ),

    .ACCTYPE                    (ACCTYPE                    ),
    .BOUTCYCLENUM               (BOUTCYCLENUM               ),
    .nBINCLKEN                  (nBINCLKEN                  ),
    .nBOUTCLKEN                 (nBOUTCLKEN                 ),

    .RELPAGE                    (RELPAGE                    )
);


BubSys_bbd8_BubbleBuffer BubbleBuffer_0 (
    .MCLK                       (i_EMUCLK                   ),

    .BITWIDTH4                  (1'b0                       ),

    .ACCTYPE                    (ACCTYPE                    ),
    .BOUTCYCLENUM               (BOUTCYCLENUM               ),
    .nBINCLKEN                  (nBINCLKEN                  ),
    .nBOUTCLKEN                 (nBOUTCLKEN                 ),

    .nOUTBUFWRCLKEN             (nOUTBUFWRCLKEN             ),
    .OUTBUFWRADDR               (OUTBUFWRADDR               ),
    .OUTBUFWRDATA               (OUTBUFWRDATA               ),

    .DOUT0                      (o_BDO_n[0]                 ),
    .DOUT1                      (o_BDO_n[1]                 ),
    .DOUT2                      (o_BDO_n[2]                 ),
    .DOUT3                      (o_BDO_n[3]                 )
);


/*
    Block RAM Buffer Address [DOUT1/DOUT0]
    1bit 0 + 13bit address + 1bit CS
    0000-1327 : bootloader data 1328*2 bits
    1328-1911 : 584*2 bad loop table
    1912-1926 : 14*2 or 15*2 bits of CRC(??) data, at least 28 bits
    1927-4038 : 11 = filler
    4039-4103 : X0 = 65 of ZEROs on EVEN channel (or possibly 64?)
    4104      : X1 = 1 of ONE on EVEN channel
    4105      : XX = DON'T CARE
    4106-7167 : 00 = empty space
    7168-7170 : 00 = 3 position shifted page data
    7171-7751 : 581bits remaining page data

    8191      : 00 = empty bubble propagation line
*/

reg     [3:0]   state = 4'd0;
reg     [7:0]   copy_data_length = 8'h00; //bootloader = 0xA6, page = 0x40
reg     [5:0]   timeout;
reg     [4:0]   data_select = 5'd0; //MSB is the buffer write strobe
reg     [15:0]  data_received;
reg     [13:0]  buffer_address = 14'd16383;
wire            buffer_wr = data_select[4];
wire            buffer_data = data_received[~data_select[3:0]];
reg     [17:0]  rom_addr = 18'd0;
reg             rom_rd = 1'b0;
reg             rom_boot_cs = 1'b0;
reg             rom_page_cs = 1'b0;

assign  o_BUBROM_BOOT_CS = rom_boot_cs;
assign  o_BUBROM_PAGE_CS = rom_page_cs;
assign  o_BUBROM_ADDR = rom_addr;
assign  o_BUBROM_RD = rom_rd;

assign  nOUTBUFWRCLKEN = ~buffer_wr;
assign  OUTBUFWRADDR = buffer_address;
assign  OUTBUFWRDATA = buffer_data;

always @(posedge i_EMUCLK) begin
    if(i_RST) state <= 4'd0;
    else begin
        if(state == 4'd0) begin
            buffer_address = 14'd16383;
            rom_boot_cs <= 1'b0;
            rom_page_cs <= 1'b0;
            if(ACCTYPE == 3'b110 || ACCTYPE == 3'b111) state <= 4'd1;
        end
        else if(state == 4'd1) begin
            if(ACCTYPE == 3'b110) begin 
                copy_data_length <= 8'hA6;
                buffer_address <= 14'd0;
                rom_boot_cs <= 1'b1;
                rom_addr <= 18'd0;
            end
            else if(ACCTYPE == 3'b111) begin 
                copy_data_length <= 8'h40;
                buffer_address <= 14'd14342;
                rom_page_cs <= 1'b1; 
                rom_addr <= {6'h0, RELPAGE} << 6;
            end
            
            rom_rd <= 1'b0;
            state <= 4'd2;
        end
        else if(state == 4'd2) begin rom_rd <= 1'b1; state <= 4'd3; end
        else if(state == 4'd3) begin timeout <= 5'd0; state <= 4'd4; end
        else if(state == 4'd4) begin 
            timeout <= timeout == 5'd31 ? 5'd31 : timeout + 5'd1;
            if(i_BUBROM_DATA_RDY || timeout == 5'd31) state <= 4'd5; 
        end
        else if(state == 4'd5) begin 
            rom_rd <= 1'b0;
            data_received <= i_BUBROM_DATA;
            data_select <= 5'd16; 
            state <= 4'd6;
        end
        else if(state == 4'd6) begin 
            data_select <= data_select == 5'd0 ? 5'd0 : data_select + 5'd1;
            buffer_address <= buffer_address + 14'd1;
            if(data_select == 5'd31) begin
                copy_data_length <= copy_data_length - 8'h1;
                rom_addr <= rom_addr + 18'd1;
                state <= 4'd7;
            end
        end
        else if(state == 4'd7) begin
            if(copy_data_length != 8'h00) state <= 4'd2;
            else begin
                if(ACCTYPE == 3'b000) state <= 4'd0;
            end
        end
    end
end





endmodule

module BubSys_bbd8_TimingGenerator
/*
    BubbleDrive8_emucore > modules > TimingGenerator.v

    Copyright (C) 2020-2021, Raki

    TimingGenerator provides all timing signals related to 
    the bubble memory side. This module uses 48MHz as master clock, 
    x4 of the original function timing generator(FTG) MB14506.
    Thereby BubbleDrive8 can manage all bubble logic without using 
    a PLL block. 


    * more details of signals below can be found on bubsys85.net *

    CLKOUT: 
        4MHz clock for the bubble memory controller: maybe an MCU uses this
    nBSS: Bubble Shift Start
        a pulse to notify a start of access cycle
    nBSEN: Bubble Shift ENable
        magnetic field rotates when this signal goes low
    nREPEN: REPlicator ENable
        FTG use this signal to replicate a bubble 
    nBOOTEN: BOOTloop ENable
        controller can access two bootloops by driving this signal low
    nSWAPEN: SWAP gate ENable
        FTG use this signal to write a page to a bubble memory

    nEN: module enable signal
    ACCTYPE: bubble access mode type
    BOUTCYCLENUM: bubble output cycle number: counts serial bits
    nBINCLKEN: emulator samples bubble data for page write when this goes low
    nBOUTCLKEN: emulator launches bubble data when this goes low
    nNOBUBBLE: emulator launches 1(no bubble)

    ABSPAGE: bubble memory's absolute position number


    * For my convenience, many comments are written in Korean *
*/

(
    //48MHz input clock
    input   wire            MCLK,   

    //4MHz output clock
    output  reg             CLKOUT = 1'b1,

    //Input control
    input   wire            nEN,
    input   wire            TIMINGSEL,

    //Bubble control signal inputs
    input   wire            nBSS,
    input   wire            nBSEN,
    input   wire            nREPEN,
    input   wire            nBOOTEN,
    input   wire            nSWAPEN,
    
    //Emulator signal outputs
    output  wire    [2:0]   ACCTYPE,
    output  reg     [12:0]  BOUTCYCLENUM,
    output  reg             nBINCLKEN = 1'b1,
    output  reg             nBOUTCLKEN = 1'b0,

    output  wire    [11:0]  RELPAGE
);

localparam      INITIAL_ABS_PAGE = 12'd1968; //0-2052
reg             __REF_nBOUTCLKEN_ORIG = 1'b0;
reg             __REF_CLK12M = 1'b0;


/*
    GLOBAL NET/REGS
*/
reg             nBSS_intl;
reg             nBSEN_intl;
reg             nREPEN_intl;
reg             nBOOTEN_intl;
reg             nSWAPEN_intl;



/*
    CLOCK DIVIDER
*/

/*
                                                         1 1 1 1 1 1 1 1 1 1 2 2 2 2
                                     0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 0 1 2 3 4 ...
                                                                             1   1 
                                     0   1   2   3   4   5   6   7   8   9   0   1   0
    48MHz             ¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|
    12MHz             _______|¯¯¯¯¯¯¯|_______|¯¯¯¯¯¯¯|_______|¯¯¯¯¯¯¯|_______|¯¯¯¯¯¯¯|_______|¯¯¯¯¯¯¯|_______|¯¯¯¯¯¯¯|_______|¯¯¯¯¯¯¯|
    4MHz              ¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯|_______________________|¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯|_______________________|¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯|

    BMC signals       ¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯|_______________________________________________|¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯
                                           |---------> sampled


    synchronization                                  |---|           |---|
    determine current access state                       |---|           |---|
    MCLK counting                                            |---------------|----------------->

    This block generates 12MHz ref clk, and 4MHz BMC clock. BMC always launches
    its signal at a "falling edge" of 4MHz. I don't know if it's synchronized
    to 4MHz or if they added a simple buffer delay. Anyway, all control signals
    arrives at a negative edge of the departing 4MHz.
    MB14506 starts to rotate magnetic field 23*12Mclk(about 83.33ns*23) later 
    just after nBSEN is sampled.
*/

reg     [4:0]   counter12 = 4'd0;


always @(posedge MCLK)
begin
    if(counter12 == 4'd1)
    begin
        __REF_CLK12M <= 1'b1;
        counter12 <= counter12 + 4'd1;
    end
    else if(counter12 == 4'd3)
    begin
        __REF_CLK12M <= 1'b0;
        counter12 <= counter12 + 4'd1;
    end
    else if(counter12 == 4'd5)
    begin
        __REF_CLK12M <= 1'b1;
        CLKOUT <= 1'b1;
        counter12 <= counter12 + 4'd1;
    end
    else if(counter12 == 4'd7)
    begin
        __REF_CLK12M <= 1'b0;
        counter12 <= counter12 + 4'd1;
    end
    else if(counter12 == 4'd9)
    begin
        __REF_CLK12M <= 1'b1;
        counter12 <= counter12 + 4'd1;
    end
    else if(counter12 == 4'd11)
    begin
        __REF_CLK12M <= 1'b0;
        CLKOUT <= 1'b0;
        counter12 <= 4'd0;
    end
    else
    begin
        counter12 <= counter12 + 4'd1;
    end
end



/*
    BUFFER CHAIN
*/
reg     [4:0]   step1 = 5'b11110;
reg     [4:0]   step2 = 5'b11110;
reg     [4:0]   step3 = 5'b11110;

always @(negedge MCLK)
begin
    step1[4] <= nEN | nSWAPEN;
    step1[3] <= nEN | nBSS;
    step1[2] <= nEN | nBSEN;
    step1[1] <= nEN | (nREPEN | ~nBOOTEN);
    step1[0] <= ~nEN & nBOOTEN;

    step2 <= step1;
    step3 <= step2;
end



/*
    SYNCHRONIZER
*/
always @(posedge MCLK)
begin
    if(counter12 == 4'd3 || counter12 == 4'd7 || counter12 == 4'd11)
    begin
        nSWAPEN_intl    <= step3[4];
        nBSS_intl       <= step3[3];
        nBSEN_intl      <= step3[2]; 
        nREPEN_intl     <= step3[1];
        nBOOTEN_intl    <= step3[0];
    end
end


/*
    ACCESS TYPE STATE MACHINE
*/

/*
    nREPEN            ¯¯¯¯¯¯¯¯¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯¯¯¯¯¯¯¯¯¯¯¯¯¯|_|¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯

    nBSS_intl         ¯¯¯¯¯|_|¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯|_|¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯|_|¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯
    nBOOTEN_intl      ______________________________________________|¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯
    nBSEN_intl        ¯¯¯¯¯¯¯¯|____________________________________|¯¯¯¯¯¯¯¯¯|__________________________|¯¯¯¯¯¯|__________________________|¯¯¯
    nREPEN_intl       ¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯|_|¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯
    nSWAPEN_intl      ¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯|_|¯¯¯¯¯¯¯¯
                              |----(bootloader load out enable)----|             |(page load out enable)|                          |(swap)|
    ----->TIME        A    |B |C                                   |A     |B |E  |D(HOLD)               |A  |B |E                  |F     |A
*/

//[magnetic field activation/data transfer/mode]
localparam RST = 3'b000;    //A
localparam STBY = 3'b001;   //B
localparam BOOT = 3'b110;   //C
localparam USER = 3'b111;   //D
localparam IDLE = 3'b100;   //E
localparam SWAP = 3'b101;   //F

reg     [2:0]   access_type = RST;
assign ACCTYPE = access_type;

always @(posedge MCLK) if(nEN) access_type = RST; else
begin
    case ({nBSS_intl, nBOOTEN_intl, nBSEN_intl, nREPEN_intl, nSWAPEN_intl})
        5'b10111: //최초 시작 후의 리셋 상태, 또는 부트로더 액세스가 끝난 후 아주 잠깐 발생
        begin
            if(access_type == STBY)
            begin
                access_type <= STBY;
            end
            else
            begin
                access_type <= RST;
            end
        end

        5'b00111: //부트로더 스탠바이
        begin
            if(access_type == RST)
            begin
                access_type <= STBY;
            end
            else
            begin
                access_type <= access_type;
            end
        end

        5'b10011: //부트로더 액세스 중
        begin
            if(access_type == STBY || access_type == BOOT || access_type == RST)
            begin
                access_type <= BOOT;
            end
            else
            begin
                access_type <= access_type;
            end
        end

        5'b11111: //유저 영역 리셋 상태
        begin
            if(access_type == STBY)
            begin
                access_type <= STBY;
            end
            else
            begin
                access_type <= RST;
            end
        end

        5'b01111: //페이지 스탠바이
        begin
            if(access_type == RST)
            begin
                access_type <= STBY;
            end
            else
            begin
                access_type <= access_type;
            end
        end

        5'b11011: //페이지 seek중, 또는 페이지 로딩 중(로딩 중에는 리플리케이션을 유지)
        begin
            if(access_type == STBY || access_type == RST)
            begin
                access_type <= IDLE;
            end
            else
            begin
                access_type <= access_type;
            end
        end

        5'b11001: //리플리케이션 펄스가 들어왔을 때
        begin
            if(access_type == IDLE)
            begin
                access_type <= USER;
            end
            else
            begin
                access_type <= access_type;
            end
        end

        5'b11010: //스왑 펄스가 들어왔을 때
        begin
            if(access_type == IDLE)
            begin
                access_type <= SWAP;
            end
            else
            begin
                access_type <= access_type;
            end
        end

        default:
        begin
            access_type <= access_type;
        end
    endcase
end



/*
    BUBBLE CYCLE STATE MACHINE
*/

/*
        +Y 568
-X 208           +X 448
        -Y 328
*/

//12MHz 1 bubble cycle = 120clks
//48MHz 1 bubble cycle = 480clks
//12MHz 1.5클럭이 씹힌 후에 계산, 만약 BMC신호가 38ns 이상 지연되면 1클럭 추가로 씹힘
//1.5클럭 씹힌 후 22클럭이 지난 직후 -X자기장 생성 시작

reg     [9:0]   MCLK_counter = 10'd0; //마스터 카운터는 세기 쉽게 1부터 시작 0아님!!

//master clock counters
always @(posedge MCLK) if(nEN) MCLK_counter = 10'd0; else 
begin
    //시작
    if(MCLK_counter == 10'd0)
    begin
        if(access_type[2] == 1'b0)
        begin
            MCLK_counter <= 10'd0;
        end
        else
        begin
            MCLK_counter <= MCLK_counter + 10'd1;
        end
    end

    //53번째 pos엣지에서 half disk -X방향 위치
    else if(MCLK_counter == 10'd208)
    begin
        if(access_type[2] == 1'b0) //-X방향에서 자기장회전이 끝났다면
        begin
            MCLK_counter <= 10'd0; //그대로 정지
        end
        else
        begin
            MCLK_counter <= MCLK_counter + 10'd1;
        end
    end

    //143번째 pos엣지에서 half disk +Y방향 위치
    else if(MCLK_counter == 10'd568) 
    begin
       MCLK_counter <= 10'd89; 
    end

    else
    begin
        MCLK_counter <= MCLK_counter + 10'd1;
    end
end


/*
    ABSOLUTE POSITION COUNTER
*/

reg     [11:0]  absolute_page_number = INITIAL_ABS_PAGE;
reg     [11:0]  relative_page_number = 12'd1127;
assign  RELPAGE = relative_page_number;

always @(posedge MCLK) begin
    if(nEN) begin
        absolute_page_number <= INITIAL_ABS_PAGE;
        relative_page_number <= 12'd1127;
    end
    else begin
        //143번째 pos엣지에서 half disk +Y방향 위치
        if(MCLK_counter == 10'd568) begin
            if(absolute_page_number < 12'd2052) absolute_page_number <= absolute_page_number + 12'd1;
            else absolute_page_number <= 12'd0;
            relative_page_number <= relative_page_number >= 12'd1531 ? relative_page_number - 12'd1531 : relative_page_number + 12'd522;
        end
    end
end



/*
    TIMING CONSTANTS
*/

/*
        +Y 568
-X 208           +X 448
        -Y 328
*/

/*
    An MB3908 has two DFF with /Q OC output, and triggered on every positive
    edge of BOUTCLK from MB14506 timing generator. For example, the waveform
    below is showing a transfer of "6C 36 B1" 

                0us     0       0       0       0       0       0       0       0       0       0       0
    BOUTCLK     |¯|_____|¯|_____|¯|_____|¯|_____|¯|_____|¯|_____|¯|_____|¯|_____|¯|_____|¯|_____|¯|_____|¯|_____
    D1          ¯¯¯¯¯¯¯¯|_______________|¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯|_______|¯¯¯¯¯¯¯|_______________________|¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯
    D0          ________|¯¯¯¯¯¯¯|_______|¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯|_______________|¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯|_______|¯¯¯¯¯¯¯|_______
    bootloop          ^       ^       ^       ^       ^       ^       ^       ^       ^       ^       ^       ^
                   +7~8us
    user page     ^       ^       ^       ^       ^       ^       ^       ^       ^       ^       ^       ^     
               +0~1us

    Konami's BMC has different sampling timings for bootloop and user page, 
    respectively. I don't know how the unknown MCU inside the BMC 
    samples(or latches) data. I assume that MCU gets data from memory-mapped
    register once per bit, but there are several possibilities that the MCU
    gets several times, triggers flip-flops to sample data, or enables a kind
    of transparent latch for quite a long time.

    My friend Maki sent me a Bubble System PCB which has a deteriorated LS244.
    Total three LS244 are used as bubble memory control signal buffers, and 
    its propagation delay is often prolonged due to aging or the output 
    goes weak. Finally, it often became insufficient to drive a fairly long
    transmission line.

    Anyway, to prevent this missampling, bubble data should be launched 0-1us
    earlier when reading the bootloop, and 5-6us earlier when reading user
    pages.
*/

reg     [9:0]   OUTBUFFER_CLKEN_TIMING = 10'd0;
reg     [9:0]   CYCLECOUNTER_TIMING = 10'd568;

always @(posedge MCLK)
begin
    if(nEN == 1'b1)
    begin
        OUTBUFFER_CLKEN_TIMING <= 10'd0;
        CYCLECOUNTER_TIMING <= 10'd568;
    end
    else
    begin
        if(TIMINGSEL == 1'b0)
        begin
            OUTBUFFER_CLKEN_TIMING <= 10'd328 - 10'd2; //오리지널 타이밍 - 20ns
            CYCLECOUNTER_TIMING <= 10'd568; //오리지널 타이밍
        end
        else
        begin
            if(access_type == BOOT)
            begin
                OUTBUFFER_CLKEN_TIMING <= 10'd328 - 10'd2; //오리지널 타이밍 - 20ns
                CYCLECOUNTER_TIMING <= 10'd568; //오리지널 타이밍
            end
            else if(access_type == USER)
            begin
                OUTBUFFER_CLKEN_TIMING <= 10'd568 - 10'd48; //오리지널 타이밍 - 6us
                CYCLECOUNTER_TIMING <= 10'd568 - 10'd60;  //오리지널보다 카운터를 2.5us 빨리 증가시킴
            end
            else
            begin
                OUTBUFFER_CLKEN_TIMING <= 10'd328 - 10'd2; //오리지널 타이밍 - 20ns
                CYCLECOUNTER_TIMING <= 10'd568; //오리지널 타이밍
            end
        end
    end
end



/*
    CYCLE COUNTER
*/

reg     [6:0]   bout_propagation_delay_counter = 7'd127; //98
reg     [9:0]   bout_page_cycle_counter = 10'd1023; //584
reg     [12:0]  bout_bootloop_cycle_counter = {1'b0, INITIAL_ABS_PAGE}; //4106

//assign BOUTCYCLENUM = bout_page_cycle_counter[14:2];

always @(posedge MCLK) if(nEN) begin
    BOUTCYCLENUM <= 13'd8191;
    bout_propagation_delay_counter <= 7'd127;
    bout_page_cycle_counter = 10'd1023;
    bout_bootloop_cycle_counter = {1'b0, INITIAL_ABS_PAGE};
end else
begin
    //리셋상태
    if(MCLK_counter == 10'd0)
    begin
        if(access_type == RST) //리셋 시
        begin
            BOUTCYCLENUM <= 13'd8191;

            bout_propagation_delay_counter <= 7'd127;

            bout_page_cycle_counter <= 10'd1023;

            bout_bootloop_cycle_counter <= bout_bootloop_cycle_counter;
        end
        else //그냥 다른 때는 그대로 유지
        begin
            BOUTCYCLENUM <= BOUTCYCLENUM;

            bout_propagation_delay_counter <= bout_propagation_delay_counter;

            bout_page_cycle_counter <= bout_page_cycle_counter;

            bout_bootloop_cycle_counter <= bout_bootloop_cycle_counter;
        end
    end

    //+Y에서 한번씩 체크
    else if(MCLK_counter == CYCLECOUNTER_TIMING) //magnetic field rotation activated
    begin
        if(access_type[1] == 1'b0) //IDLE 또는 SWAP: 실제로 데이터가 나가지 않음
        begin
            //empty propagation line
            BOUTCYCLENUM <= 13'd8191;

            //reset state
            bout_propagation_delay_counter <= 7'd127;

            //reset state
            bout_page_cycle_counter <= 10'd1023;

            //count up
            if(bout_bootloop_cycle_counter < 13'd4105)
            begin
                bout_bootloop_cycle_counter <= bout_bootloop_cycle_counter + 13'd1; //bootloop cycle counter는 계속 세기
            end
            else
            begin
                bout_bootloop_cycle_counter <= 13'd0;
            end
        end

        else //BOOT 또는 USER
        begin
            if(bout_propagation_delay_counter == 7'd127 || bout_propagation_delay_counter < 7'd97) //부트로더(초반 2비트가 씹힘)와 페이지 공히 첫 98싸이클 무효
            begin
                //empty propagation line
                BOUTCYCLENUM <= 13'd8191;

                //count up
                if(bout_propagation_delay_counter < 7'd127)
                begin
                    bout_propagation_delay_counter <= bout_propagation_delay_counter + 7'd1;
                end
                else
                begin
                    bout_propagation_delay_counter <= 7'd0;
                end

                //reset state
                bout_page_cycle_counter <= 10'd1023;

                //count up
                if(bout_bootloop_cycle_counter < 13'd4105)
                begin
                    bout_bootloop_cycle_counter <= bout_bootloop_cycle_counter + 13'd1; //bootloop cycle counter는 계속 세기
                end
                else
                begin
                    bout_bootloop_cycle_counter <= 13'd0;
                end
            end

            else //98사이클 지난 후부터
            begin
                if(access_type[0] == 1'b0) //BOOT 액세스,
                begin
                    //hold
                    bout_propagation_delay_counter <= bout_propagation_delay_counter;

                    //reset state
                    bout_page_cycle_counter <= 10'd1023;

                    //count up
                    if(bout_bootloop_cycle_counter < 13'd4105)
                    begin
                        bout_bootloop_cycle_counter <= bout_bootloop_cycle_counter + 13'd1; //bootloop cycle counter는 계속 세기
                        BOUTCYCLENUM <= bout_bootloop_cycle_counter + 13'd1;
                    end
                    else
                    begin
                        bout_bootloop_cycle_counter <= 13'd0;
                        BOUTCYCLENUM <= 13'd0;
                    end
                end
                else //USER 액세스
                begin
                    if(bout_page_cycle_counter == 10'd1023 || bout_page_cycle_counter < 10'd583) //페이지는 584-1 카운트
                    begin
                        //hold
                        bout_propagation_delay_counter <= bout_propagation_delay_counter;

                        //count up
                        if(bout_page_cycle_counter < 10'd583)
                        begin
                            bout_page_cycle_counter <= bout_page_cycle_counter + 10'd1;
                            BOUTCYCLENUM <= {3'b000, (bout_page_cycle_counter + 10'd1)};
                        end
                        else
                        begin
                            bout_page_cycle_counter <= 10'd0;
                            BOUTCYCLENUM <= 13'd0;
                        end

                        //count up
                        if(bout_bootloop_cycle_counter < 13'd4105)
                        begin
                            bout_bootloop_cycle_counter <= bout_bootloop_cycle_counter + 13'd1; //bootloop cycle counter는 계속 세기
                        end
                        else
                        begin
                            bout_bootloop_cycle_counter <= 13'd0;
                        end
                    end
                    else
                    begin
                        //hold
                        bout_propagation_delay_counter <= bout_propagation_delay_counter;

                        //hold
                        bout_page_cycle_counter <= bout_page_cycle_counter;

                        //count up
                        if(bout_bootloop_cycle_counter < 13'd4105)
                        begin
                            bout_bootloop_cycle_counter <= bout_bootloop_cycle_counter + 13'd1; //bootloop cycle counter는 계속 세기
                        end
                        else
                        begin
                            bout_bootloop_cycle_counter <= 13'd0;
                        end
                    end
                end
            end
        end
    end
end

//bubble output clock enable generator
always @(posedge MCLK)
begin
    //리셋상태
    if(MCLK_counter == 10'd0)
    begin
        nBOUTCLKEN <= 1'b0;
    end
    //버블 -Y에서 체크
    else if(MCLK_counter == OUTBUFFER_CLKEN_TIMING) //propagation delay보상을 위해 신호를 15ns정도 일찍 보내기; 오래된 기판의 경우 LS244가 느려짐
    begin
        nBOUTCLKEN <= 1'b0;
    end
    else
    begin
        nBOUTCLKEN <= 1'b1;
    end
end

//bubble input enable generator
always @(posedge MCLK)
begin
    //리셋상태
    if(MCLK_counter == 10'd0)
    begin
        nBINCLKEN <= 1'b1;
    end
    //버블 시작, +Y에서 한번씩 체크
    else if(MCLK_counter == 10'd88 || MCLK_counter == 10'd568) 
    begin
        nBINCLKEN <= 1'b0;   
    end
    else
    begin
        nBINCLKEN <= 1'b1;
    end
end

endmodule


module BubSys_bbd8_BubbleBuffer
/*
    BubbleDrive8_emucore > modules > BubbleBuffer.v

    Copyright (C) 2020-2022, Raki

    BubbleInterface acts as a buffer. This buffer has 8k*1bit space per
    one bubble memory. So, a 2Mbit module can take two of them, and a 4Mb,
    unreleased, undeveloped, never-seen one takes four.
    This buffer can hold both bootloader(2053*2) and user pages(584). SPI 
    Loader writes the bootloader and a requested page on here. One important 
    thing is that this buffer also has the synchronization pattern and empty
    propagation line.
    64 of LOGIC LOW + 1 of LOGIC HIGH + extra 1 of DON'T CARE synchronization
    pattern bits are loaded on the D0 buffer during the FPGA configuration 
    session. BUBBLE VALID CYCLE COUNTER automatically sweeps the address bus 
    of the buffer, so entire bootloop read can be accomplished without 
    unnatural behavior or exceptional asynchronous code that forces to make
    the pattern.
    Timing Generator makes Clock Enable pulses(active low) to launch a bubble
    bit.

    * For my convenience, many comments are written in Korean *
*/

(
    //48MHz input clock
    input   wire            MCLK,

    //4bit width mode
    input   wire            BITWIDTH4,

    //Emulator signal outputs
    input   wire    [2:0]   ACCTYPE,        //access type
    input   wire    [12:0]  BOUTCYCLENUM,   //bubble output cycle number
    input   wire            nBINCLKEN,
    input   wire            nBOUTCLKEN,     //bubble output asynchronous control ticks

    //Bubble out buffer interface
    input   wire            nOUTBUFWRCLKEN,    //bubble outbuffer write clk
    input   wire    [14:0]  OUTBUFWRADDR,      //bubble outbuffer write address
    input   wire            OUTBUFWRDATA,      //bubble outbuffer write data

    //Bubble data out
    output  wire            DOUT0,
    output  wire            DOUT1,
    output  wire            DOUT2,
    output  wire            DOUT3
);



/*
    OUTBUFFER READ ADDRESS DECODER
*/

/*
    Block RAM Buffer Address [DOUT1/DOUT0]
    1bit 0 + 13bit address + 1bit CS
    0000-1327 : bootloader data 1328*2 bits
    1328-1911 : 584*2 bad loop table
    1912-1926 : 14*2 or 15*2 bits of CRC(??) data, at least 28 bits
    1927-4038 : 11 = filler
    4039-4103 : X0 = 65 of ZEROs on EVEN channel (or possibly 64?)
    4104      : X1 = 1 of ONE on EVEN channel
    4105      : XX = DON'T CARE
    4106-7167 : 00 = empty space
    7168-7170 : 00 = 3 position shifted page data
    7171-7751 : 581bits remaining page data

    8191      : 00 = empty bubble propagation line
*/

localparam BOOT = 3'b110;   //C
localparam USER = 3'b111;   //D

reg     [12:0]  outbuffer_read_address = 13'b1_1111_1111_1111;

always @(*)
begin
    case (ACCTYPE)
        BOOT:
        begin
            outbuffer_read_address <= BOUTCYCLENUM;
        end
        USER:
        begin
            outbuffer_read_address <= {3'b111, BOUTCYCLENUM[9:0]};
        end
        default:
        begin
            outbuffer_read_address <= 13'b1_1111_1111_1111;
        end
    endcase
end



/*
    OUTBUFFER WRITE ADDRESS DECODER
*/

wire    [3:0]   outbuffer_write_enable;
reg     [3:0]   outbuffer_we_decoder = 4'b1111; //D3 D2 DOUT1 DOUT0
assign          outbuffer_write_enable = outbuffer_we_decoder;
reg     [12:0]  outbuffer_write_address;

always @(*)
begin
    case(BITWIDTH4)
        1'b0: //2BITMODE
        begin
            case(OUTBUFWRADDR[0])
                1'b0:
                begin
                    outbuffer_write_address <= OUTBUFWRADDR[13:1];
                    outbuffer_we_decoder <= 4'b1101;
                end
                1'b1:
                begin
                    outbuffer_write_address <= OUTBUFWRADDR[13:1];
                    outbuffer_we_decoder <= 4'b1110;
                end
            endcase
        end
        1'b1: //4BITMODE: no game released
        begin
            case(OUTBUFWRADDR[1:0])
                2'b00:
                begin
                    outbuffer_write_address <= OUTBUFWRADDR[14:2];
                    outbuffer_we_decoder <= 4'b0111;
                end
                2'b01:
                begin
                    outbuffer_write_address <= OUTBUFWRADDR[14:2];
                    outbuffer_we_decoder <= 4'b1011;
                end
                2'b10:
                begin
                    outbuffer_write_address <= OUTBUFWRADDR[14:2];
                    outbuffer_we_decoder <= 4'b1101;
                end
                2'b11:
                begin
                    outbuffer_write_address <= OUTBUFWRADDR[14:2];
                    outbuffer_we_decoder <= 4'b1110;
                end
            endcase
        end
    endcase
end



/*
    OUTBUFFER
*/

//DOUT0
reg             D0_outbuffer[8191:0];
reg             D0_outbuffer_read_data;
assign          DOUT0 = ~D0_outbuffer_read_data;

always @(posedge MCLK)
begin
    if(nOUTBUFWRCLKEN == 1'b0)
    begin
       if (outbuffer_write_enable[0] == 1'b0)
       begin
           D0_outbuffer[outbuffer_write_address] <= OUTBUFWRDATA;
       end
    end
end

always @(posedge MCLK) //read 
begin
    if(nBOUTCLKEN == 1'b0)
    begin
        D0_outbuffer_read_data <= D0_outbuffer[outbuffer_read_address];
    end
end

initial
begin
    $readmemb("./rtl/BubSys_bbd8/D0_outbuffer.txt", D0_outbuffer);
end


//DOUT1
reg             D1_outbuffer[8191:0];
reg             D1_outbuffer_read_data;
assign          DOUT1 = ~D1_outbuffer_read_data;

always @(posedge MCLK)
begin
    if(nOUTBUFWRCLKEN == 1'b0)
    begin
       if (outbuffer_write_enable[1] == 1'b0)
       begin
           D1_outbuffer[outbuffer_write_address] <= OUTBUFWRDATA;
       end
    end
end

always @(posedge MCLK) //read 
begin   
    if(nBOUTCLKEN == 1'b0)
    begin
        D1_outbuffer_read_data <= D1_outbuffer[outbuffer_read_address];
    end
end

initial
begin
    $readmemb("./rtl/BubSys_bbd8/D1_outbuffer.txt", D1_outbuffer);
end


//DOUT2
reg             D2_outbuffer[8191:0];
reg             D2_outbuffer_read_data;
assign          DOUT2 = (BITWIDTH4 == 1'b0) ? ~1'b1 : ~D2_outbuffer_read_data;

always @(posedge MCLK)
begin
    if(nOUTBUFWRCLKEN == 1'b0)
    begin
       if (outbuffer_write_enable[2] == 1'b0)
       begin
           D2_outbuffer[outbuffer_write_address] <= OUTBUFWRDATA;
       end
    end
end

always @(posedge MCLK) //read 
begin
    if(nBOUTCLKEN == 1'b0)
    begin
        D2_outbuffer_read_data <= D2_outbuffer[outbuffer_read_address];
    end
end

initial
begin
    $readmemb("./rtl/BubSys_bbd8/D2_outbuffer.txt", D2_outbuffer);
end


//DOUT3
reg             D3_outbuffer[8191:0];
reg             D3_outbuffer_read_data;
assign          DOUT3 = (BITWIDTH4 == 1'b0) ? ~1'b1 : ~D3_outbuffer_read_data;

always @(posedge MCLK)
begin
    if(nOUTBUFWRCLKEN == 1'b0)
    begin
       if (outbuffer_write_enable[3] == 1'b0)
       begin
           D3_outbuffer[outbuffer_write_address] <= OUTBUFWRDATA;
       end
    end
end

always @(posedge MCLK) //read 
begin
    if(nBOUTCLKEN == 1'b0)
    begin
        D3_outbuffer_read_data <= D3_outbuffer[outbuffer_read_address];
    end
end

initial
begin
    $readmemb("./rtl/BubSys_bbd8/D3_outbuffer.txt", D3_outbuffer);
end

endmodule