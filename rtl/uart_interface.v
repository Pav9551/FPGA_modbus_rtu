module uart_interface #(
    parameter integer CLK_FRE    = 50,
    parameter integer BAUD_RATE  = 9600,
    parameter integer FIFO_DEPTH = 64
)(
    input             clk,
    input             rst_n,

    // Физические выводы UART.
    input             uart_rx_pin,
    output            uart_tx_pin,

    // Передача байта от прикладной логики.
    input      [7:0]  tx_data,
    input             tx_valid,
    output            tx_ready,

    // Передача принятого байта прикладной логике.
    output     [7:0]  rx_data,
    output            rx_valid,
    input             rx_ready
);

    // ============================================================
    // Передатчик UART
    // ============================================================
    uart_stream_tx #(
        .FIFO_DEPTH (FIFO_DEPTH),
        .CLK_FRE    (CLK_FRE),
        .BAUD_RATE  (BAUD_RATE)
    ) u_uart_stream_tx (
        .clk        (clk),
        .rst_n      (rst_n),

        .data_in    (tx_data),
        .data_valid (tx_valid),
        .data_ready (tx_ready),

        .uart_tx    (uart_tx_pin)
    );

    // ============================================================
    // Приёмник UART
    // ============================================================
    uart_rx #(
        .CLK_FRE   (CLK_FRE),
        .BAUD_RATE (BAUD_RATE)
    ) u_uart_rx (
        .clk           (clk),
        .rst_n         (rst_n),

        .rx_data       (rx_data),
        .rx_data_valid (rx_valid),
        .rx_data_ready (rx_ready),

        .rx_pin        (uart_rx_pin)
    );

endmodule