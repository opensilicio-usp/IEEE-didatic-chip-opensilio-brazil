// Copyright (c) 2025 USP OpenSilicio Group (IEEE)
// SPDX-License-Identifier: Apache-2.0

`default_nettype none

// =============================================================
// (IEEE) USP OpenSilicio Didactic Testchip -- TTSKY26B
//
// Five educational modules routed by a 3-bit main MUX:
//   ui_in[7:5] = main_sel
//   000 -- Logic Gate Library
//   001 -- Ring Oscillator + 24-bit Configurable Divider
//   010 -- Phase-Frequency Detector (PFD)
//   011 -- Flip-Flop Study (D-FF and T-FF)
//   100 -- 4-Bit Binary Counter
//   101-111 -- outputs grounded (reserved)
//
//   ui_in[4:0] = sub_in (shared; meaning varies by module)
//   uio_out[3:0] = always-live monitoring regardless of main_sel
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

    // -- Global selectors --------------------------------------
    wire [2:0] main_sel = ui_in[7:5];
    wire [4:0] sub_in   = ui_in[4:0];

    // Silence unused-input warning
    wire _unused = &{ena, clk, uio_in, 1'b0};

    // ==========================================================
    // MODULE 0 (main_sel=000) -- Logic Gate Library
    //
    // sub_in[0] = A
    // sub_in[1] = B
    // sub_in[4:2] = gate_sel (selects which gate drives uo_out[0])
    //
    // uo_out[7:1] -- all 7 gates live simultaneously
    // uo_out[0]   -- gate selected by gate_sel
    // ==========================================================
    wire        A        = sub_in[0];
    wire        B        = sub_in[1];
    wire [2:0]  gate_sel = sub_in[4:2];

    wire not_a   = ~A;
    wire and_ab  = A & B;
    wire or_ab   = A | B;
    wire xor_ab  = A ^ B;
    wire nand_ab = ~(A & B);
    wire nor_ab  = ~(A | B);
    wire xnor_ab = ~(A ^ B);

    reg selected_gate;
    always @(*) begin
        case (gate_sel)
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

    wire [7:0] gates_out = {xnor_ab, nor_ab, nand_ab, xor_ab,
                             or_ab, and_ab, not_a, selected_gate};

    // ==========================================================
    // MODULE 1 (main_sel=001) -- 11-Stage Ring Oscillator
    //                            + 24-bit Configurable Divider
    //
    // sub_in[2]   = ring_en  (active high: enables oscillation)
    // sub_in[1:0] = div_sel  (selects frequency tap)
    //   00 -> ring_div[6]  ~ 13.6 MHz  (scope measurement)
    //   01 -> ring_div[12] ~  424 kHz  (USB logic analyzer)
    //   10 -> ring_div[20] ~  830 Hz   (audio / buzzer)
    //   11 -> ring_div[23] ~  104 Hz   (LED-visible blink)
    //
    // uo_out[0] -- selected divider tap
    //
    // Explicit sky130_fd_sc_hd__inv_1 instantiations with
    // (* keep = "true" *) prevent Yosys from optimising away
    // the chain. The intentional combinatorial loop is expected;
    // config.json sets SYNTH_CHECKS_ALLOW_COMBO_LOOP=1.
    // ==========================================================
    wire        ring_en  = sub_in[2];
    wire [1:0]  div_sel  = sub_in[1:0];

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

    reg [23:0] ring_div;
    always @(posedge ring[10] or negedge rst_n)
        if (!rst_n) ring_div <= 24'd0;
        else        ring_div <= ring_div + 24'd1;

    reg ring_div_out;
    always @(*) begin
        case (div_sel)
            2'd0: ring_div_out = ring_div[6];
            2'd1: ring_div_out = ring_div[12];
            2'd2: ring_div_out = ring_div[20];
            default: ring_div_out = ring_div[23];
        endcase
    end

    wire [7:0] ring_out = {7'b0, ring_div_out};

    // ==========================================================
    // MODULE 2 (main_sel=010) -- Phase-Frequency Detector (PFD)
    //
    // Classic dual-FF topology with reset when both set.
    // sub_in[0] = clk_ref
    // sub_in[1] = clk_vco
    //
    // UP   pulses when clk_ref leads clk_vco -> uo_out[0]
    // DOWN pulses when clk_vco leads clk_ref -> uo_out[1]
    //
    // SYNTHESIS NOTE:
    // The "textbook" async-reset PFD (pfd_reset fed back into the FF
    // async resets) is flagged by Yosys "check" as a logic loop (ARST->Q),
    // which fails LibreLane's Checker.YosysSynthChecks. We therefore clear
    // the FFs synchronously (sample pfd_reset on clock edges) and include
    // rst_n for deterministic init.
    // ==========================================================
    wire clk_ref = sub_in[0];
    wire clk_vco = sub_in[1];

    wire pfd_reset;
    reg  up_ff;
    reg  down_ff;

    assign pfd_reset = up_ff & down_ff;

    always @(posedge clk_ref or negedge rst_n) begin
        if (!rst_n)        up_ff <= 1'b0;
        else if (pfd_reset) up_ff <= 1'b0;
        else               up_ff <= 1'b1;
    end

    always @(posedge clk_vco or negedge rst_n) begin
        if (!rst_n)         down_ff <= 1'b0;
        else if (pfd_reset) down_ff <= 1'b0;
        else                down_ff <= 1'b1;
    end

    wire [7:0] pfd_out = {6'b0, down_ff, up_ff};

    // ==========================================================
    // MODULE 3 (main_sel=011) -- Flip-Flop Study (D-FF + T-FF)
    //
    // sub_in[0] = ff_clk   (manual clock / button)
    // sub_in[1] = ff_d     (D data input)
    // sub_in[2] = ff_t_en  (T toggle enable)
    // sub_in[3] = ff_rst   (async reset, active high)
    //
    // uo_out[0] = D-FF Q
    // uo_out[1] = D-FF ~Q (complement output)
    // uo_out[2] = T-FF Q
    // ==========================================================
    wire ff_clk  = sub_in[0];
    wire ff_d    = sub_in[1];
    wire ff_t_en = sub_in[2];
    wire ff_rst  = sub_in[3];

    reg dff_q;
    always @(posedge ff_clk or posedge ff_rst)
        if (ff_rst) dff_q <= 1'b0;
        else        dff_q <= ff_d;

    reg tff_q;
    always @(posedge ff_clk or posedge ff_rst)
        if (ff_rst) tff_q <= 1'b0;
        else if (ff_t_en) tff_q <= ~tff_q;

    wire [7:0] ff_out = {5'b0, tff_q, ~dff_q, dff_q};

    // ==========================================================
    // MODULE 4 (main_sel=100) -- 4-Bit Binary Counter
    //
    // sub_in[0] = cnt_clk  (manual clock / button)
    // sub_in[1] = cnt_rst  (async reset, active high)
    //
    // uo_out[3:0] = counter value (connect directly to 4 LEDs)
    // ==========================================================
    wire cnt_clk = sub_in[0];
    wire cnt_rst = sub_in[1];

    reg [3:0] counter;
    always @(posedge cnt_clk or posedge cnt_rst)
        if (cnt_rst) counter <= 4'd0;
        else         counter <= counter + 4'd1;

    wire [7:0] cnt_out = {4'b0, counter};

    // ==========================================================
    // MAIN MUX -- route selected module to uo_out[7:0]
    // ==========================================================
    reg [7:0] uo_mux;
    always @(*) begin
        case (main_sel)
            3'd0: uo_mux = gates_out;
            3'd1: uo_mux = ring_out;
            3'd2: uo_mux = pfd_out;
            3'd3: uo_mux = ff_out;
            3'd4: uo_mux = cnt_out;
            default: uo_mux = 8'b0;
        endcase
    end

    assign uo_out = uo_mux;

    // -- Always-live monitoring on uio -------------------------
    // uio[0] = UP (PFD)          always visible for scope probing
    // uio[1] = DOWN (PFD)        always visible for scope probing
    // uio[2] = ring/1024         reliable low-freq measurement tap
    // uio[3] = ring raw          direct oscillator output
    assign uio_out = {4'b0, ring[10], ring_div[9], down_ff, up_ff};
    assign uio_oe  = 8'b00001111;   // bits [3:0] are outputs

endmodule


// =============================================================
// Behavioral stub for RTL simulation only.
// Excluded during synthesis (SYNTHESIS) and gate-level sim (GL_TEST).
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
