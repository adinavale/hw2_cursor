`include "vid5regs.sv"
`include "FIFO.sv"

typedef enum reg [2:0] {
    addr_phase,
    data_phase,
    dummy_phase,
    rgbfetch_phase,
    pushfifo_phase,
    cursorfetch_phase
} REGSTATE;

typedef enum reg [1:0] {
    fetch_phase, 
    repetition_phase, 
    extra_phase
} RGBDISPLAY;

typedef struct packed {
	reg [12:0] Vsize;
	reg [12:0] Vend;
} V1;

typedef struct packed {
	reg [12:0] VsyncStart;
	reg [12:0] VsyncEnd;
} V2;

typedef struct packed {
	reg [31:0] Base;
} Base;

typedef struct packed {
	reg [31:0] LineInc;
} LineInc;

typedef struct packed {
	reg [31:0] Cursor;
} Cursor;

module vid5b (input reg clk,
    input reg reset,
    input reg selin,
    input reg[2:0] cmdin,
    input reg[1:0] lenin,
    input reg[31:0] addrdatain,
    output reg[1:0] reqout,
    output reg[1:0] lenout,
    output reg[31:0] addrdataout,
    output reg[2:0] cmdout,
    output reg[3:0] reqtar,
    output reg ackin,
    output reg enable,  //possibly controller enable CR reg
    output reg hsync,
    output reg hblank,
    output reg vsync,
    output reg vblank,
    output reg[7:0] R, G, B
);
    reg [7:0] reg_addr, reg_addr_d;
    reg first_data; //later try to rearrange logic
    reg [3:0] burstcnt, burstcnt_d; 
    reg [5:0] pixelcnt, pixelcnt_d;  //since we cant tell how big pclk is pclk is 6 bits wide
    reg [13:0] hcnt, hcnt_d;  //since we dont know how long the display is(hsize + hblank) keeping it 14bits, hblank and hsync are both 13 bits
    reg [13:0] vcnt, vcnt_d;
    reg [31:0] rgb, rgb_d;
    reg hsync_d, hblank_d, vsync_d, vblank_d;
    reg [7:0] R_d, G_d, B_d;

    reg [13:0] fetchcnt, fetchcnt_d; //to get as many vsize rgb values
    reg [13:0] linecnt, linecnt_d; //to get as many hsize rgb values
    reg [7:0] cursor_buffer, cursor_buffer_d; //buffer addr for cursor - assuming it wont go beyond 8bit
    reg cursor_fetch, cursor_fetch_d;
    reg [6:0] firstcur_data, firstcur_data_d; //data of upto 64 rows hence 6 bits
    reg [4:0] burst1cnt, burst1cnt_d; 

    reg [63:0] cursor_data;

    //FIFO registers
    reg rd_en, wr_en; 
    reg [31:0] data_in, data_out;
    reg empty, full, half_full;
    wire fifo_rd_en, fifo_wr_en, fifo_empty, fifo_full, fifo_half_full;
    wire [31:0] fifo_data_in, fifo_data_out;
    //FIFO registers end
    
    FIFO #(.FIFO_depth(32), .FIFO_width(32), .addr_width (5)) fifo(.clk(clk), .rst(reset), .rd_en(fifo_rd_en), .wr_en(fifo_wr_en), .data_in(fifo_data_in), .empty(fifo_empty), .full(fifo_full), .half_full(fifo_half_full), .data_out(fifo_data_out));
    
    CR0 cr0, cr0_d;
    CUR0 cur0, cur0_d;
    CUR1 cur1, cur1_d;
    CURFG curfg, curfg_d;
    CURBG curbg, curbg_d;
    H1 h1, h1_d;
    H2 h2, h2_d;
    V1 v1, v1_d;
    V2 v2, v2_d;
    Base base, base_d;
    LineInc lineinc, lineinc_d;
    Cursor cursor, cursor_d;
    REGSTATE regwrite_state_ns, regwrite_state_cs;
    RGBDISPLAY rgbdisplay_ns, rgbdisplay_cs;

    assign fifo_rd_en = rd_en;
    assign fifo_wr_en = wr_en;
    assign fifo_data_in = data_in;

    always @ (*) begin
        //For FIFO
        empty = fifo_empty;
        full = fifo_full;
        half_full = fifo_half_full;
        data_out = fifo_data_out;
        data_in = 0;
        addrdataout = 0;
        lenout = 0;
        burst1cnt_d = burst1cnt;
        fetchcnt_d = fetchcnt;
        linecnt_d = linecnt;
        cursor_buffer_d = cursor_buffer;
        cursor_fetch_d = cursor_fetch;
        firstcur_data_d = firstcur_data;
        burstcnt_d = burstcnt;
        reg_addr_d = reg_addr;
        hcnt_d = hcnt;
        vcnt_d = vcnt;
        regwrite_state_ns = regwrite_state_cs;
        rgbdisplay_ns = rgbdisplay_cs;
        pixelcnt_d = pixelcnt;
        rgb_d = rgb;
        hsync_d = hsync;
        hblank_d = hblank;
        vsync_d = vsync;
        vblank_d = vblank;
        R_d = R;
        G_d = G;
        B_d = B;

        h1_d = h1;
        h2_d = h2;
        v1_d = v1;
        v2_d = v2;
        cr0_d = cr0;
        cur0_d = cur0;
        cur1_d = cur1;
        curfg_d = curfg;
        curbg_d = curbg;
        base_d = base;
        lineinc_d = lineinc;
        cursor_d = cursor;

        reqout = 0;
        cmdout = 0;
        reqtar = 0;

        //FSM - initial register value fetch 
        wr_en = 0;
        case(regwrite_state_cs)
            addr_phase: begin
                if(selin == 1'b1) begin
                    if(cmdin == 4) begin
                        vblank_d = 1;
                        first_data = 1'b1;
                        cmdout = 5; //Getting the next set of registers and setting priority
                        reqout = 3;
                        reg_addr_d = addrdatain[7:0]; //saving the current address the tb is sending
                        regwrite_state_ns = data_phase;
                    end
                    else begin
                        regwrite_state_ns = addr_phase;
                        vblank_d = 0;
                    end
                end
                else if(vsync) begin
                    regwrite_state_ns = dummy_phase;
                end
                else begin
                    regwrite_state_ns = addr_phase;
                end
                
            end
            data_phase: begin
                cmdout = 5;
                reqout = 3;
                if(lenin == 0) 
                    regwrite_state_ns = dummy_phase;
                else begin  //this needs further revision
                    regwrite_state_ns = addr_phase;
                    burstcnt_d = burstcnt + 1;
                    if(burstcnt == (2**(lenout + 1))) begin
                        burstcnt_d = 0;
                        regwrite_state_ns = dummy_phase;
                    end
                end
                case(reg_addr)
                    8'h00: cr0_d = addrdatain;
                    8'h08: cur0_d = addrdatain; //not required for now
                    8'h10: cur1_d = addrdatain; //not required for now
                    8'h18: curfg_d = addrdatain; //not required for now
                    8'h20: curbg_d = addrdatain; //not required for now
                    8'h28: h1_d = addrdatain;
                    8'h30: h2_d = addrdatain;
                    8'h38: v1_d = addrdatain;
                    8'h40: v2_d = addrdatain;
                    8'h48: base_d = addrdatain;
                    8'h50: lineinc_d = addrdatain;
                    8'h60: cursor_d = addrdatain;
                    default: regwrite_state_ns = dummy_phase;
                endcase
            end
            dummy_phase: begin
                cmdout = 5;
                reqout = 3;
                regwrite_state_ns = addr_phase; //nothing something like end packet
                if(cr0.Enable == 1) begin
                    regwrite_state_ns = rgbfetch_phase;
                    fetchcnt_d = 0;
                    linecnt_d = 0;
                    cursor_buffer_d = 0;
                    cursor_fetch_d = 0;
                end
            end
            rgbfetch_phase: begin
                burst1cnt_d = 0;

                if(hblank && ((vcnt + 1 >= cur0.Curx) && (vcnt + 1 <= cur0.Cury)) && cr0.CursorEnable && ~cursor_fetch) begin
                    lenout = 1;   //coz we need 64 bit value
                    firstcur_data_d = 0;
                    addrdataout = cursor.Cursor + cursor_buffer;
                    regwrite_state_ns = cursorfetch_phase;
                    reqout = 3;
                    cmdout = 3'b010;
                end
                else begin
                    if(h1.Hsize >= linecnt + 16)
                        lenout = 3;
                    else if (h1.Hsize >= linecnt + 8)
                        lenout = 2;
                    else if (h1.Hsize >= linecnt + 4)
                        lenout = 1;
                    else 
                        lenout = 0;
                    
                    addrdataout = base + (lineinc * fetchcnt) + (linecnt * 4); //lineinc is the address along the hsize
                    if(~half_full) begin
                        regwrite_state_ns = pushfifo_phase;
                        cmdout = 3'b010;
                        reqout = 3;
                        if(fetchcnt > v1.Vsize) begin
                            regwrite_state_ns = addr_phase;  //wait for the next register updates process
                            reqout = 0;
                            cmdout = 0;
                            lenout = 0;
                        end
                    end
                    else begin
                        regwrite_state_ns = rgbfetch_phase;
                    end
                end
            end
            pushfifo_phase: begin
                if(h1.Hsize >= linecnt + 16)   //recreating the same logic---have to change this approach later
                    lenout = 3;
                else if (h1.Hsize >= linecnt + 8)
                    lenout = 2;
                else if (h1.Hsize >= linecnt + 4)
                    lenout = 1;
                else 
                    lenout = 0;
                    
                cmdout = 3'b010;
                regwrite_state_ns = pushfifo_phase;
                case(cmdin)
                    3'b000: begin
                        if((burst1cnt == 2**(lenout + 1) && lenout > 0) || (lenout == 0 && burst1cnt == 1)) begin  //lenout 2 means 8 burst, 3 means 16 burst
                            linecnt_d = linecnt + burst1cnt;
                            regwrite_state_ns = rgbfetch_phase;
                            if(linecnt_d > h1.Hsize) begin
                                fetchcnt_d = fetchcnt + 1;
                                linecnt_d = 0;
                            end
                        end
                    end
                    3'b011: begin
                        wr_en = 1;
                        data_in = addrdatain;
                        burst1cnt_d = burst1cnt + 1;
                    end
                    3'b001: begin
                        wr_en = 1;
                        data_in = addrdatain;
                        burst1cnt_d = burst1cnt + 1;
                    end
                endcase
            end
            cursorfetch_phase: begin
                lenout = 1;
                cmdout = 3'b010;
                case(cmdin)
                    3'b000: begin
                        if(firstcur_data == 2**(lenout + 1) && lenout > 0) begin
                            cursor_fetch_d = 1;
                            regwrite_state_ns = rgbfetch_phase;
                        end
                    end
                    2'b011: begin
                        cursor_data[63:32] = addrdatain;
                        firstcur_data_d = firstcur_data + 1;
                    end
                    2'b001: begin
                        if(firstcur_data == 1) begin
                            cursor_data[31:0] = addrdatain;
                        end    
                        firstcur_data_d = firstcur_data + 1;
                    end
                endcase
            end
        endcase 

        //FSM - for sending the RGB values out
        rd_en = 0;
        case(rgbdisplay_cs)
            fetch_phase: begin
                if(~empty) begin
                    rgbdisplay_ns = repetition_phase;
                    rd_en = 1; //fetching data from fifo
                    pixelcnt_d = 0;
                    rgb_d = data_out;
                end
                else
                    rgbdisplay_ns = fetch_phase;
            end
            repetition_phase: begin
                if(pixelcnt < (cr0.Pclk - 1)) begin  //every value has to wait pclk times
                    pixelcnt_d = pixelcnt + 1;
                    R_d = rgb[23:16];
                    G_d = rgb[15:8];
                    B_d = rgb[7:0];
                                        
                    if(hcnt > h1.Hsize) begin  //horizontal count
                        hblank_d = 1;
                        R_d = 8'b0;
                        G_d = 8'b0;
                        B_d = 8'b0;
                    end
                    else 
                        hblank_d = 0;
                    if((hcnt > h2.HsyncStart) && (hcnt <= h2.HsyncEnd))
                        hsync_d = 1;
                    else 
                        hsync_d = 0;
                    
                    if(((vcnt > v1.Vsize) && (~((vcnt == v1.Vend) && (hcnt > h2.HsyncStart)))) || ((vcnt == v1.Vsize) && (hcnt > h2.HsyncStart))) begin  //vertical count
                        vblank_d = 1;
                        R_d = 8'b0;
                        G_d = 8'b0;
                        B_d = 8'b0;
                    end
                    else 
                        vblank_d = 0;
                    if(((vcnt > v2.VsyncStart) && (vcnt <= v2.VsyncEnd) && (~((vcnt == v2.VsyncEnd) && (hcnt > h2.HsyncStart)))) || ((vcnt == v2.VsyncStart) && (hcnt > h2.HsyncStart)))
                        vsync_d = 1;
                    else
                        vsync_d = 0;

                end
                else begin
                    hcnt_d = hcnt + 1;
                    // if(hcnt_d > h1.Hend)
                    //     vcnt_d = vcnt + 1;
                    
                    if(hcnt + 1 > h1.Hend) begin
                        hcnt_d = 0;
                        vcnt_d = vcnt + 1;
                        cursor_fetch_d = 0;  //enabling the fetching operation of cursor
                        if(vcnt + 1 > v1.Vend) 
                            vcnt_d = 0;
                    end
                    
                    if(((hcnt_d > h1.Hsize) && (hcnt_d <= h1.Hend)) || ((vcnt_d > v1.Vsize) && (vcnt_d <= v1.Vend)))
                        rgbdisplay_ns = extra_phase;
                    else
                        rgbdisplay_ns = fetch_phase;
                end
            end
            // update_phase: begin
            //     // if(hcnt > h1.Hend) begin 
            //     //     hcnt_d = 0;
            //     // end
            //     // if(vcnt > v1.Vend) begin
            //     //     vcnt_d = 0;
            //     // end

                
            // end
            extra_phase: begin
                rgbdisplay_ns = repetition_phase;
                pixelcnt_d = 0;
            end
        endcase
    end

    always @ (posedge clk or posedge reset) begin
        if(reset) begin
            //data_phase <= 1'b0;
            burstcnt <= 0;
            regwrite_state_cs <= addr_phase;
            fetchcnt <= 0;
            linecnt <= 0;
            cursor_buffer <= 0;
            cursor_fetch <= 0;
            firstcur_data <= 0;
            burst1cnt <= 0;
            reg_addr <= 0;
            h1 <= 0;
            h2 <= 0;
            v1 <= 0;
            v2 <= 0;
            cr0 <= 0;
            cur0 <= 0;
            cur1 <= 0;
            curfg <= 0;
            curbg <= 0;
            base <= 0;
            lineinc <= 0;
            cursor <= 0;

            //RGB out FSM
            rgbdisplay_cs <= fetch_phase;
            pixelcnt <= 0; 
            rgb <= 0;
            hcnt <= 0;
            vcnt <= 0;
            hsync <= 0;
            hblank <= 0;
            vsync <= 0;
            vblank <= 0;
            R <= 0;
            G <= 0;
            B <= 0;
        end
        else begin
            //data_phase <= data_phase_d;
            burstcnt <= burstcnt_d;
            regwrite_state_cs <= regwrite_state_ns;
            fetchcnt <= fetchcnt_d;
            linecnt <= linecnt_d;
            cursor_buffer <= cursor_buffer_d;
            cursor_fetch <= cursor_fetch_d;
            firstcur_data <= firstcur_data_d;
            burst1cnt <= burst1cnt_d;
            reg_addr <= reg_addr_d;
            h1 <= h1_d;
            h2 <= h2_d;
            v1 <= v1_d;
            v2 <= v2_d;
            cr0 <= cr0_d;
            cur0 <= cur0_d;
            cur1 <= cur1_d;
            curfg <= curfg_d;
            curbg <= curbg_d;
            base <= base_d;
            lineinc <= lineinc_d;
            cursor <= cursor_d;
            
            //RGB out FSM
            rgbdisplay_cs <= rgbdisplay_ns;
            pixelcnt <= pixelcnt_d;
            rgb <= rgb_d;
            hcnt <= hcnt_d;
            vcnt <= vcnt_d;
            hsync <= hsync_d;
            hblank <= hblank_d;
            vsync <= vsync_d;
            vblank <= vblank_d;
            R <= R_d;
            G <= G_d;
            B <= B_d;
        end
    end
endmodule

