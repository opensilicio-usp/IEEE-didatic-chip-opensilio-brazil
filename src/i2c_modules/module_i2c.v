`default_nettype none

module module_i2c (
    input  wire clk,       // System clock for synchronous sampling
    input  wire rst_n,     // Active-low asynchronous reset
    input  wire scl,       // SCL clock wire routed from top-level input
    input  wire sda,       // SDA data wire routed from top-level input
    output wire sda_drive  // Combined output enable for the top-level open-drain SDA pad
);

    // ==========================================
    // Internal Configuration
    // ==========================================
    
    // Defines the generic number of connected I2C expanders internally
    localparam NUM_EXPANDERS = 2;
    
    // Flat vector array containing the 7-bit physical address for each expander instance.
    // Default is 7'h8 for 1 instance. For multiple instances, concatenate them: {7'h9, 7'h8}
    //Following I2C protocol, only the address 0x08 to 0x77 are Available for Peripheral Devices
    localparam [NUM_EXPANDERS*7-1:0] EXPANDER_ADDRESSES = {7'h9, 7'h8};

    // ==========================================
    // Bus Arbitration and Routing
    // ==========================================
    
    // Internal wire vector to collect individual drive requests from each instantiated expander
    wire [NUM_EXPANDERS-1:0] sda_drive_array;

    // Open-Drain Resolution (Wired-AND behavior): 
    // If ANY expander slave wants to pull the SDA line low, it outputs a '1' to sda_drive_array.
    // The bitwise OR reduction combines them so the top-level pad is driven low appropriately.
    assign sda_drive = |sda_drive_array;

    // ==========================================
    // Barramentos Internos (Patch Panel)
    // ==========================================
    wire [NUM_EXPANDERS*8-1:0] internal_gpio_out;
    wire [NUM_EXPANDERS*8-1:0] internal_gpio_in;
    wire [NUM_EXPANDERS-1:0]   internal_gpio_eo;

    // Hardwiring the Expansion Modes based on the schematic:
    assign internal_gpio_eo[1] = 1'b0; // (Expander 1 is Input Only);
    assign internal_gpio_eo[0] = 1'b1; // (Expander 0 is Output Only);

    // Tying unused inputs to ground to prevent floating nodes
    assign internal_gpio_in[7:0] = 8'h00; // Expander 0 doesn't read inputs

    // ==========================================
    // System Instantiation
    // ==========================================
    genvar i;
    generate
        for (i = 0; i < NUM_EXPANDERS; i = i + 1) begin : gen_i2c_system
            
            i2c_expander_core #(
                .MY_ADDRESS(EXPANDER_ADDRESSES[i*7 +: 7])
            ) expander_inst (
                .clk       (clk),
                .rst_n     (rst_n),
                .scl_in    (scl),
                .sda_in    (sda),
                .drive_sda (sda_drive_array[i]),
                // interface dual hardwired
                .gpio_eo   (internal_gpio_eo[i]),        // 0 = Input, 1 = Output
                .gpio_in   (internal_gpio_in[i*8 +: 8]), // Lê do módulo interno
                .gpio_out  (internal_gpio_out[i*8 +: 8]) // Escreve para o módulo interno
            );
        end
    endgenerate

    // ==========================================
    // Test Circuit Instantiation
    // ==========================================
    
    // Instantiating the 8-bit register to act as a bridge between the two expanders.
    // Expander 0 writes to the register, and Expander 1 reads from it.
    reg_8bit test_register_inst (
        .clk   (clk),
        .rst_n (rst_n),
        .d     (internal_gpio_out[7:0]),  // Data comes FROM Expander 0's output
        .q     (internal_gpio_in[15:8])   // Data goes TO Expander 1's input
    );

endmodule