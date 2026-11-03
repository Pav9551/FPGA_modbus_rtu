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
    // Кнопка
    // ============================================================
    wire key_valid;

    key_jitter u_key_jitter (
        .clk       (clk),
        .rst_n     (rst_n),
        .key_n     (key0),
        .key_valid (key_valid)
    );

    // ============================================================
    // Дискретный выход с адресом 0.
    // Кнопка переключает его состояние.
    // ============================================================
    reg coil0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            coil0 <= 1'b0;
        else if (key_valid)
            coil0 <= ~coil0;
    end

    // LED показывает логическое состояние coil0.
    assign led = coil0;

    // ============================================================
    // Байтный интерфейс UART <-> Modbus.
    // ============================================================
    wire [7:0] tx_data;
    wire       tx_valid;
    wire       tx_ready;

    wire [7:0] rx_data;
    wire       rx_valid;
    wire       rx_ready;

    // ============================================================
    // UART
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
    // Начальный обработчик Modbus RTU.
    // ============================================================
    modbus_rtu_slave #(
        .CLK_FRE   (CLK_FRE),
        .BAUD_RATE (BAUD_RATE),
        .SLAVE_ID  (8'd1)
    ) u_modbus_rtu_slave (
        .clk       (clk),
        .rst_n     (rst_n),

        .rx_pin    (uart_rx),

        .rx_data   (rx_data),
        .rx_valid  (rx_valid),
        .rx_ready  (rx_ready),

        .tx_data   (tx_data),
        .tx_valid  (tx_valid),
        .tx_ready  (tx_ready),

        .coil0     (coil0)
    );

    // key1 пока не используется.

endmodule