## How it works

Three independent modules share the tile simultaneously — there is no mux between them. Each module uses its own dedicated pins and operates at all times.

**Module 1 — Logic Gate Library**

Inputs A (`ui[5]`) and B (`ui[6]`) are fed to seven combinational gates: NOT, AND, OR, XOR, NAND, NOR, XNOR. All seven gate outputs are always live on `uo[7:1]`, allowing a logic analyzer to capture all results simultaneously. `uo[0]` mirrors whichever gate is selected by the 3-bit selector `ui[4:2]`. This arrangement lets students compare propagation delays across all gates in a single measurement sweep.

**Module 2 — 11-Stage Ring Oscillator**

An 11-stage inverter ring built from explicit `sky130_fd_sc_hd__inv_1` standard-cell instantiations (with `(* keep = "true" *)` attributes to prevent Yosys from optimizing the chain away). When `ui[7]` is high, the ring oscillates freely. The raw output of the last inverter is routed to the analog pad `ua[0]` for direct oscilloscope measurement — expected frequency is approximately 200 MHz to 1.5 GHz depending on process corner, supply voltage, and temperature. A 10-bit binary counter divides the ring frequency by 1024 and outputs the MSB on `uio[2]`, providing a lower-frequency signal measurable with basic equipment.

**Module 3 — Phase-Frequency Detector (PFD)**

A classic dual flip-flop PFD with AND-based asynchronous reset — the standard topology used in real PLL designs. `clk_ref` (`ui[0]`) and `clk_vco` (`ui[1]`) each drive one D flip-flop. When `clk_ref` leads, the UP flip-flop sets (`uio[0]` goes high) while DOWN remains low. When `clk_vco` leads, the DOWN flip-flop sets (`uio[1]` goes high). When both flip-flops are high simultaneously, their AND gate fires an asynchronous reset, creating the characteristic narrow dead-zone pulse. This PFD output can drive a charge pump to form a complete PLL.

## How to test

**Logic Gate Library**

Set A on `ui[5]` and B on `ui[6]` using DIP switches or a microcontroller. Step through the 8 selector values on `ui[4:2]` (0–6 are valid; 7 outputs 0). Read `uo[0]` for the selected gate result. All seven gate outputs are simultaneously visible on `uo[7:1]`. For propagation delay measurement, apply a step function on A and probe `uo[2]` (AND output) with an oscilloscope.

**Ring Oscillator**

Set `ui[7]` = HIGH. Connect an oscilloscope probe directly to the `ua[0]` pad (use 50Ω termination if available). Measure the oscillation frequency. For a VDD-vs-frequency characterization exercise, vary VDD from 1.6 V to 1.9 V in 0.1 V steps and record frequency at each voltage — this demonstrates the relationship between supply voltage and inverter switching speed in 130 nm CMOS. Compare measured results against SPICE simulation. For basic equipment, monitor `uio[2]` which outputs the ring frequency divided by 1024.

**Phase-Frequency Detector**

Apply two square waves to `ui[0]` (clk_ref) and `ui[1]` (clk_vco) from a two-channel function generator with phase control. Observe `uio[0]` (UP) and `uio[1]` (DOWN) on an oscilloscope. Increase the phase difference from 0° to 180° and verify that the UP pulse width scales linearly with phase error — confirming the PFD's behavior as a linear phase comparator. To observe the averaged control voltage, add an external RC low-pass filter across the UP or DOWN output.

## External hardware

- Oscilloscope with ≥ 2 GHz bandwidth (recommended) for ring oscillator measurement on `ua[0]`
- Two-channel function generator with phase control for PFD testing
- 50Ω coaxial probe or termination for `ua[0]` ring oscillator output
- Optional RC low-pass filter (e.g., 1 kΩ + 100 nF) for PFD charge-pump emulation
- TT Demoboard (PCB supplied via shuttle coupon)
