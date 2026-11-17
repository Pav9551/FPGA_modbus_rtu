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
	| P1  |  B18  |
	| XX  |  C18  |
	| XX  |  C24  |*/
	output Pin_C5,
	output Pin_C6,
	output Pin_C7,
	output Pin_C8,
	output Pin_C9,
	output Pin_C10,
	output Pin_C11,
	output Pin_C12,
	
	input Pin_B18,
	input Pin_B19
	
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
    // Инициализация
	 localparam [COIL_COUNT-1:0] COILS_INIT =
    16'b0000_0010_1110_1110;

    // ============================================================
    // Кнопка key0.
    // ============================================================
    wire key_valid;
    wire blink_out;
    key_jitter u_key_jitter (
        .clk       (clk),
        .rst_n     (rst_n),
        .key_n     (key0),
        .key_valid (key_valid)
    );
	 // ============================================================
    // Мигание Pin_C10.
    // ============================================================
    led_blink #(
        .CLK_FREQ_HZ    (CLK_FRE * 1_000_000),
        .HALF_PERIOD_MS (500)
    ) u_led_blink (
        .clk       (clk),
        .rst_n     (rst_n),
        .blink_out (blink_out)
    );
    
	 // ============================================================
    // LED горит 3 секунды после снятия сброса, затем гаснет.
    // ============================================================
    localparam integer LED_ON_CYCLES = CLK_FRE * 1_000_000 * 3;

    reg [31:0] led_startup_counter;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            led_startup_counter <= 32'd0;
        end else if (led_startup_counter < LED_ON_CYCLES) begin
            led_startup_counter <= led_startup_counter + 32'd1;
        end
    end

    assign led = rst_n && (led_startup_counter < LED_ON_CYCLES);
    //assign led = Pin_B19;
    // ============================================================
    // Данные устройства.
    // ============================================================
	 localparam integer INPUT_COUNT = 2;

	 wire [INPUT_COUNT*16-1:0] input_values;

	 wire tc_status;
	 wire bc_status;

	 // Input-регистр 0 — TC.
	 //assign input_values[0*16 +: 16] = {15'b0, tc_status};
	 assign input_values[0*16 +: 16] = {15'b0, Pin_B18};

	 // Input-регистр 1 — BC.
	 assign input_values[1*16 +: 16] = {15'b0, Pin_B19};

    wire [COIL_COUNT-1:0] coils;

    wire [HOLDING_COUNT*16-1:0] holding_values;
	 // Светодиод показывает выход TC блока управления возбуждением.
	 //assign led = coils[5];
	 //assign coils[10] = tc_status;
	 generator_excitation_control u_excitation (
    .BOT_CONTROL (coils[6]),
    .TOP_CONTROL (coils[7]),
    .EXC_TRIP    (coils[8]),
    .PROTECTIONS(coils[9]),
    .TC         (tc_status),
    .BC         (bc_status)
    );
	 //assign coils[0] = blink_out;
	 assign Pin_C5 = coils[5];
	 assign Pin_C6 = coils[6];//+Pin_C16
	 assign Pin_C7 = coils[7];
	 assign Pin_C8 = coils[8];
	 assign Pin_C9 = coils[9];//+Pin_C26
	 //assign Pin_C10 = 8'd0;
	 //assign Pin_C11 = coils[11];
	 //assign Pin_C12 = coils[12];
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
    .HOLDING_COUNT (HOLDING_COUNT),
	 .INPUT_COUNT(INPUT_COUNT),

    // Для проверки: только coils[5] = 1.
    .COILS_INIT    (COILS_INIT)
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
    .holding_values (holding_values),
	 .input_values (input_values)
);
    // key1 пока не используется.

endmodule