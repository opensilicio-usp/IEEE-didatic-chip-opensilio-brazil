`default_nettype none

module i2c_expander_core #(
    // Base 7-bit I2C address for this specific instance
    parameter [6:0] MY_ADDRESS = 7'h27
)(
    input  wire       clk,        // System clock (high speed)
    input  wire       rst_n,      // Active-low asynchronous reset
    
    // I2C Physical Bus Signals
    input  wire       scl_in,     // Serial Clock input
    input  wire       sda_in,     // Serial Data input
    output reg        drive_sda,  // 1 = Pull SDA low (GND), 0 = Release SDA (High-Z)
    
    // Internal Hardwired Dual-Interface
    input  wire       gpio_eo,    // Expansion Mode: 0 = Input Expander, 1 = Output Expander
    input  wire [7:0] gpio_in,    // Sensed inputs from internal logic
    output reg  [7:0] gpio_out    // Driven outputs to internal logic
);

    // ==========================================
    // 1. Bus Synchronization & Edge Detection
    // ==========================================
    // I2C lines are asynchronous to the system clock. 
    // We use 3-stage shift registers to prevent metastability and detect edges.
    reg [2:0] scl_sync;
    reg [2:0] sda_sync;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scl_sync <= 3'b111; // I2C lines idle high
            sda_sync <= 3'b111;
        end else begin
            scl_sync <= {scl_sync[1:0], scl_in};
            sda_sync <= {sda_sync[1:0], sda_in};
        end
    end

    // Edge detectors for the SCL clock
    wire scl_rise = (scl_sync[2:1] == 2'b01);
    wire scl_fall = (scl_sync[2:1] == 2'b10);
    wire sda_val  = sda_sync[2];

    // START/STOP condition detectors (SDA changes while SCL is HIGH)
    wire start_cond = (scl_sync[2] == 1'b1) && (sda_sync[2:1] == 2'b10); // SDA goes low
    wire stop_cond  = (scl_sync[2] == 1'b1) && (sda_sync[2:1] == 2'b01); // SDA goes high

    // ==========================================
    // 2. State Machine Declarations
    // ==========================================
    localparam STATE_IDLE     = 3'd0;
    localparam STATE_RX_ADDR  = 3'd1;
    localparam STATE_ACK_ADDR = 3'd2;
    localparam STATE_RX_DATA  = 3'd3;
    localparam STATE_TX_ACK   = 3'd4;
    localparam STATE_TX_DATA  = 3'd5;
    localparam STATE_RX_ACK   = 3'd6;

    reg [2:0] state;
    reg [3:0] bit_cnt;     // Counts from 0 to 8 bits
    reg [7:0] shift_reg;   // Central register for serial/parallel conversion
    reg       ack_rx;      // Stores the ACK/NACK bit sent by the Master during reads

    // ==========================================
    // 3. FSM Sequential Logic
    // ==========================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= STATE_IDLE;
            bit_cnt  <= 4'd0;
            shift_reg<= 8'h00;
            gpio_out <= 8'h00;
            ack_rx   <= 1'b1;
        end else begin
            
            // Asynchronous-like protocol resets
            if (start_cond) begin
                state   <= STATE_RX_ADDR;
                bit_cnt <= 4'd0;
            end else if (stop_cond) begin
                state   <= STATE_IDLE;
            end else begin
                
                case (state)
                    
                    STATE_IDLE: begin
                        // Waiting for START condition...
                    end
                    
                    // ------------------------------------
                    // ADDRESSING PHASE
                    // ------------------------------------
                    STATE_RX_ADDR: begin
                        if (scl_rise) begin
                            shift_reg <= {shift_reg[6:0], sda_val}; // Sample on rising edge
                            bit_cnt   <= bit_cnt + 1'b1;
                        end else if (scl_fall && bit_cnt == 4'd8) begin
                            // Check if the received 7-bit address matches
                            if (shift_reg[7:1] == MY_ADDRESS) begin
                                state <= STATE_ACK_ADDR;
                            end else begin
                                state <= STATE_IDLE; // Not our address, ignore transaction
                            end
                        end
                    end
                    
                    STATE_ACK_ADDR: begin
                        // drive_sda is handled combinationally below
                        if (scl_fall) begin
                            if (shift_reg[0] == 1'b0) begin 
                                // W=0 (Master wants to Write)
                                state   <= STATE_RX_DATA;
                                bit_cnt <= 4'd0;
                            end else begin                  
                                // R=1 (Master wants to Read)
                                state   <= STATE_TX_DATA;
                                bit_cnt <= 4'd0;
                                
                                // EXCEPTION LOGIC (READ): 
                                // If Output Mode (eo=1), echo back our own output register.
                                // If Input Mode (eo=0), sample the physical input pins.
                                shift_reg <= (gpio_eo == 1'b1) ? gpio_out : gpio_in;
                            end
                        end
                    end
                    
                    // ------------------------------------
                    // WRITE PHASE (Master -> Slave)
                    // ------------------------------------
                    STATE_RX_DATA: begin
                        if (scl_rise) begin
                            shift_reg <= {shift_reg[6:0], sda_val};
                            bit_cnt   <= bit_cnt + 1'b1;
                        end else if (scl_fall && bit_cnt == 4'd8) begin
                            state <= STATE_TX_ACK;
                            
                            // EXCEPTION LOGIC (WRITE):
                            // Silently ignore incoming data if configured as an Input Expander.
                            // Only latch data to physical outputs if gpio_eo == 1.
                            if (gpio_eo == 1'b1) begin
                                gpio_out <= shift_reg;
                            end
                        end
                    end
                    
                    STATE_TX_ACK: begin
                        if (scl_fall) begin
                            state   <= STATE_RX_DATA; // Be ready for the next sequential byte
                            bit_cnt <= 4'd0;
                        end
                    end
                    
                    // ------------------------------------
                    // READ PHASE (Slave -> Master)
                    // ------------------------------------
                    STATE_TX_DATA: begin
                        // drive_sda pushes shift_reg[7] combinationally
                        if (scl_fall) begin
                            if (bit_cnt == 4'd8) begin
                                state <= STATE_RX_ACK; // Sent 8 bits, wait for master to ACK
                            end else begin
                                shift_reg <= {shift_reg[6:0], 1'b1}; // Shift left
                                bit_cnt   <= bit_cnt + 1'b1;
                            end
                        end
                    end
                    
                    STATE_RX_ACK: begin
                        if (scl_rise) begin
                            ack_rx <= sda_val; // Master sends 0 to continue, 1 to stop
                        end else if (scl_fall) begin
                            if (ack_rx == 1'b0) begin 
                                // Master ACKed. Send next byte!
                                state   <= STATE_TX_DATA;
                                bit_cnt <= 4'd0;
                                // Reload data (allows continuous real-time sampling/echoing)
                                shift_reg <= (gpio_eo == 1'b1) ? gpio_out : gpio_in;
                            end else begin 
                                // Master NACKed. Transaction over.
                                state <= STATE_IDLE;
                            end
                        end
                    end
                    
                    default: state <= STATE_IDLE;
                endcase
            end
        end
    end

    // ==========================================
    // 4. Output Combinational Logic (Open-Drain)
    // ==========================================
    // In I2C, driving SDA low (0) requires enabling the output transistor.
    // Driving SDA high (1) requires disabling it (releasing the line).
    always @(*) begin
        drive_sda = 1'b0; // Default: Release bus (High-Z)
        
        case (state)
            STATE_ACK_ADDR: drive_sda = 1'b1; // Send ACK (Pull low)
            STATE_TX_ACK:   drive_sda = 1'b1; // Send ACK (Pull low)
            STATE_TX_DATA:  begin
                // If the bit to transmit is 0, pull SDA low.
                // If the bit is 1, release SDA.
                if (shift_reg[7] == 1'b0)
                    drive_sda = 1'b1;
            end
            default: drive_sda = 1'b0;
        endcase
    end

endmodule