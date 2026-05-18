`default_nettype none

module reg_8bit (
    input  wire       clk,   // System clock
    input  wire       rst_n, // Active-low asynchronous reset
    input  wire [7:0] d,     // 8-bit data input  (From I2C_EXPANDER_0 GPIO_OUT)
    output reg  [7:0] q      // 8-bit data output (To I2C_EXPANDER_1 GPIO_IN)
);

    // ==========================================
    // Synchronous Logic with Asynchronous Reset
    // ==========================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            q <= 8'h00; // Clear the register on reset
        end else begin
            q <= d;     // Latch the input data on the rising edge of the clock
        end
    end

endmodule