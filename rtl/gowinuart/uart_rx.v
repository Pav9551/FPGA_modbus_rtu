module uart_rx #(
    parameter integer CLK_FRE   = 50,
    parameter integer BAUD_RATE = 9600
)(
    input             clk,
    input             rst_n,
    output reg [7:0]  rx_data,
    output reg        rx_data_valid,
    input             rx_data_ready,
    input             rx_pin
);

    localparam integer CYCLE = CLK_FRE * 1000000 / BAUD_RATE;
    localparam integer CNT_W = (CYCLE <= 1) ? 1 : $clog2(CYCLE);

    initial begin
        if (CYCLE < 2)
            $error("UART CYCLE must be >= 2");
    end

    localparam [2:0] S_IDLE     = 3'd0;
    localparam [2:0] S_START    = 3'd1;
    localparam [2:0] S_REC_BYTE = 3'd2;
    localparam [2:0] S_STOP     = 3'd3;
    localparam [2:0] S_DATA     = 3'd4;

    reg [2:0] state, next_state;
    reg       rx_meta, rx_sync, rx_sync_d;
    reg [7:0] rx_bits;
    reg [CNT_W-1:0] cycle_cnt;
    reg [2:0] bit_cnt;

    wire rx_negedge = rx_sync_d && !rx_sync;
    wire rx_fire    = rx_data_valid && rx_data_ready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_meta   <= 1'b1;
            rx_sync   <= 1'b1;
            rx_sync_d <= 1'b1;
        end else begin
            rx_meta   <= rx_pin;
            rx_sync   <= rx_meta;
            rx_sync_d <= rx_sync;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= S_IDLE;
        else
            state <= next_state;
    end

    always @(*) begin
        case (state)
            S_IDLE:
                if (rx_negedge)
                    next_state = S_START;
                else
                    next_state = S_IDLE;

            S_START:
                if (cycle_cnt == (CYCLE/2 - 1)) begin
                    if (!rx_sync)
                        next_state = S_REC_BYTE;
                    else
                        next_state = S_IDLE;
                end else begin
                    next_state = S_START;
                end

            S_REC_BYTE:
                if ((cycle_cnt == (CYCLE - 1)) && (bit_cnt == 3'd7))
                    next_state = S_STOP;
                else
                    next_state = S_REC_BYTE;

            S_STOP:
                if (cycle_cnt == (CYCLE - 1)) begin
                    if (rx_sync)
                        next_state = S_DATA;
                    else
                        next_state = S_IDLE;
                end else begin
                    next_state = S_STOP;
                end

            S_DATA:
                if (rx_fire)
                    next_state = S_IDLE;
                else
                    next_state = S_DATA;

            default:
                next_state = S_IDLE;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_cnt <= {CNT_W{1'b0}};
        end else if (next_state != state) begin
            cycle_cnt <= {CNT_W{1'b0}};
        end else if ((state == S_START) || (state == S_REC_BYTE) || (state == S_STOP)) begin
            if (cycle_cnt == (CYCLE - 1))
                cycle_cnt <= {CNT_W{1'b0}};
            else
                cycle_cnt <= cycle_cnt + 1'b1;
        end else begin
            cycle_cnt <= {CNT_W{1'b0}};
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_cnt <= 3'd0;
        end else if (state == S_REC_BYTE) begin
            if (cycle_cnt == (CYCLE - 1))
                bit_cnt <= bit_cnt + 1'b1;
        end else begin
            bit_cnt <= 3'd0;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_bits <= 8'd0;
        end else if ((state == S_REC_BYTE) && (cycle_cnt == (CYCLE - 1))) begin
            rx_bits[bit_cnt] <= rx_sync;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_data <= 8'd0;
        end else if ((state == S_STOP) && (next_state == S_DATA)) begin
            rx_data <= rx_bits;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_data_valid <= 1'b0;
        end else if ((state == S_STOP) && (next_state == S_DATA)) begin
            rx_data_valid <= 1'b1;
        end else if (rx_fire) begin
            rx_data_valid <= 1'b0;
        end
    end

endmodule
