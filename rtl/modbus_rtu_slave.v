module modbus_rtu_slave #(
    parameter integer CLK_FRE   = 50,
    parameter integer BAUD_RATE = 9600,
    parameter [7:0]   SLAVE_ID  = 8'd1
)(
    input            clk,
    input            rst_n,

    // Физическая линия RX для контроля активности.
    input            rx_pin,

    // Принятые байты.
    input      [7:0] rx_data,
    input            rx_valid,
    output           rx_ready,

    // Передаваемые байты.
    output reg [7:0] tx_data,
    output           tx_valid,
    input            tx_ready,

    // Состояние выхода с адресом 0.
    input            coil0
);

    // ============================================================
    // Таймер конца кадра.
    //
    // Для выбранного формата 8N1:
    // 1 символ = 10 бит.
    // 3.5 символа = 35 бит.
    //
    // Небольшое округление вверх.
    // Для этого начального варианта использовать 9600 бод.
    // ============================================================
    localparam integer CLK_HZ = CLK_FRE * 1000000;

    localparam integer FRAME_GAP_TICKS =
        (CLK_HZ / BAUD_RATE) * 35 + 35;

    // ============================================================
    // Состояния
    // ============================================================
    localparam ST_RECEIVE = 1'b0;
    localparam ST_SEND    = 1'b1;

    reg state;

    // ============================================================
    // Синхронизация линии RX для таймера.
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
    // Приём запроса: ожидается ровно 8 байт.
    // ============================================================
    reg [7:0] request [0:7];
    reg [3:0] request_count;
    reg       request_overflow;

    reg [15:0] request_crc;
    reg [31:0] gap_counter;

    wire rx_fire;
    wire tx_fire;

    // Во время отправки входящие байты потребляются,
    // но не включаются в новый запрос.
    assign rx_ready = 1'b1;
    assign rx_fire  = rx_valid && rx_ready;

    assign tx_valid = (state == ST_SEND);
    assign tx_fire  = tx_valid && tx_ready;

    // ============================================================
    // Ответ:
    // ID 01 01 DATA CRC_LO CRC_HI
    // ============================================================
    reg [2:0]  tx_index;
    reg [7:0]  response_data;
    reg [15:0] response_crc;

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
    // CRC ответа из четырёх байт:
    // SLAVE_ID, 01, 01, DATA.
    // ============================================================
    function [15:0] make_response_crc;
        input [7:0] data_byte;

        reg [15:0] crc;

        begin
            crc = 16'hFFFF;
            crc = crc16_byte(crc, SLAVE_ID);
            crc = crc16_byte(crc, 8'h01);
            crc = crc16_byte(crc, 8'h01);
            crc = crc16_byte(crc, data_byte);

            make_response_crc = crc;
        end
    endfunction

    // ============================================================
    // Выбор передаваемого байта.
    // При ожидании tx_ready индекс и данные не меняются.
    // ============================================================
    always @(*) begin
        case (tx_index)
            3'd0: tx_data = SLAVE_ID;
            3'd1: tx_data = 8'h01;
            3'd2: tx_data = 8'h01;
            3'd3: tx_data = response_data;
            3'd4: tx_data = response_crc[7:0];
            3'd5: tx_data = response_crc[15:8];

            default: tx_data = 8'h00;
        endcase
    end

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

            tx_index         <= 3'd0;
            response_data    <= 8'h00;
            response_crc     <= 16'h0000;
        end
        else begin
            case (state)

                // ================================================
                // Приём запроса.
                // ================================================
                ST_RECEIVE: begin
                    if (rx_fire) begin
                        gap_counter <= 32'd0;

                        // CRC считается по всем принятым байтам,
                        // включая два байта CRC запроса.
                        request_crc <=
                            crc16_byte(request_crc, rx_data);

                        if (request_count < 4'd8) begin
                            request[request_count] <= rx_data;
                            request_count <= request_count + 1'b1;
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

                        // Поддерживается только:
                        // ID 01 00 00 00 01 CRC_LO CRC_HI
                        //
                        // При корректном CRC остаток после
                        // обработки всего кадра равен нулю.
                        if (
                            !request_overflow &&
                            (request_count == 4'd8) &&
                            (request_crc == 16'h0000) &&

                            (request[0] == SLAVE_ID) &&
                            (request[1] == 8'h01) &&

                            (request[2] == 8'h00) &&
                            (request[3] == 8'h00) &&

                            (request[4] == 8'h00) &&
                            (request[5] == 8'h01)
                        ) begin
                            response_data <= {7'b0000000, coil0};

                            response_crc <=
                                make_response_crc(
                                    {7'b0000000, coil0}
                                );

                            tx_index <= 3'd0;
                            state    <= ST_SEND;
                        end

                        // Подготовка к следующему запросу.
                        request_count    <= 4'd0;
                        request_overflow <= 1'b0;
                        request_crc      <= 16'hFFFF;
                        gap_counter      <= 32'd0;
                    end
                end

                // ================================================
                // Передача шести байт ответа в UART FIFO.
                // ================================================
                ST_SEND: begin
                    gap_counter <= 32'd0;

                    if (tx_fire) begin
                        if (tx_index == 3'd5) begin
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
                    tx_index         <= 3'd0;
                end

            endcase
        end
    end

endmodule