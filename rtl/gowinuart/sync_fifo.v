module sync_fifo #(
    parameter integer WIDTH = 8,
    parameter integer DEPTH = 64
)(
    input                  clk,
    input                  rst_n,
    input                  wr_en,
    input  [WIDTH-1:0]     din,
    input                  rd_en,
    output [WIDTH-1:0]     dout,
    output                 full,
    output                 empty
);

    initial begin
        if ((DEPTH & (DEPTH - 1)) != 0)
            $error("DEPTH must be a power of 2");
    end

    localparam integer AW = (DEPTH <= 1) ? 1 : $clog2(DEPTH);

    reg [WIDTH-1:0] mem [0:DEPTH-1];
    reg [AW-1:0]    wptr;
    reg [AW-1:0]    rptr;
    reg [AW:0]      count;

    assign empty = (count == 0);
    assign full  = (count == DEPTH);
    assign dout  = mem[rptr];

    wire do_rd = rd_en && !empty;
    wire do_wr = wr_en && (!full || do_rd);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wptr  <= {AW{1'b0}};
            rptr  <= {AW{1'b0}};
            count <= {(AW+1){1'b0}};
        end else begin
            if (do_wr) begin
                mem[wptr] <= din;
                wptr <= wptr + 1'b1;
            end

            if (do_rd) begin
                rptr <= rptr + 1'b1;
            end

            case ({do_wr, do_rd})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end

endmodule
