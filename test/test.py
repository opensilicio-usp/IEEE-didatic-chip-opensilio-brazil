# SPDX-FileCopyrightText: 2025 USP OpenSilicio Group (IEEE)
# SPDX-License-Identifier: Apache-2.0
#
# Cocotb testbench for tt_um_usp_didactic
# Covers: Logic Gates, PFD ref-leads, PFD VCO-leads, Flip-Flops, Counter
#
# Pin mapping:
#   ui_in[7:5] = main_sel  (000=gates, 001=ring, 010=PFD, 011=FF, 100=counter)
#   ui_in[4:0] = sub_in    (meaning depends on module -- see project.v)

import cocotb
from cocotb.triggers import Timer

from cocotb.clock import Clock 


# ---------------------------------------------------------------------------
# Input helpers
# ---------------------------------------------------------------------------

def set_ui(dut, main_sel=0, b0=0, b1=0, b2=0, b3=0, b4=0):
    """Pack ui_in: main_sel into [7:5], sub-bits into [4:0]."""
    dut.ui_in.value = (
        (b0      & 0x1)       |
        ((b1     & 0x1) << 1) |
        ((b2     & 0x1) << 2) |
        ((b3     & 0x1) << 3) |
        ((b4     & 0x1) << 4) |
        ((main_sel & 0x7) << 5)
    )


def set_gates(dut, A=0, B=0, sel=0):
    """main_sel=000: A=b0, B=b1, gate_sel=b4:b2."""
    set_ui(dut, main_sel=0,
           b0=A, b1=B,
           b2=(sel >> 0) & 1, b3=(sel >> 1) & 1, b4=(sel >> 2) & 1)


def set_pfd(dut, clk_ref=0, clk_vco=0):
    """main_sel=010: clk_ref=b0, clk_vco=b1."""
    set_ui(dut, main_sel=2, b0=clk_ref, b1=clk_vco)


def set_ff(dut, clk=0, d=0, t_en=0, rst=0):
    """main_sel=011: ff_clk=b0, ff_d=b1, ff_t_en=b2, ff_rst=b3."""
    set_ui(dut, main_sel=3, b0=clk, b1=d, b2=t_en, b3=rst)


def set_cnt(dut, clk=0, rst=0):
    """main_sel=100: cnt_clk=b0, cnt_rst=b1."""
    set_ui(dut, main_sel=4, b0=clk, b1=rst)


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_logic_gates(dut):
    """Verify all 7 gates for every (A, B) combination (main_sel=000)."""

    dut._log.info("Logic gate test - reset")
    dut.rst_n.value  = 0
    dut.ena.value    = 1
    dut.uio_in.value = 0
    set_gates(dut)
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
                set_gates(dut, A=A, B=B, sel=sel)
                await Timer(5, units='ns')

                got = int(dut.uo_out.value) & 0x1   # uo_out[0] = selected gate
                exp = fn(A, B)
                assert got == exp, (
                    "Gate sel=%d A=%d B=%d: expected %d, got %d" % (sel, A, B, exp, got)
                )

    dut._log.info("Logic gate test - PASSED")


@cocotb.test()
async def test_pfd_ref_leads(dut):
    """UP should pulse when clk_ref rises before clk_vco (main_sel=010)."""

    dut._log.info("PFD test - clk_ref leads")
    dut.rst_n.value  = 0
    dut.ena.value    = 1
    dut.uio_in.value = 0
    set_pfd(dut)
    await Timer(20, units='ns')
    dut.rst_n.value = 1
    await Timer(5, units='ns')

    # Apply rising edge on clk_ref only
    set_pfd(dut, clk_ref=1, clk_vco=0)
    await Timer(5, units='ns')

    uo = int(dut.uo_out.value)
    assert (uo & 0x1) == 1, "UP (uo_out[0]) should be 1, got %d" % (uo & 0x1)
    assert (uo & 0x2) == 0, "DOWN (uo_out[1]) should be 0, got %d" % ((uo >> 1) & 0x1)

    dut._log.info("PFD ref-leads test - PASSED")


@cocotb.test()
async def test_pfd_vco_leads(dut):
    """DOWN should pulse when clk_vco rises before clk_ref (main_sel=010)."""

    dut._log.info("PFD test - clk_vco leads")
    dut.rst_n.value  = 0
    dut.ena.value    = 1
    dut.uio_in.value = 0
    set_pfd(dut)
    await Timer(20, units='ns')
    dut.rst_n.value = 1
    await Timer(5, units='ns')

    # Apply rising edge on clk_vco only
    set_pfd(dut, clk_ref=0, clk_vco=1)
    await Timer(5, units='ns')

    uo = int(dut.uo_out.value)
    assert (uo & 0x2) == 2, "DOWN (uo_out[1]) should be 1, got %d" % ((uo >> 1) & 0x1)
    assert (uo & 0x1) == 0, "UP (uo_out[0]) should be 0, got %d" % (uo & 0x1)

    dut._log.info("PFD VCO-leads test - PASSED")


@cocotb.test()
async def test_flipflops(dut):
    """Verify D-FF and T-FF behaviour (main_sel=011)."""

    dut._log.info("Flip-flop test - reset")
    dut.rst_n.value  = 0
    dut.ena.value    = 1
    dut.uio_in.value = 0
    set_ff(dut, rst=1)          # hold FF reset high during system reset
    await Timer(20, units='ns')
    dut.rst_n.value = 1
    await Timer(5, units='ns')

    # Release FF reset -- Q=0, ~Q=1, T-Q=0
    set_ff(dut, clk=0, d=0, t_en=0, rst=0)
    await Timer(5, units='ns')

    uo = int(dut.uo_out.value)
    assert (uo & 0x1) == 0, "D-FF Q  should be 0 after reset, got %d" % (uo & 0x1)
    assert (uo & 0x2) == 2, "D-FF ~Q should be 1 after reset, got %d" % ((uo >> 1) & 0x1)
    assert (uo & 0x4) == 0, "T-FF Q  should be 0 after reset, got %d" % ((uo >> 2) & 0x1)

    # Clock D=1 into the D-FF
    set_ff(dut, clk=0, d=1, t_en=0, rst=0)
    await Timer(5, units='ns')
    set_ff(dut, clk=1, d=1, t_en=0, rst=0)   # rising edge
    await Timer(5, units='ns')

    uo = int(dut.uo_out.value)
    assert (uo & 0x1) == 1, "D-FF Q  should be 1 after clocking D=1, got %d" % (uo & 0x1)
    assert (uo & 0x2) == 0, "D-FF ~Q should be 0 after clocking D=1, got %d" % ((uo >> 1) & 0x1)

    # T-FF: first toggle (T=1, rising clock edge -> Q: 0->1)
    set_ff(dut, clk=0, d=1, t_en=1, rst=0)
    await Timer(5, units='ns')
    set_ff(dut, clk=1, d=1, t_en=1, rst=0)   # rising edge
    await Timer(5, units='ns')

    uo = int(dut.uo_out.value)
    assert (uo & 0x4) == 4, "T-FF Q should be 1 after first toggle, got %d" % ((uo >> 2) & 0x1)

    # T-FF: second toggle (Q: 1->0)
    set_ff(dut, clk=0, d=1, t_en=1, rst=0)
    await Timer(5, units='ns')
    set_ff(dut, clk=1, d=1, t_en=1, rst=0)
    await Timer(5, units='ns')

    uo = int(dut.uo_out.value)
    assert (uo & 0x4) == 0, "T-FF Q should be 0 after second toggle, got %d" % ((uo >> 2) & 0x1)

    # D-FF async reset
    set_ff(dut, clk=0, d=1, t_en=0, rst=1)   # assert reset
    await Timer(5, units='ns')

    uo = int(dut.uo_out.value)
    assert (uo & 0x1) == 0, "D-FF Q should be 0 after async reset, got %d" % (uo & 0x1)
    assert (uo & 0x2) == 2, "D-FF ~Q should be 1 after async reset, got %d" % ((uo >> 1) & 0x1)

    dut._log.info("Flip-flop test - PASSED")


@cocotb.test()
async def test_counter(dut):
    """Verify 4-bit binary counter counts 0-15 and resets (main_sel=100)."""

    dut._log.info("Counter test - reset")
    dut.rst_n.value  = 0
    dut.ena.value    = 1
    dut.uio_in.value = 0
    set_cnt(dut, clk=0, rst=1)   # hold counter reset
    await Timer(20, units='ns')
    dut.rst_n.value = 1
    await Timer(5, units='ns')

    # Release reset
    set_cnt(dut, clk=0, rst=0)
    await Timer(5, units='ns')

    uo = int(dut.uo_out.value)
    assert (uo & 0xF) == 0, "Counter should be 0 after reset, got %d" % (uo & 0xF)

    # Clock the counter 15 times and verify each step
    for expected in range(1, 16):
        set_cnt(dut, clk=0, rst=0)
        await Timer(5, units='ns')
        set_cnt(dut, clk=1, rst=0)   # rising edge
        await Timer(5, units='ns')

        uo = int(dut.uo_out.value)
        assert (uo & 0xF) == expected, (
            "Counter should be %d, got %d" % (expected, uo & 0xF)
        )

    # Async reset mid-count
    set_cnt(dut, clk=0, rst=1)
    await Timer(5, units='ns')

    uo = int(dut.uo_out.value)
    assert (uo & 0xF) == 0, "Counter should be 0 after mid-count reset, got %d" % (uo & 0xF)

    dut._log.info("Counter test - PASSED")













# ---------------------------------------------------------------------------
# Helper Class for I2C Master Emulation
# ---------------------------------------------------------------------------
class I2CBus:
    """Emulates an I2C Master with open-drain SDA handling via uio_oe."""
    def __init__(self, dut, scl_half_period_ns=500):
        self.dut = dut
        self.sda = 1
        self.scl = 1
        self.delay = scl_half_period_ns # 500ns half-period = 1us full period = 1MHz I2C clock

    async def update(self):
        """Resolves the open-drain bus state and drives uio_in."""
        # Check if the slave (DUT) is pulling SDA low (uio_oe[0] == 1 means driving 0)
        slave_pull = self.dut.uio_oe[0].value.integer if self.dut.uio_oe[0].value.is_resolvable else 0
        
        # Wired-AND: Bus is 0 if either Master OR Slave pulls it low. Otherwise 1 (pull-up).
        bus_sda = 0 if (self.sda == 0 or slave_pull == 1) else 1
        bus_scl = self.scl # We assume the slave doesn't stretch the SCL clock
        
        # Read current uio_in to avoid overwriting other bits
        val = self.dut.uio_in.value.integer if self.dut.uio_in.value.is_resolvable else 0
        
        # Mask out bits 0 and 1, then set them to our new I2C bus state
        val = (val & ~0x3) | ((bus_scl & 1) << 1) | (bus_sda & 1)
        self.dut.uio_in.value = val

    async def wait(self):
        await Timer(self.delay, units='ns')

    async def start(self):
        self.sda = 1
        self.scl = 1
        await self.update()
        await self.wait()
        
        # START condition: SDA goes low while SCL is high
        self.sda = 0
        await self.update()
        await self.wait()
        
        self.scl = 0
        await self.update()
        await self.wait()

    async def stop(self):
        self.sda = 0
        self.scl = 1
        await self.update()
        await self.wait()
        
        # STOP condition: SDA goes high while SCL is high
        self.sda = 1
        await self.update()
        await self.wait()

    async def write_bit(self, bit):
        self.sda = bit
        await self.update()
        await self.wait()
        
        self.scl = 1
        await self.update()
        await self.wait()
        
        self.scl = 0
        await self.update()
        await self.wait()

    async def read_bit(self):
        self.sda = 1 # Master releases the SDA line
        await self.update()
        await self.wait()
        
        self.scl = 1
        await self.update()
        
        # Wait a tiny bit for the slave to react and drive the line, then sample it
        await Timer(100, units='ns')
        await self.update()
        
        slave_pull = self.dut.uio_oe[0].value.integer if self.dut.uio_oe[0].value.is_resolvable else 0
        bit_val = 0 if slave_pull == 1 else 1
        
        # Finish the half-clock period
        await Timer(self.delay - 100, units='ns')
        
        self.scl = 0
        await self.update()
        await self.wait()
        return bit_val

    async def write_byte(self, byte_val):
        for i in range(7, -1, -1):
            await self.write_bit((byte_val >> i) & 1)
        return await self.read_bit() # Return the ACK bit (0 = ACK, 1 = NACK)

    async def read_byte(self, ack=True):
        byte_val = 0
        for i in range(8):
            byte_val = (byte_val << 1) | await self.read_bit()
        
        # Master sends ACK (0) to continue, or NACK (1) to stop
        await self.write_bit(0 if ack else 1)
        return byte_val


# ---------------------------------------------------------------------------
# I2C Expander Loopback Test
# ---------------------------------------------------------------------------
@cocotb.test()
async def test_i2c_expander_loopback(dut):
    """Write 0xAA to Expander 0 (addr 0x08), read back from Expander 1 (addr 0x09)."""
    
    # 1. Start the 50MHz system clock (20ns period) in the background
    cocotb.start_soon(Clock(dut.clk, 20, units="ns").start())

    dut._log.info("Resetting DUT")
    dut.rst_n.value = 0
    dut.ena.value = 1
    # Initialize uio_in. The I2C module ignores ui_in main_sel.
    dut.uio_in.value = 0 
    await Timer(100, units="ns")
    dut.rst_n.value = 1
    await Timer(100, units="ns")
    
    # 2. Instantiate the I2C Master bus (1MHz clock speed to safely clear the 50MHz internal sampling)
    i2c = I2CBus(dut, scl_half_period_ns=500)
    await i2c.update()
    await Timer(1, units="us")
    
    # ==========================================
    # 3. WRITE PHASE (To Expander 0 -> Address 0x08)
    # ==========================================
    dut._log.info("Sending I2C START (Write Phase)")
    await i2c.start()
    
    # I2C Slave Address format: 7-bit address + 1-bit W/R (Write = 0)
    addr_write = (0x08 << 1) | 0
    ack = await i2c.write_byte(addr_write)
    assert ack == 0, f"Expander 0 (0x08) did NOT ACK its address! Got {ack}"
    
    dut._log.info("Writing data 0xAA to Expander 0...")
    ack = await i2c.write_byte(0xAA)
    assert ack == 0, f"Expander 0 did NOT ACK data byte 0xAA! Got {ack}"
    
    await i2c.stop()
    
    # Wait for the internal 8-bit register to latch the data (needs system clock edges)
    await Timer(100, units="ns")
    
    # ==========================================
    # 4. READ PHASE (From Expander 1 -> Address 0x09)
    # ==========================================
    dut._log.info("Sending I2C START (Read Phase)")
    await i2c.start()
    
    # I2C Slave Address format: 7-bit address + 1-bit W/R (Read = 1)
    addr_read = (0x09 << 1) | 1
    ack = await i2c.write_byte(addr_read)
    assert ack == 0, f"Expander 1 (0x09) did NOT ACK its address! Got {ack}"
    
    dut._log.info("Reading data from Expander 1...")
    # Master sends NACK (ack=False) after the first byte to signal end of read
    read_val = await i2c.read_byte(ack=False) 
    
    await i2c.stop()
    
    # ==========================================
    # 5. VERIFICATION
    # ==========================================
    dut._log.info(f"Loopback read value: {hex(read_val)}")
    assert read_val == 0xAA, f"Loopback Failed! Expected 0xAA, got {hex(read_val)}"
    
    dut._log.info("I2C Expander Loopback test - PASSED!")
