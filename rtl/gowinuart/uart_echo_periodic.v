module uart_echo_periodic #(
    parameter integer SEND_DELAY = 1,
    parameter integer FIFO_DEPTH = 64,
    parameter integer CLK_FRE    = 50,
    parameter integer BAUD_RATE  = 9600
)(
    input  clk,
    input  rst_n,
    input  uart_rx,
    output uart_tx
);

    localparam integer ONE_SEC_CNT    = CLK_FRE * 1000000;
    localparam integer TX_SEND_PERIOD = ONE_SEC_CNT * SEND_DELAY;
    localparam integer DATA_NUM       = 17;

    reg [31:0] sec_cnt;
    reg        str_active;
    reg [7:0]  str_idx;

    wire [DATA_NUM*8-1:0] send_data = {
        8'h0D, 8'h0A,
        8'hE4, 8'hBD, 8'hA0,
        8'hE5, 8'hA5, 8'hBD,
        8'h20, 8'h20,
        8'h47, 8'h4F, 8'h57, 8'h49, 8'h4E,
        8'h0D, 8'h0A
    };

    wire [7:0] str_byte = send_data[(DATA_NUM - 1 - str_idx)*8 +: 8];

    wire [7:0] rx_data;
    wire       rx_data_valid;
    wire       rx_data_ready;

    reg [7:0] tx_data;
    reg       tx_data_valid;
    wire      tx_data_ready;
    wire      tx_busy;

    wire [7:0] fifo_dout;
    wire       fifo_full;
    wire       fifo_empty;
    wire       fifo_rd_en;
    reg        fifo_wr_en;
    reg [7:0]  fifo_din;

    wire deq = tx_data_ready && !tx_data_valid && !fifo_empty;
    assign fifo_rd_en = deq;

    wire fifo_can_write = !fifo_full || fifo_rd_en;

    assign rx_data_ready = fifo_can_write;
    wire rx_fire = rx_data_valid && rx_data_ready;

    wire str_fire = str_active && fifo_can_write && !rx_fire;

    always @(*) begin
        fifo_wr_en = 1'b0;
        fifo_din   = 8'h00;

        if (rx_fire) begin
            fifo_wr_en = 1'b1;
            fifo_din   = rx_data;
        end else if (str_fire) begin
            fifo_wr_en = 1'b1;
            fifo_din   = str_byte;
        end
    end

    wire tx_all_idle = fifo_empty && tx_data_ready && !tx_data_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sec_cnt    <= 32'd0;
            str_active <= 1'b0;
            str_idx    <= 8'd0;
        end else begin
            if (!str_active) begin
                if (tx_all_idle) begin
                    if (sec_cnt >= (TX_SEND_PERIOD - 1)) begin
                        sec_cnt    <= 32'd0;
                        str_active <= 1'b1;
                        str_idx    <= 8'd0;
                    end else begin
                        sec_cnt <= sec_cnt + 1'b1;
                    end
                end
            end

            if (str_fire) begin
                if (str_idx == (DATA_NUM - 1)) begin
                    str_active <= 1'b0;
                    str_idx    <= 8'd0;
                end else begin
                    str_idx <= str_idx + 1'b1;
                end
            end
        end
    end

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
    ) u_txfifo (
        .clk   (clk),
        .rst_n (rst_n),
        .wr_en (fifo_wr_en),
        .din   (fifo_din),
        .rd_en (fifo_rd_en),
        .dout  (fifo_dout),
        .full  (fifo_full),
        .empty (fifo_empty)
    );

    uart_rx #(
        .CLK_FRE   (CLK_FRE),
        .BAUD_RATE (BAUD_RATE)
    ) u_uart_rx (
        .clk           (clk),
        .rst_n         (rst_n),
        .rx_data       (rx_data),
        .rx_data_valid (rx_data_valid),
        .rx_data_ready (rx_data_ready),
        .rx_pin        (uart_rx)
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
