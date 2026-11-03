module modbus_rtu_slave #(
    parameter integer CLK_FRE   = 50,
    parameter integer BAUD_RATE = 9600,
    parameter [7:0]   SLAVE_ID  = 8'd1
)(
    input             clk,
    input             rst_n,

    // Физическая линия RX для контроля активности.
    input             rx_pin,

    // Принятые байты от UART.
    input      [7:0]  rx_data,
    input             rx_valid,
    output            rx_ready,

    // Передаваемые байты в UART.
    output     [7:0]  tx_data,
    output            tx_valid,
    input             tx_ready,

    // Однотактный импульс от кнопки.
    input             coil_toggle,

    // Дискретный выход с адресом 0.
    output reg        coil0,

    // Holding-регистр с адресом 0.
    output reg [15:0] holding0 /* synthesis preserve */
);

    // ============================================================
    // Таймер конца кадра.
    //
    // Текущий формат UART: 8N1.
    // Один символ = 10 бит.
    // Пауза 3.5 символа = 35 бит.
    //
    // Эта начальная реализация используется при 9600 бод.
    // ============================================================
    localparam integer CLK_HZ = CLK_FRE * 1000000;

    localparam integer FRAME_GAP_TICKS =
        (CLK_HZ / BAUD_RATE) * 35 + 35;

    // ============================================================
    // Состояния.
    // ============================================================
    localparam ST_RECEIVE = 1'b0;
    localparam ST_SEND    = 1'b1;

    reg state;

    // ============================================================
    // Синхронизация физической линии RX.
    // Используется только для контроля активности линии.
    // ============================================================
    reg rx_meta;
    reg rx_sync;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end
        else begin
            rx_meta <= rx_pin;
            rx_sync <= rx_meta;
        end
    end

    // ============================================================
    // Буфер запроса.
    //
    // Все поддерживаемые запросы имеют длину 8 байт.
    // ============================================================
    reg [7:0] request [0:7];

    reg [3:0] request_count;
    reg       request_overflow;

    reg [15:0] request_crc;
    reg [31:0] gap_counter;

    // ============================================================
    // Буфер ответа.
    //
    // 01: 6 байт.
    // 03: 7 байт.
    // 05: 8 байт.
    // 06: 8 байт.
    // ============================================================
    reg [7:0] response [0:7];

    reg [3:0] response_length;
    reg [2:0] tx_index;

    wire rx_fire;
    wire tx_fire;

    // Входящие байты всегда потребляются.
    // Во время ST_SEND они не включаются в новый запрос.
    assign rx_ready = 1'b1;
    assign rx_fire  = rx_valid && rx_ready;

    assign tx_valid = (state == ST_SEND);
    assign tx_data  = response[tx_index];
    assign tx_fire  = tx_valid && tx_ready;

    // ============================================================
    // CRC16 Modbus: обработка одного байта.
    // ============================================================
    function [15:0] crc16_byte;
        input [15:0] crc_in;
        input [7:0]  data_in;

        reg [15:0] crc;
        integer i;

        begin
            crc = crc_in ^ {8'h00, data_in};

            for (i = 0; i < 8; i = i + 1) begin
                if (crc[0])
                    crc = (crc >> 1) ^ 16'hA001;
                else
                    crc = crc >> 1;
            end

            crc16_byte = crc;
        end
    endfunction

    // ============================================================
    // CRC ответа функции 01.
    //
    // SLAVE_ID 01 01 DATA
    // ============================================================
    function [15:0] make_coil_read_crc;
        input [7:0] data_byte;

        reg [15:0] crc;

        begin
            crc = 16'hFFFF;
            crc = crc16_byte(crc, SLAVE_ID);
            crc = crc16_byte(crc, 8'h01);
            crc = crc16_byte(crc, 8'h01);
            crc = crc16_byte(crc, data_byte);

            make_coil_read_crc = crc;
        end
    endfunction

    // ============================================================
    // CRC ответа функции 03.
    //
    // SLAVE_ID 03 02 DATA_HI DATA_LO
    // ============================================================
    function [15:0] make_register_read_crc;
        input [15:0] register_value;

        reg [15:0] crc;

        begin
            crc = 16'hFFFF;
            crc = crc16_byte(crc, SLAVE_ID);
            crc = crc16_byte(crc, 8'h03);
            crc = crc16_byte(crc, 8'h02);
            crc = crc16_byte(crc, register_value[15:8]);
            crc = crc16_byte(crc, register_value[7:0]);

            make_register_read_crc = crc;
        end
    endfunction

    // ============================================================
    // Данные и CRC ответов чтения.
    // При формировании ответа они сохраняются в response[].
    // ============================================================
    wire [7:0]  coil_read_value;
    wire [15:0] coil_read_crc;
    wire [15:0] register_read_crc;

    assign coil_read_value = {7'b0000000, coil0};

    assign coil_read_crc =
        make_coil_read_crc(coil_read_value);

    assign register_read_crc =
        make_register_read_crc(holding0);

    integer n;

    // ============================================================
    // Основной автомат.
    // ============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= ST_RECEIVE;

            request_count    <= 4'd0;
            request_overflow <= 1'b0;
            request_crc      <= 16'hFFFF;
            gap_counter      <= 32'd0;

            response_length  <= 4'd0;
            tx_index         <= 3'd0;

            coil0            <= 1'b0;
            holding0         <= 16'h0000;

            for (n = 0; n < 8; n = n + 1) begin
                request[n]  <= 8'h00;
                response[n] <= 8'h00;
            end
        end
        else begin

            // Переключение coil0 кнопкой.
            //
            // Если одновременно выполняется запись функцией 05,
            // приоритет имеет запись Modbus ниже.
            if (coil_toggle)
                coil0 <= ~coil0;

            case (state)

                // ================================================
                // Приём запроса.
                // ================================================
                ST_RECEIVE: begin

                    if (rx_fire) begin
                        gap_counter <= 32'd0;

                        // Обрабатывается весь кадр,
                        // включая два байта CRC.
                        request_crc <=
                            crc16_byte(request_crc, rx_data);

                        if (request_count < 4'd8) begin
                            request[request_count] <= rx_data;

                            request_count <=
                                request_count + 1'b1;
                        end
                        else begin
                            request_overflow <= 1'b1;
                        end
                    end
                    else if (!rx_sync) begin

                        // Линия активна: паузы пока нет.
                        gap_counter <= 32'd0;
                    end
                    else if (gap_counter < FRAME_GAP_TICKS) begin

                        gap_counter <= gap_counter + 1'b1;
                    end
                    else if (request_count != 4'd0) begin

                        // ----------------------------------------
                        // Общая проверка:
                        // - ровно 8 байт;
                        // - нет переполнения;
                        // - корректный CRC;
                        // - совпадает адрес устройства.
                        // ----------------------------------------
                        if (
                            !request_overflow &&
                            (request_count == 4'd8) &&
                            (request_crc == 16'h0000) &&
                            (request[0] == SLAVE_ID)
                        ) begin

                            // ------------------------------------
                            // 01: Read Coils.
                            //
                            // Адрес: 0.
                            // Количество: 1.
                            // ------------------------------------
                            if (
                                (request[1] == 8'h01) &&
                                (request[2] == 8'h00) &&
                                (request[3] == 8'h00) &&
                                (request[4] == 8'h00) &&
                                (request[5] == 8'h01)
                            ) begin

                                response[0] <= SLAVE_ID;
                                response[1] <= 8'h01;
                                response[2] <= 8'h01;
                                response[3] <= coil_read_value;
                                response[4] <= coil_read_crc[7:0];
                                response[5] <= coil_read_crc[15:8];

                                response_length <= 4'd6;
                                tx_index        <= 3'd0;
                                state           <= ST_SEND;
                            end

                            // ------------------------------------
                            // 03: Read Holding Registers.
                            //
                            // Адрес: 0.
                            // Количество: 1.
                            // ------------------------------------
                            else if (
                                (request[1] == 8'h03) &&
                                (request[2] == 8'h00) &&
                                (request[3] == 8'h00) &&
                                (request[4] == 8'h00) &&
                                (request[5] == 8'h01)
                            ) begin

                                response[0] <= SLAVE_ID;
                                response[1] <= 8'h03;
                                response[2] <= 8'h02;

                                response[3] <= holding0[15:8];
                                response[4] <= holding0[7:0];

                                response[5] <=
                                    register_read_crc[7:0];

                                response[6] <=
                                    register_read_crc[15:8];

                                response_length <= 4'd7;
                                tx_index        <= 3'd0;
                                state           <= ST_SEND;
                            end

                            // ------------------------------------
                            // 05: Write Single Coil.
                            //
                            // Адрес: 0.
                            // FF00 — включить.
                            // 0000 — выключить.
                            // ------------------------------------
                            else if (
                                (request[1] == 8'h05) &&
                                (request[2] == 8'h00) &&
                                (request[3] == 8'h00) &&
                                (request[5] == 8'h00) &&
                                (
                                    (request[4] == 8'hFF) ||
                                    (request[4] == 8'h00)
                                )
                            ) begin

                                coil0 <= (request[4] == 8'hFF);

                                // Ответ повторяет запрос.
                                for (n = 0; n < 8; n = n + 1)
                                    response[n] <= request[n];

                                response_length <= 4'd8;
                                tx_index        <= 3'd0;
                                state           <= ST_SEND;
                            end

                            // ------------------------------------
                            // 06: Preset Single Register.
                            //
                            // Адрес: 0.
                            // request[4] — старший байт.
                            // request[5] — младший байт.
                            // ------------------------------------
                            else if (
                                (request[1] == 8'h06) &&
                                (request[2] == 8'h00) &&
                                (request[3] == 8'h00)
                            ) begin

                                holding0 <= {
                                    request[4],
                                    request[5]
                                };

                                // Ответ повторяет запрос.
                                for (n = 0; n < 8; n = n + 1)
                                    response[n] <= request[n];

                                response_length <= 4'd8;
                                tx_index        <= 3'd0;
                                state           <= ST_SEND;
                            end

                        end

                        // Подготовка к следующему запросу.
                        request_count    <= 4'd0;
                        request_overflow <= 1'b0;
                        request_crc      <= 16'hFFFF;
                        gap_counter      <= 32'd0;
                    end
                end

                // ================================================
                // Передача ответа в UART FIFO.
                //
                // Пока tx_ready = 0, индекс и данные сохраняются.
                // ================================================
                ST_SEND: begin
                    gap_counter <= 32'd0;

                    if (tx_fire) begin

                        if (
                            {1'b0, tx_index} ==
                            (response_length - 4'd1)
                        ) begin

                            tx_index <= 3'd0;
                            state    <= ST_RECEIVE;
                        end
                        else begin

                            tx_index <= tx_index + 1'b1;
                        end
                    end
                end

                default: begin
                    state            <= ST_RECEIVE;

                    request_count    <= 4'd0;
                    request_overflow <= 1'b0;
                    request_crc      <= 16'hFFFF;
                    gap_counter      <= 32'd0;

                    response_length  <= 4'd0;
                    tx_index         <= 3'd0;
                end

            endcase
        end
    end

endmodule