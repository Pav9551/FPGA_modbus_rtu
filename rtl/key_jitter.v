module key_jitter (
    input      clk,
    input      rst_n,

    input      key_n,
    output reg key_valid
);

    // ============================================================
    // Вход кнопки активен нулём.
    // ============================================================
    reg key_meta;
    reg key_sync;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_meta <= 1'b1;
            key_sync <= 1'b1;
        end
        else begin
            key_meta <= key_n;
            key_sync <= key_meta;
        end
    end

    // ============================================================
    // Счётчик периода проверки кнопки.
    // ============================================================
    reg [19:0] cnt0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            cnt0 <= 20'd0;
        else
            cnt0 <= cnt0 + 1'b1;
    end

    // ============================================================
    // История четырёх выборок.
    //
    // 0 — кнопка отпущена;
    // 1 — кнопка нажата.
    // ============================================================
    reg [3:0] key_down_check;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_down_check <= 4'b0000;
        end
        else if (cnt0 == 20'hFFFFF) begin
            key_down_check <= {
                key_down_check[2:0],
                ~key_sync
            };
        end
    end

    // ============================================================
    // Обнаружение последовательности 0011.
    // ============================================================
    reg key_valid_r0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            key_valid_r0 <= 1'b0;
        else
            key_valid_r0 <= (key_down_check == 4'b0011);
    end

    // ============================================================
    // Выделение переднего фронта.
    // ============================================================
    reg key_valid_r1;
    reg key_valid_r2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_valid_r1 <= 1'b0;
            key_valid_r2 <= 1'b0;
        end
        else begin
            key_valid_r1 <= key_valid_r0;
            key_valid_r2 <= key_valid_r1;
        end
    end

    wire key_valid_pos;

    assign key_valid_pos = key_valid_r1 && !key_valid_r2;

    // ============================================================
    // Выходной импульс длительностью один такт clk.
    // ============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            key_valid <= 1'b0;
        else
            key_valid <= key_valid_pos;
    end

endmodule