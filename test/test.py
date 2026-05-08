# SPDX-FileCopyrightText: 2025 USP OpenSilicio Group (IEEE)
# SPDX-License-Identifier: Apache-2.0
#
# Cocotb testbench for tt_um_usp_didactic
# Covers: Logic Gate Library, PFD ref-leads, PFD VCO-leads
#
# Run with:  cd test && make

import cocotb
from cocotb.triggers import Timer


def set_inputs(dut, A=0, B=0, sel=0, clk_ref=0, clk_vco=0, ring_en=0):
    """Pack all inputs into the 8-bit ui_in bus."""
    dut.ui_in.value = (
        (clk_ref  & 0x1)       |
        ((clk_vco & 0x1) << 1) |
        ((sel     & 0x7) << 2) |
        ((A       & 0x1) << 5) |
        ((B       & 0x1) << 6) |
        ((ring_en & 0x1) << 7)
    )


@cocotb.test()
async def test_logic_gates(dut):
    """Verify all 7 gates for every (A, B) input combination."""

    dut._log.info("Logic gate test - reset")
    dut.rst_n.value  = 0
    dut.ena.value    = 1
    dut.uio_in.value = 0
    set_inputs(dut)
    await Timer(10, units='ns')
    dut.rst_n.value = 1
    await Timer(2, units='ns')

    # Reference implementations for each gate (sel 0-6)
    gate_fns = [
        lambda a, b: int(not a),          # 0: NOT(A)
        lambda a, b: a & b,               # 1: AND
        lambda a, b: a | b,               # 2: OR
        lambda a, b: a ^ b,               # 3: XOR
        lambda a, b: int(not (a & b)),    # 4: NAND
        lambda a, b: int(not (a | b)),    # 5: NOR
        lambda a, b: int(not (a ^ b)),    # 6: XNOR
    ]

    for A in [0, 1]:
        for B in [0, 1]:
            for sel, fn in enumerate(gate_fns):
                set_inputs(dut, A=A, B=B, sel=sel)
                await Timer(5, units='ns')

                got = int(dut.uo_out.value) & 0x1   # uo_out[0] = selected gate
                exp = fn(A, B)
                assert got == exp, (
                    "Gate sel=%d A=%d B=%d: expected %d, got %d" % (sel, A, B, exp, got)
                )

    dut._log.info("Logic gate test - PASSED")


@cocotb.test()
async def test_pfd_ref_leads(dut):
    """UP should pulse when clk_ref rises before clk_vco."""

    dut._log.info("PFD test - clk_ref leads")
    dut.rst_n.value  = 0
    dut.ena.value    = 1
    dut.uio_in.value = 0
    dut.ui_in.value  = 0
    await Timer(20, units='ns')
    dut.rst_n.value = 1
    await Timer(5, units='ns')

    # Apply rising edge on clk_ref only (ui_in[0]=1, ui_in[1]=0)
    set_inputs(dut, clk_ref=1, clk_vco=0)
    await Timer(5, units='ns')

    uio = int(dut.uio_out.value)
    assert (uio & 0x1) == 1, "UP (uio_out[0]) should be 1, got %d" % (uio & 0x1)
    assert (uio & 0x2) == 0, "DOWN (uio_out[1]) should be 0, got %d" % ((uio >> 1) & 0x1)

    dut._log.info("PFD ref-leads test - PASSED")


@cocotb.test()
async def test_pfd_vco_leads(dut):
    """DOWN should pulse when clk_vco rises before clk_ref."""

    dut._log.info("PFD test - clk_vco leads")
    dut.rst_n.value  = 0
    dut.ena.value    = 1
    dut.uio_in.value = 0
    dut.ui_in.value  = 0
    await Timer(20, units='ns')
    dut.rst_n.value = 1
    await Timer(5, units='ns')

    # Apply rising edge on clk_vco only (ui_in[0]=0, ui_in[1]=1)
    set_inputs(dut, clk_ref=0, clk_vco=1)
    await Timer(5, units='ns')

    uio = int(dut.uio_out.value)
    assert (uio & 0x2) == 2, "DOWN (uio_out[1]) should be 1, got %d" % ((uio >> 1) & 0x1)
    assert (uio & 0x1) == 0, "UP (uio_out[0]) should be 0, got %d" % (uio & 0x1)

    dut._log.info("PFD VCO-leads test - PASSED")
