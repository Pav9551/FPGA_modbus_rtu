module fpga_modbus (
    input  clk,
    input  rst_n,

    input  uart_rx,
    output uart_tx,

    input  key0,
    input  key1,

    output led
);

    // ============================================================
    // Параметры
    // ============================================================
    localparam integer CLK_FRE   = 50;
    localparam integer BAUD_RATE = 9600;

    // ============================================================
    // Кнопка key0
    // ============================================================
    wire key_valid;

    key_jitter u_key_jitter (
        .clk       (clk),
        .rst_n     (rst_n),
        .key_n     (key0),
        .key_valid (key_valid)
    );

    // ============================================================
    // Байтный интерфейс.
    //
    // В дальнейшем эти сигналы будут подключены
    // к отдельному модулю протокола.
    // ============================================================
    wire [7:0] tx_data;
    reg        tx_valid;
    wire       tx_ready;

    wire [7:0] rx_data;
    wire       rx_valid;
    wire       rx_ready;

    wire tx_fire;
    wire rx_fire;

    assign tx_fire = tx_valid && tx_ready;
    assign rx_fire = rx_valid && rx_ready;

    // ============================================================
    // UART-интерфейс
    // ============================================================
    uart_interface #(
        .CLK_FRE    (CLK_FRE),
        .BAUD_RATE  (BAUD_RATE),
        .FIFO_DEPTH (64)
    ) u_uart_interface (
        .clk         (clk),
        .rst_n       (rst_n),

        .uart_rx_pin (uart_rx),
        .uart_tx_pin (uart_tx),

        .tx_data     (tx_data),
        .tx_valid    (tx_valid),
        .tx_ready    (tx_ready),

        .rx_data     (rx_data),
        .rx_valid    (rx_valid),
        .rx_ready    (rx_ready)
    );

    // ============================================================
    // Временная прикладная логика:
    // отправка "A" по нажатию key0.
    //
    // В дальнейшем этот блок заменяется модулем протокола.
    // ============================================================
    assign tx_data = 8'h42;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_valid <= 1'b0;
        end
        else begin
            if (key_valid)
                tx_valid <= 1'b1;
            else if (tx_fire)
                tx_valid <= 1'b0;
        end
    end

    // ============================================================
    // Временная прикладная логика:
    // всегда готовы принять байт.
    // ============================================================
    assign rx_ready = 1'b1;

    // ============================================================
    // Светодиод переключается при получении каждого байта.
    // ============================================================
    reg led_state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            led_state <= 1'b0;
        else if (rx_fire)
            led_state <= ~led_state;
    end

    assign led = led_state;
	 //assign led = 1'b1;

    // key1 пока не используется.
    // rx_data содержит принятый байт.

endmodule