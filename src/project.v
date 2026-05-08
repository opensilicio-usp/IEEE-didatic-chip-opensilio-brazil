// Copyright (c) 2025 USP OpenSilicio Group (IEEE)
// SPDX-License-Identifier: Apache-2.0

`default_nettype none

// =============================================================
// (IEEE) USP OpenSilicio Didactic Testchip -- TTSKY26B
// Three modules: Logic Gates | Ring Oscillator | PFD
// =============================================================

module tt_um_usp_didactic (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered
    input  wire       clk,      // clock (unused -- design is fully async)
    input  wire       rst_n     // active-low reset
);

    // -- Input aliases ------------------------------------------
    wire        A       = ui_in[5];
    wire        B       = ui_in[6];
    wire [2:0]  sel     = ui_in[4:2];
    wire        clk_ref = ui_in[0];
    wire        clk_vco = ui_in[1];
    wire        ring_en = ui_in[7];

    // Silence unused-input warning
    wire _unused = &{ena, clk, uio_in, 1'b0};

    // ==========================================================
    // MODULE 1 -- Logic Gate Library
    // All 7 gate results are always live on uo_out[7:1].
    // uo_out[0] mirrors the gate selected by sel (ui_in[4:2]).
    // ==========================================================
    wire not_a   = ~A;
    wire and_ab  = A & B;
    wire or_ab   = A | B;
    wire xor_ab  = A ^ B;
    wire nand_ab = ~(A & B);
    wire nor_ab  = ~(A | B);
    wire xnor_ab = ~(A ^ B);

    reg selected_gate;
    always @(*) begin
        case (sel)
            3'd0: selected_gate = not_a;
            3'd1: selected_gate = and_ab;
            3'd2: selected_gate = or_ab;
            3'd3: selected_gate = xor_ab;
            3'd4: selected_gate = nand_ab;
            3'd5: selected_gate = nor_ab;
            3'd6: selected_gate = xnor_ab;
            default: selected_gate = 1'b0;
        endcase
    end

    // uo_out[7:1] = all gates; uo_out[0] = selected gate
    assign uo_out = {xnor_ab, nor_ab, nand_ab, xor_ab,
                     or_ab, and_ab, not_a, selected_gate};

    // ==========================================================
    // MODULE 2 -- 11-Stage Ring Oscillator (explicit SKY130 cells)
    //
    // Behavioral inverters ARE synthesized away by Yosys.
    // (* keep = "true" *) on every instance prevents removal.
    //
    // uio_out[2] -> ring /1024 (reliable measurement path)
    // uio_out[3] -> ring raw (digital pad, degrades above ~400 MHz)
    // ==========================================================
    wire [10:0] ring;

    (* keep = "true" *) sky130_fd_sc_hd__inv_1 inv0  (.A(ring[10] & ring_en), .Y(ring[0]));
    (* keep = "true" *) sky130_fd_sc_hd__inv_1 inv1  (.A(ring[0]),  .Y(ring[1]));
    (* keep = "true" *) sky130_fd_sc_hd__inv_1 inv2  (.A(ring[1]),  .Y(ring[2]));
    (* keep = "true" *) sky130_fd_sc_hd__inv_1 inv3  (.A(ring[2]),  .Y(ring[3]));
    (* keep = "true" *) sky130_fd_sc_hd__inv_1 inv4  (.A(ring[3]),  .Y(ring[4]));
    (* keep = "true" *) sky130_fd_sc_hd__inv_1 inv5  (.A(ring[4]),  .Y(ring[5]));
    (* keep = "true" *) sky130_fd_sc_hd__inv_1 inv6  (.A(ring[5]),  .Y(ring[6]));
    (* keep = "true" *) sky130_fd_sc_hd__inv_1 inv7  (.A(ring[6]),  .Y(ring[7]));
    (* keep = "true" *) sky130_fd_sc_hd__inv_1 inv8  (.A(ring[7]),  .Y(ring[8]));
    (* keep = "true" *) sky130_fd_sc_hd__inv_1 inv9  (.A(ring[8]),  .Y(ring[9]));
    (* keep = "true" *) sky130_fd_sc_hd__inv_1 inv10 (.A(ring[9]),  .Y(ring[10]));

    // Divide-by-1024 counter (10-bit, MSB -> uio_out[2])
    reg [9:0] ring_div;
    always @(posedge ring[10] or negedge rst_n)
        if (!rst_n) ring_div <= 10'd0;
        else        ring_div <= ring_div + 10'd1;

    // ==========================================================
    // MODULE 3 -- Phase-Frequency Detector (PFD)
    //
    // Classic dual-FF topology with AND-based async reset.
    // UP   pulses when clk_ref leads clk_vco.
    // DOWN pulses when clk_vco leads clk_ref.
    //
    // SYNTHESIS NOTE: Each FF uses exactly 2 edge-sensitive events
    // (clock + pfd_reset) which is the max Yosys supports.
    // rst_n is intentionally omitted from PFD FFs -- the pfd_reset
    // mechanism self-clears them; initial value 0 covers simulation.
    // ==========================================================
    wire pfd_reset;
    reg  up_ff   = 1'b0;   // initial value for RTL simulation
    reg  down_ff = 1'b0;   // initial value for RTL simulation

    assign pfd_reset = up_ff & down_ff;

    // Two edge-sensitive events only: posedge clock + posedge async reset
    always @(posedge clk_ref or posedge pfd_reset)
        if (pfd_reset) up_ff   <= 1'b0;
        else           up_ff   <= 1'b1;

    always @(posedge clk_vco or posedge pfd_reset)
        if (pfd_reset) down_ff <= 1'b0;
        else           down_ff <= 1'b1;

    // -- Output assignments -------------------------------------
    // uio[0]=UP, uio[1]=DOWN, uio[2]=ring/1024, uio[3]=ring raw
    assign uio_out = {4'b0000, ring[10], ring_div[9], down_ff, up_ff};
    assign uio_oe  = 8'b00001111;  // bits [3:0] are outputs

endmodule


// =============================================================
// Behavioral stub for RTL simulation only.
// - Excluded during synthesis by SYNTHESIS define (Yosys -D SYNTHESIS)
// - Excluded during gate-level sim by GL_TEST define
// Without the guard, the stub would conflict with the PDK Verilog
// models loaded by the linter (MODDUP warning).
// =============================================================
`ifndef GL_TEST
`ifndef SYNTHESIS
module sky130_fd_sc_hd__inv_1 (
    input  wire A,
    output wire Y
);
    assign Y = ~A;
endmodule
`endif
`endif
