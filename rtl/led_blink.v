module led_blink #(
    parameter integer CLK_FREQ_HZ    = 50000000,
    parameter integer HALF_PERIOD_MS = 1000
)(
    input  wire clk,
    input  wire rst_n,
    output reg  blink_out
);

    localparam integer HALF_PERIOD_TICKS =
        (CLK_FREQ_HZ / 1000) * HALF_PERIOD_MS;

    reg [31:0] counter;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter   <= 32'd0;
            blink_out <= 1'b0;
        end else if (counter == HALF_PERIOD_TICKS - 1) begin
            counter   <= 32'd0;
            blink_out <= ~blink_out;
        end else begin
            counter <= counter + 32'd1;
        end
    end

endmodule