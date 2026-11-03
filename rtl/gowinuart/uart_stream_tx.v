module uart_stream_tx #(
    parameter integer FIFO_DEPTH = 64,
    parameter integer CLK_FRE    = 27,
    parameter integer BAUD_RATE  = 115200
)(
    input             clk,
    input             rst_n,

    // Runtime byte-stream input. A byte is queued only on valid && ready.
    input      [7:0]  data_in,
    input             data_valid,
    output            data_ready,

    output            uart_tx
);

    wire [7:0] fifo_dout;
    wire       fifo_full;
    wire       fifo_empty;
    wire       fifo_rd_en;

    reg [7:0] tx_data;
    reg       tx_data_valid;
    wire      tx_data_ready;
    wire      tx_busy;

    // The input can write while the FIFO is full if TX removes its head
    // on this same rising edge.
    wire deq = tx_data_ready && !tx_data_valid && !fifo_empty;
    assign fifo_rd_en = deq;
    assign data_ready = !fifo_full || fifo_rd_en;

    wire fifo_wr_en = data_valid && data_ready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_data       <= 8'd0;
            tx_data_valid <= 1'b0;
        end else begin
            if (tx_data_valid && tx_data_ready)
                tx_data_valid <= 1'b0;

            if (deq) begin
                tx_data       <= fifo_dout;
                tx_data_valid <= 1'b1;
            end
        end
    end

    sync_fifo #(
        .WIDTH(8),
        .DEPTH(FIFO_DEPTH)
    ) u_fifo (
        .clk   (clk),
        .rst_n (rst_n),
        .wr_en (fifo_wr_en),
        .din   (data_in),
        .rd_en (fifo_rd_en),
        .dout  (fifo_dout),
        .full  (fifo_full),
        .empty (fifo_empty)
    );

    uart_tx #(
        .CLK_FRE   (CLK_FRE),
        .BAUD_RATE (BAUD_RATE)
    ) u_uart_tx (
        .clk           (clk),
        .rst_n         (rst_n),
        .tx_data       (tx_data),
        .tx_data_valid (tx_data_valid),
        .tx_data_ready (tx_data_ready),
        .tx_pin        (uart_tx),
        .tx_busy       (tx_busy)
    );

endmodule
