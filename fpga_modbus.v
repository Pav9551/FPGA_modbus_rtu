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
    // Параметры платы и UART
    // ============================================================
    // Частота входного clk в MHz.
    localparam integer CLK_FRE   = 50;
    localparam integer BAUD_RATE = 9600;

    // ============================================================
    // Подавление дребезга кнопки key0.
    //
    // key0:
    //   1 — кнопка отпущена;
    //   0 — кнопка нажата.
    //
    // key_valid — однотактный импульс при нажатии.
    // ============================================================
    wire key_valid;

    key_jitter u_key_jitter (
        .clk       (clk),
        .rst_n     (rst_n),
        .key_n     (key0),
        .key_valid (key_valid)
    );

    // ============================================================
    // Интерфейс передачи UART
    // ============================================================
    reg  app_tx_valid;

    wire app_tx_ready;
    wire app_tx_fire;

    assign app_tx_fire = app_tx_valid && app_tx_ready;

    uart_stream_tx #(
        .FIFO_DEPTH (64),
        .CLK_FRE    (CLK_FRE),
        .BAUD_RATE  (BAUD_RATE)
    ) u_uart_stream_tx (
        .clk        (clk),
        .rst_n      (rst_n),

        .data_in    (8'h41),      // Символ "A"
        .data_valid (app_tx_valid),
        .data_ready (app_tx_ready),

        .uart_tx    (uart_tx)
    );

    // ============================================================
    // Один запрос передачи на одно нажатие.
    //
    // До готовности UART запрос остаётся установленным.
    // Если одновременно принят предыдущий символ и пришло
    // новое нажатие, запрос сохраняется для нового символа.
    // ============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            app_tx_valid <= 1'b0;
        end
        else begin
            if (key_valid)
                app_tx_valid <= 1'b1;
            else if (app_tx_fire)
                app_tx_valid <= 1'b0;
        end
    end

    // ============================================================
    // Светодиод меняет состояние, когда uart_stream_tx
    // принимает очередной символ для отправки.
    // ============================================================
    reg led_state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            led_state <= 1'b0;
        else if (app_tx_fire)
            led_state <= ~led_state;
    end

    assign led = led_state;

    // uart_rx и key1 в этой версии не используются.

endmodule