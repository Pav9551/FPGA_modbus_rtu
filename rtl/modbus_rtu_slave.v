module modbus_rtu_slave #(
    parameter integer CLK_FRE       = 50,
    parameter integer BAUD_RATE     = 9600,
    parameter [7:0]   SLAVE_ID      = 8'd1,
    parameter integer COIL_COUNT   = 16,
    parameter integer HOLDING_COUNT = 32,
    parameter integer INPUT_COUNT  = 2,
    parameter [COIL_COUNT-1:0] COILS_INIT = {COIL_COUNT{1'b0}}
)(
    input clk,
    input rst_n,
    input rx_pin,
    input [7:0] rx_data,
    input rx_valid,
    output rx_ready,
    output [7:0] tx_data,
    output tx_valid,
    input tx_ready,
    input coil_toggle,
    output reg [COIL_COUNT-1:0] coils = COILS_INIT,
    output [HOLDING_COUNT*16-1:0] holding_values,
    // Register 0: [15:0], register 1: [31:16], etc.
    input [INPUT_COUNT*16-1:0] input_values
);

    localparam integer CLK_HZ = CLK_FRE * 1000000;
    localparam integer FRAME_GAP_TICKS =
        (CLK_HZ / BAUD_RATE) * 35 + 35;
    localparam ST_RECEIVE = 1'b0;
    localparam ST_SEND = 1'b1;

    reg state;
    reg [15:0] holding_regs [0:HOLDING_COUNT-1];
    genvar g;
    generate
        for (g = 0; g < HOLDING_COUNT; g = g + 1) begin : GEN_HOLDING
            assign holding_values[g*16 +: 16] = holding_regs[g];
        end
    endgenerate

    reg rx_meta;
    reg rx_sync;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end else begin
            rx_meta <= rx_pin;
            rx_sync <= rx_meta;
        end
    end

    reg [7:0] request [0:7];
    reg [3:0] request_count;
    reg request_overflow;
    reg [15:0] request_crc;
    reg [31:0] gap_counter;
    reg [7:0] response [0:7];
    reg [3:0] response_length;
    reg [2:0] tx_index;

    wire rx_fire;
    wire tx_fire;
    assign rx_ready = 1'b1;
    assign rx_fire = rx_valid && rx_ready;
    assign tx_valid = (state == ST_SEND);
    assign tx_data = response[tx_index];
    assign tx_fire = tx_valid && tx_ready;

    wire [15:0] request_address;
    wire [15:0] request_value;
    assign request_address = {request[2], request[3]};
    assign request_value = {request[4], request[5]};

    function [15:0] crc16_byte;
        input [15:0] crc_in;
        input [7:0] data_in;
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

    // Shared CRC function for one-register responses 03 and 04.
    function [15:0] make_register_read_crc;
        input [7:0] function_code;
        input [15:0] register_value;
        reg [15:0] crc;
        begin
            crc = 16'hFFFF;
            crc = crc16_byte(crc, SLAVE_ID);
            crc = crc16_byte(crc, function_code);
            crc = crc16_byte(crc, 8'h02);
            crc = crc16_byte(crc, register_value[15:8]);
            crc = crc16_byte(crc, register_value[7:0]);
            make_register_read_crc = crc;
        end
    endfunction

    reg [7:0] selected_coil;
    reg [15:0] selected_holding;
    reg [15:0] selected_input;
    always @(*) begin
        selected_coil = 8'h00;
        selected_holding = 16'h0000;
        selected_input = 16'h0000;
        if (request_address < COIL_COUNT)
            selected_coil = {7'b0000000, coils[request_address]};
        if (request_address < HOLDING_COUNT)
            selected_holding = holding_regs[request_address];
        if (request_address < INPUT_COUNT)
            selected_input = input_values[request_address*16 +: 16];
    end

    wire [15:0] coil_read_crc;
    wire [15:0] register_read_crc;
    wire [15:0] input_read_crc;
    assign coil_read_crc = make_coil_read_crc(selected_coil);
    assign register_read_crc = make_register_read_crc(8'h03, selected_holding);
    assign input_read_crc = make_register_read_crc(8'h04, selected_input);

    integer n;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_RECEIVE;
            request_count <= 4'd0;
            request_overflow <= 1'b0;
            request_crc <= 16'hFFFF;
            gap_counter <= 32'd0;
            response_length <= 4'd0;
            tx_index <= 3'd0;
            coils <= COILS_INIT;
            for (n = 0; n < HOLDING_COUNT; n = n + 1)
                holding_regs[n] <= 16'h0000;
            for (n = 0; n < 8; n = n + 1) begin
                request[n] <= 8'h00;
                response[n] <= 8'h00;
            end
        end else begin
            // A simultaneous Modbus write to coil 0 has priority.
            if (coil_toggle)
                coils[0] <= ~coils[0];

            case (state)
                ST_RECEIVE: begin
                    if (rx_fire) begin
                        gap_counter <= 32'd0;
                        request_crc <= crc16_byte(request_crc, rx_data);
                        if (request_count < 4'd8) begin
                            request[request_count] <= rx_data;
                            request_count <= request_count + 1'b1;
                        end else begin
                            request_overflow <= 1'b1;
                        end
                    end else if (!rx_sync) begin
                        gap_counter <= 32'd0;
                    end else if (gap_counter < FRAME_GAP_TICKS) begin
                        gap_counter <= gap_counter + 1'b1;
                    end else if (request_count != 4'd0) begin
                        if (!request_overflow &&
                            (request_count == 4'd8) &&
                            (request_crc == 16'h0000) &&
                            (request[0] == SLAVE_ID)) begin

                            // 01: Read one coil.
                            if ((request[1] == 8'h01) &&
                                (request_address < COIL_COUNT) &&
                                (request_value == 16'd1)) begin
                                response[0] <= SLAVE_ID;
                                response[1] <= 8'h01;
                                response[2] <= 8'h01;
                                response[3] <= selected_coil;
                                response[4] <= coil_read_crc[7:0];
                                response[5] <= coil_read_crc[15:8];
                                response_length <= 4'd6;
                                tx_index <= 3'd0;
                                state <= ST_SEND;
                            end
                            // 03: Read one holding register.
                            else if ((request[1] == 8'h03) &&
                                (request_address < HOLDING_COUNT) &&
                                (request_value == 16'd1)) begin
                                response[0] <= SLAVE_ID;
                                response[1] <= 8'h03;
                                response[2] <= 8'h02;
                                response[3] <= selected_holding[15:8];
                                response[4] <= selected_holding[7:0];
                                response[5] <= register_read_crc[7:0];
                                response[6] <= register_read_crc[15:8];
                                response_length <= 4'd7;
                                tx_index <= 3'd0;
                                state <= ST_SEND;
                            end
                            // 04: Read one input register.
                            else if ((request[1] == 8'h04) &&
                                (request_address < INPUT_COUNT) &&
                                (request_value == 16'd1)) begin
                                response[0] <= SLAVE_ID;
                                response[1] <= 8'h04;
                                response[2] <= 8'h02;
                                response[3] <= selected_input[15:8];
                                response[4] <= selected_input[7:0];
                                response[5] <= input_read_crc[7:0];
                                response[6] <= input_read_crc[15:8];
                                response_length <= 4'd7;
                                tx_index <= 3'd0;
                                state <= ST_SEND;
                            end
                            // 05: Write one coil.
                            else if ((request[1] == 8'h05) &&
                                (request_address < COIL_COUNT) &&
                                ((request_value == 16'hFF00) ||
                                 (request_value == 16'h0000))) begin
                                coils[request_address] <=
                                    (request_value == 16'hFF00);
                                for (n = 0; n < 8; n = n + 1)
                                    response[n] <= request[n];
                                response_length <= 4'd8;
                                tx_index <= 3'd0;
                                state <= ST_SEND;
                            end
                            // 06: Write one holding register.
                            else if ((request[1] == 8'h06) &&
                                (request_address < HOLDING_COUNT)) begin
                                holding_regs[request_address] <= request_value;
                                for (n = 0; n < 8; n = n + 1)
                                    response[n] <= request[n];
                                response_length <= 4'd8;
                                tx_index <= 3'd0;
                                state <= ST_SEND;
                            end
                        end
                        request_count <= 4'd0;
                        request_overflow <= 1'b0;
                        request_crc <= 16'hFFFF;
                        gap_counter <= 32'd0;
                    end
                end
                ST_SEND: begin
                    gap_counter <= 32'd0;
                    if (tx_fire) begin
                        if ({1'b0, tx_index} == (response_length - 4'd1)) begin
                            tx_index <= 3'd0;
                            state <= ST_RECEIVE;
                        end else begin
                            tx_index <= tx_index + 1'b1;
                        end
                    end
                end
                default: begin
                    state <= ST_RECEIVE;
                    request_count <= 4'd0;
                    request_overflow <= 1'b0;
                    request_crc <= 16'hFFFF;
                    gap_counter <= 32'd0;
                    response_length <= 4'd0;
                    tx_index <= 3'd0;
                end
            endcase
        end
    end
endmodule
