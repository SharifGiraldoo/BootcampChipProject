# SPDX-FileCopyrightText: © 2026 Bootcamp IEEE OpenSilicon / IEEE CASS UTP
# SPDX-License-Identifier: Apache-2.0

"""
test.py — cocotb testbench for tt_um_alu7b


Serial protocol (17 capture posedges + 1 posedge for S_CALC):

  Posedge  1.. 7  → Operand A [6:0], LSB first, via ui_in[0]
  Posedge  8..14  → Operand B [6:0], LSB first, via ui_in[0]
  Posedge 15..17  → Opcode   [2:0], LSB first, via ui_in[0]
  Posedge 18      → FSM S_CALC: Done=1, result stable on uo_out

Timing within run_alu():
  reset_dut() ends at FallingEdge → low half-cycle ready for bit[0].
  • bit[0]: place data immediately → RisingEdge (capture)
  • bit[1..16]: FallingEdge → place data → RisingEdge (capture)
  This guarantees exactly 17 capture posedges with no cycle offset.

Operation codes (op[2:0]):
  000=ADD  001=AND  010=OR  011=XOR  100=SUB
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, FallingEdge

#Opcode constants
OP_ADD = 0b000
OP_AND = 0b001
OP_OR  = 0b010
OP_XOR = 0b011
OP_SUB = 0b100

CLK_PERIOD_NS = 20   # 20 ns clock period → 50 MHz



# Helper: reset
# Ends at FallingEdge so the next bit aligns without a cycle offset.

async def reset_dut(dut):
    """Assert active-low reset and leave control at the low half-cycle."""
    dut.rst_n.value  = 0
    dut.ui_in.value  = 0
    dut.uio_in.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await FallingEdge(dut.clk)   # position at low half-cycle



# Helper: serial transmission and result capture

async def run_alu(dut, A, B, op):
    """
    Send 17 serial bits (LSB first) and return (result, done_seen).

    Precondition: call immediately after reset_dut(), which leaves
    control at FallingEdge. bit[0] is presented without an extra
    FallingEdge, preventing a +1 cycle offset.
    """
    # Build bit sequence: A (7 bits) + B (7 bits) + op (3 bits) = 17 bits
    bits  = [(A  >> i) & 1 for i in range(7)]
    bits += [(B  >> i) & 1 for i in range(7)]
    bits += [(op >> i) & 1 for i in range(3)]

    for i, bit in enumerate(bits):
        if i > 0:
            await FallingEdge(dut.clk)  # low half-cycle for bits 1..16
        dut.ui_in.value = int(bit)      # data stable before posedge
        await RisingEdge(dut.clk)       # posedge: DUT captures the bit

    # Wait for S_CALC posedge (exactly 1 cycle after bit 16)
    dut.ui_in.value = 0
    done_seen  = False
    result_val = 0

    for _ in range(4):
        await FallingEdge(dut.clk)
        await RisingEdge(dut.clk)
        if int(dut.uio_out.value) & 0x01:
            done_seen  = True
            result_val = int(dut.uo_out.value)
            break

    return result_val, done_seen



# Main test

@cocotb.test()
async def test_project(dut):
    """Full verification of the 7-bit ALU — all five operations."""
    dut._log.info("Starting tt_um_alu7b tests")

    # Start clock
    clock = Clock(dut.clk, CLK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())

    # Initial reset
    dut._log.info("Applying initial reset")
    dut.ena.value    = 1
    dut.ui_in.value  = 0
    dut.uio_in.value = 0
    dut.rst_n.value  = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await FallingEdge(dut.clk)

    dut._log.info("Running test cases")

    # ── Test table: (A, B, op, expected, description) ────────────────────────
    test_cases = [
        # ── ADD ───────────────────────────────────────────────────────────────
        (20,  30,  OP_ADD, (20  + 30)  & 0xFF, "ADD  20 +  30 =  50"),
        (10,  15,  OP_ADD, (10  + 15)  & 0xFF, "ADD  10 +  15 =  25"),
        (100, 100, OP_ADD, (100 + 100) & 0xFF, "ADD 100 + 100 = 200 (carry on bit 7)"),
        (0,   0,   OP_ADD, 0,                  "ADD   0 +   0 =   0"),
        (127, 1,   OP_ADD, (127 + 1)   & 0xFF, "ADD 127 +   1 = 128"),
        # ── AND ───────────────────────────────────────────────────────────────
        (0b1010101, 0b1100110, OP_AND,
         (0b1010101 & 0b1100110) & 0xFF,        "AND 0x55 & 0x66 = 0x44"),
        (0x7F, 0x00, OP_AND, 0x00,              "AND 0x7F & 0x00 = 0x00"),
        (0x7F, 0x7F, OP_AND, 0x7F,              "AND 0x7F & 0x7F = 0x7F"),
        # ── OR ────────────────────────────────────────────────────────────────
        (0b0101010, 0b0010101, OP_OR,
         (0b0101010 | 0b0010101) & 0xFF,         "OR  0x2A | 0x15 = 0x3F"),
        (0x00, 0x7F, OP_OR, 0x7F,               "OR  0x00 | 0x7F = 0x7F"),
        # ── XOR ───────────────────────────────────────────────────────────────
        (0b1111111, 0b1010101, OP_XOR,
         (0b1111111 ^ 0b1010101) & 0xFF,         "XOR 0x7F ^ 0x55 = 0x2A"),
        (0b1100110, 0b1100110, OP_XOR, 0,        "XOR  A  ^  A  =   0 (self-cancel)"),
        # ── SUB ───────────────────────────────────────────────────────────────
        (50,  20,  OP_SUB, (50  - 20)  & 0xFF,  "SUB  50 -  20 =  30"),
        (77,  77,  OP_SUB, 0,                    "SUB   A -  A  =   0"),
        (10,  30,  OP_SUB, (10  - 30)  & 0xFF,  "SUB  10 -  30 (underflow, two's complement)"),
    ]

    #Run test cases 
    passed = 0
    failed = 0

    for idx, (A, B, op, expected, desc) in enumerate(test_cases):
        await reset_dut(dut)
        result, done = await run_alu(dut, A, B, op)

        ok     = (result == expected) and done
        status = "PASS" if ok else "FAIL"

        dut._log.info(
            f"[{idx+1:02d}] {desc:<50s}  "
            f"got=0x{result:02X}  exp=0x{expected:02X}  "
            f"Done={int(done)}  [{status}]"
        )

        if ok:
            passed += 1
        else:
            failed += 1

        assert done, \
            f"[{idx+1}] {desc}: Done never asserted (uio_out[0] stayed 0)"
        assert result == expected, \
            f"[{idx+1}] {desc}: got=0x{result:02X}, expected=0x{expected:02X}"

    #Summary
    dut._log.info("─" * 62)
    dut._log.info(
        f"SUMMARY: {passed} PASS  /  {failed} FAIL  "
        f"(total {len(test_cases)} cases)"
    )
    dut._log.info("─" * 62)