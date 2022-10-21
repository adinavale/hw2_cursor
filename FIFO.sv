module FIFO #(parameter FIFO_depth = 16,
    parameter FIFO_width = 32,
    parameter addr_width = 4) ( 
    input clk, rst, rd_en, wr_en, 
    input reg[31:0] data_in,
    output reg empty, full, half_full,
    output reg[31:0] data_out
    ); 

    // parameter FIFO_depth = 16,
    //           FIFO_width = 32,
    //           addr_width = 4;

    reg [addr_width-1:0] rd_addr_d , wr_addr_d, rd_addr, wr_addr;
    reg [FIFO_depth-1:0] [FIFO_width-1:0] mem, mem_d;

    assign empty = (((rd_addr - wr_addr) == 0) || ((wr_addr - rd_addr) == 0)) ? 1'b1 : 1'b0;
    assign full = (((rd_addr - wr_addr) == 1) || ((wr_addr - rd_addr) == FIFO_depth - 1))  ? 1'b1 : 1'b0;
    assign half_full = ((((rd_addr - wr_addr) < (FIFO_depth/2) -1) && ~empty) || ((wr_addr - rd_addr) > (FIFO_depth/2) - 1))  ? 1'b1 : 1'b0;

    always @ (*) begin
	    mem_d = mem;
        wr_addr_d = wr_addr;
        rd_addr_d = rd_addr;
	    data_out = 0;
        if(wr_en && !full) begin
            wr_addr_d = wr_addr + 1;
            mem_d[wr_addr] = data_in;
        end

        if(rd_en && !empty) begin
            rd_addr_d = rd_addr + 1;
            data_out = mem[rd_addr];
        end
    end

    always @ (posedge clk or posedge rst) begin
        if(rst) begin
            wr_addr <= 0;
            rd_addr <= 0;
            mem <= 0;
        end
        else begin
            wr_addr <= wr_addr_d;
            rd_addr <= rd_addr_d;
            mem <= mem_d;
        end
    end
endmodule

