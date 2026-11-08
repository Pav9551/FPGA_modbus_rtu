module fpga_modbus (
    input  clk,
    input  rst_n,

    input  uart_rx,
    output uart_tx,

    input  key0,
    input  key1,

    output led,
	 
/*	| PIN | CRATE |
	|-----|-------|
	| D4  |  C5   |
	| C3  |  C6   |
	| D3  |  C7   |
	| D5  |  C8   |
	| E5  |  C9   |
	| F3  |  --   |
	| F5  |  C11  |
	| L6  |  C12  |
	| K6  |  C10  |
	
	| XX  |  C14  |
	| XX  |  C15  |
	| XX  |  C16  |
	| XX  |  C17  |
	| XX  |  C18  |
	| XX  |  C24  |*/
	output Pin_C5,
	output Pin_C6,
	output Pin_C7,
	output Pin_C8,
	output Pin_C9,
	output Pin_C10,
	output Pin_C11,
	output Pin_C12
);

    // ============================================================
    // Параметры платы и UART.
    // ============================================================
    localparam integer CLK_FRE   = 50;
    localparam integer BAUD_RATE = 9600;

    // ============================================================
    // Количество объектов Modbus.
    //
    // Значения должны быть не меньше 1.
    //
    // Например:
    // COIL_COUNT = 16    -> адреса 0...15
    // HOLDING_COUNT = 32 -> адреса 0...31
    // ============================================================
    localparam integer COIL_COUNT    = 16;
    localparam integer HOLDING_COUNT = 32;

    // ============================================================
    // Кнопка key0.
    // ============================================================
    wire key_valid;

    key_jitter u_key_jitter (
        .clk       (clk),
        .rst_n     (rst_n),
        .key_n     (key0),
        .key_valid (key_valid)
    );
	 // ============================================================
    // Мигание Pin_C10.
    // ============================================================
    /*led_blink #(
        .CLK_FREQ_HZ    (CLK_FRE * 1_000_000),
        .HALF_PERIOD_MS (500)
    ) u_led_blink (
        .clk       (clk),
        .rst_n     (rst_n),
        .blink_out (Pin_C10)
    );*/


    // ============================================================
    // Данные устройства.
    // ============================================================
    wire [COIL_COUNT-1:0] coils;

    wire [HOLDING_COUNT*16-1:0] holding_values;

    // Светодиод показывает состояние выхода с адресом 0.
    assign led =  coils[0];
	 assign Pin_C5 = 8'd0;
	 assign Pin_C6 = 8'd0;//+Pin_C16
	 assign Pin_C7 = 8'd0;
	 assign Pin_C8 = 8'd0;
	 assign Pin_C9 = 8'd0;//+Pin_C26
	 //assign Pin_C10 = 8'd0;
	 assign Pin_C11 = 8'd0;
	 assign Pin_C12 = 8'd0;
	 //assign Pin_C13 = 8'd0;

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
    // UART.
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
    // Modbus RTU.
    // ============================================================
    modbus_rtu_slave #(
        .CLK_FRE       (CLK_FRE),
        .BAUD_RATE     (BAUD_RATE),
        .SLAVE_ID      (8'd1),

        .COIL_COUNT    (COIL_COUNT),
        .HOLDING_COUNT (HOLDING_COUNT)
    ) u_modbus_rtu_slave (
        .clk            (clk),
        .rst_n          (rst_n),

        .rx_pin         (uart_rx),

        .rx_data        (rx_data),
        .rx_valid       (rx_valid),
        .rx_ready       (rx_ready),

        .tx_data        (tx_data),
        .tx_valid       (tx_valid),
        .tx_ready       (tx_ready),

        .coil_toggle    (key_valid),

        .coils          (coils),
        .holding_values (holding_values)
    );

    // key1 пока не используется.

endmodule