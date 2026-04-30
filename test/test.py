# SPDX-FileCopyrightText: © 2026 Bootcamp IEEE OpenSilicon / IEEE CASS UTP
# SPDX-License-Identifier: Apache-2.0

"""
test.py — cocotb Testbench for tt_um_alu7b
===========================================

Module Under Test (DUT): tt_um_alu7b
  Instantiated as `user_project` in tb.v.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SERIAL PROTOCOL — tt_um_alu7b
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Rising edge  1 ..  7  → Operand A [6:0], LSB first  (bit_count 0..6)
  Rising edge  8 .. 14  → Operand B [6:0], LSB first  (bit_count 7..13)
  Rising edge 15        → S_CALC: reg_result ← alu_out, done_reg = 1 (1 cycle)

  Opcode: parallel input on ui_in[3:1] = op[2:0], stable throughout the
  operation.  It does NOT need to be serialised through Bit_in.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
TIMING FIX (vs. original test.py)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Original run_alu had "if i > 0: await FallingEdge(dut.clk)" before setting
  ui_in, which skipped the falling-edge setup guard for the first bit (i=0).
  In cocotb 2.0.1, assigning ui_in and immediately awaiting RisingEdge can
  create a delta-cycle race where the DUT samples Bit_in = 0 instead of A[0]
  on that first rising edge, effectively losing the LSB of operand A.

  Fix applied: reset_dut no longer ends with await FallingEdge (the caller
  run_alu will do that), and run_alu always awaits FallingEdge BEFORE driving
  ui_in for every bit (including i=0).  This guarantees correct setup time
  for all 14 serial bits and is compatible with serial_alu_ctrl.v (CNT=6,13).

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
OPERATION TABLE (reference: alu_7b.v)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  000 → ADD  result = {1'b0, A} + {1'b0, B}  [8 bits]  result[7] = carry-out
  001 → AND  result = {1'b0, A & B}                     result[7] = 0 (always)
  010 → OR   result = {1'b0, A | B}                     result[7] = 0 (always)
  011 → XOR  result = {1'b0, A ^ B}                     result[7] = 0 (always)
  100 → SUB  result = {1'b0, A} - {1'b0, B}  [8 bits]  result[7] = borrow (C2)

  Python expected values (A, B ∈ [0, 127]):
    ADD  expected = (A + B) & 0xFF
    SUB  expected = (A - B) & 0xFF   (8-bit two's complement)
    AND  expected = (A & B) & 0x7F   (result[7] always 0)
    OR   expected = (A | B) & 0x7F
    XOR  expected = (A ^ B) & 0x7F
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, FallingEdge

# ── Opcodes — must match alu_7b.v and tt_um_alu7b.v ──────────────────────────
OP_ADD = 0b000
OP_AND = 0b001
OP_OR  = 0b010
OP_XOR = 0b011
OP_SUB = 0b100

CLK_PERIOD_NS = 20   # 20 ns → 50 MHz (TinyTapeout digital I/O maximum)


# ─────────────────────────────────────────────────────────────────────────────
# HELPER: reset_dut
#
# Applies synchronous active-low reset to the DUT.
# Held for 5 clock cycles for robust initialisation.
#
# IMPORTANT TIMING NOTE:
#   This function does NOT await FallingEdge at the end.  The caller (run_alu)
#   is responsible for the first FallingEdge before presenting the first bit.
#   This avoids an extra rising edge between rst_n=1 and the first data bit,
#   which would advance bit_count before any data arrives and corrupt A[0].
#
# Postcondition:
#   - FSM in S_RECV, bit_count = 0, reg_A = 0, reg_B = 0, reg_result = 0
#   - rst_n = 1; clock can be at any phase (run_alu will align via FallingEdge)
# ─────────────────────────────────────────────────────────────────────────────
async def reset_dut(dut):
    """Synchronous active-low reset.  Does NOT end on a falling edge."""
    dut.rst_n.value  = 0
    dut.ui_in.value  = 0
    dut.uio_in.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    # Control returns immediately after rst_n=1, without an extra rising edge.
    # The next await in run_alu will be FallingEdge, which guarantees proper
    # setup time for the first serial bit (A[0]).


# ─────────────────────────────────────────────────────────────────────────────
# HELPER: run_alu
#
# Transmits 14 serial bits (7 for A, 7 for B), LSB first, and polls for Done.
#
# Timing protocol per bit (ALL 14 bits, including bit 0):
#   1. await FallingEdge  — setup window; ui_in is driven stable here
#   2. drive ui_in        — Bit_in = bit[i], op[2:0] = opcode
#   3. await RisingEdge   — DUT captures on the rising edge
#
# This uniform protocol ensures correct setup time for every bit, including
# the first one (i=0).  The original code had "if i > 0: await FallingEdge",
# which could cause a delta-cycle race on i=0 that corrupted A[0].
#
# After 14 rising edges:
#   bit_count == 13 == CNT_B_END → FSM transitions to S_CALC on the NEXT
#   rising edge (the first poll edge).  Done pulses for exactly 1 cycle.
#
# Returns:
#   result (int): captured value of uo_out when Done was observed
#   done_seen (bool): True if Done was asserted within the polling window
# ─────────────────────────────────────────────────────────────────────────────
async def run_alu(dut, A, B, op):
    """
    Transmit 14 serial bits (A [6:0] + B [6:0], LSB first).
    Opcode is applied on ui_in[3:1] as a stable parallel input.
    Always awaits FallingEdge before each bit (including bit 0).
    Returns (result: int, done_seen: bool).
    """
    # Build the 14-bit serial sequence: A LSB-first then B LSB-first
    bits  = [(A >> i) & 1 for i in range(7)]
    bits += [(B >> i) & 1 for i in range(7)]

    for bit in bits:
        await FallingEdge(dut.clk)           # Always: setup window first
        dut.ui_in.value = int(bit) | (op << 1)
        await RisingEdge(dut.clk)            # DUT captures on rising edge

    # Clear Bit_in; hold opcode stable during S_CALC
    dut.ui_in.value = op << 1
    done_seen  = False
    result_val = 0

    # Poll for Done — up to 4 clock cycles
    # S_CALC fires on the first rising edge after bit 13 is captured.
    for _ in range(4):
        await FallingEdge(dut.clk)
        await RisingEdge(dut.clk)
        if int(dut.uio_out.value) & 0x01:
            done_seen  = True
            result_val = int(dut.uo_out.value)
            break

    return result_val, done_seen


# ─────────────────────────────────────────────────────────────────────────────
# MAIN TEST
# ─────────────────────────────────────────────────────────────────────────────
@cocotb.test()
async def test_project(dut):
    """
    Full verification of tt_um_alu7b — 21 test cases.

    Covers all 5 ALU operations (ADD, AND, OR, XOR, SUB) with both nominal
    and boundary scenarios aligned with the Bootcamp specification.

    Protocol: 14 serial bits (7 for A + 7 for B), opcode parallel on
    ui_in[3:1].  All bits are presented on falling edges (setup-time safe).
    """
    dut._log.info("=" * 65)
    dut._log.info("  tt_um_alu7b — Bootcamp IEEE OpenSilicon / IEEE CASS UTP 2026")
    dut._log.info("  Protocol: 14 serial bits (7A + 7B), opcode parallel ui_in[3:1]")
    dut._log.info("  Clock: %d ns (%d MHz)" % (CLK_PERIOD_NS, 1000 // CLK_PERIOD_NS))
    dut._log.info("=" * 65)

    # Start the clock
    clock = Clock(dut.clk, CLK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())

    # Robust initial reset
    dut.ena.value    = 1
    dut.ui_in.value  = 0
    dut.uio_in.value = 0
    dut.rst_n.value  = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    # No FallingEdge here — run_alu will provide it before the first bit.

    dut._log.info("Initial reset complete. Starting test cases.")
    dut._log.info("-" * 65)

    # ─────────────────────────────────────────────────────────────────────────
    # TEST CASE TABLE
    # Format: (A, B, op, expected, description)
    #
    # Expected values computed exactly as the RTL (alu_7b.v):
    #   ADD/SUB : 8-bit zero-extended arithmetic → & 0xFF
    #   AND/OR/XOR : 7-bit result, bit[7] forced 0  → & 0x7F
    # ─────────────────────────────────────────────────────────────────────────
    test_cases = [

        # ══════════════════════════════════════════════════════════════════════
        # BLOCK A — ADDITION (op = 000)
        # RTL reference: 3'b000: result = {1'b0, A} + {1'b0, B}
        # result[7] = carry-out (1 when A + B >= 128)
        # ══════════════════════════════════════════════════════════════════════
        (20,  30,  OP_ADD,
         (20  + 30)  & 0xFF,
         "ADD  20 +  30 =  50   [normal, no carry]"),

        (10,  15,  OP_ADD,
         (10  + 15)  & 0xFF,
         "ADD  10 +  15 =  25   [normal, no carry]"),

        (100, 100, OP_ADD,
         (100 + 100) & 0xFF,
         "ADD 100 + 100 = 0xC8  [carry, result[7]=1]"),

        (0,   0,   OP_ADD,
         0,
         "ADD   0 +   0 = 0x00  [zero case]"),

        (127, 1,   OP_ADD,
         (127 + 1)   & 0xFF,
         "ADD 127 +   1 = 0x80  [7-bit limit, carry]"),

        (127, 127, OP_ADD,
         (127 + 127) & 0xFF,
         "ADD 127 + 127 = 0xFE  [both max, carry]"),

        # ══════════════════════════════════════════════════════════════════════
        # BLOCK B — BITWISE AND (op = 001)
        # RTL reference: 3'b001: result = {1'b0, A & B}
        # result[7] = 0 always
        # ══════════════════════════════════════════════════════════════════════
        (0b1010101, 0b1100110, OP_AND,
         (0b1010101 & 0b1100110) & 0x7F,
         "AND 0x55 & 0x66 = 0x44 [partial mask]"),

        (0x7F, 0x00, OP_AND,
         0x00,
         "AND 0x7F & 0x00 = 0x00 [annihilation]"),

        (0x7F, 0x7F, OP_AND,
         0x7F,
         "AND 0x7F & 0x7F = 0x7F [identity]"),

        (0b0101010, 0b1010101, OP_AND,
         0x00,
         "AND 0x2A & 0x55 = 0x00 [crossed alternating, always 0]"),

        # ══════════════════════════════════════════════════════════════════════
        # BLOCK C — BITWISE OR (op = 010)
        # RTL reference: 3'b010: result = {1'b0, A | B}
        # result[7] = 0 always
        # ══════════════════════════════════════════════════════════════════════
        (0b0101010, 0b0010101, OP_OR,
         (0b0101010 | 0b0010101) & 0x7F,
         "OR  0x2A | 0x15 = 0x3F [complementary patterns]"),

        (0x00, 0x7F, OP_OR,
         0x7F,
         "OR  0x00 | 0x7F = 0x7F [OR identity]"),

        (0x7F, 0x7F, OP_OR,
         0x7F,
         "OR  0x7F | 0x7F = 0x7F [both operands at max]"),

        # ══════════════════════════════════════════════════════════════════════
        # BLOCK D — BITWISE XOR (op = 011)
        # RTL reference: 3'b011: result = {1'b0, A ^ B}
        # result[7] = 0 always
        # ══════════════════════════════════════════════════════════════════════
        (0b1111111, 0b1010101, OP_XOR,
         (0b1111111 ^ 0b1010101) & 0x7F,
         "XOR 0x7F ^ 0x55 = 0x2A [difference]"),

        (0b1100110, 0b1100110, OP_XOR,
         0x00,
         "XOR  A   ^  A   = 0x00 [self-cancellation]"),

        (0b1010101, 0b0101010, OP_XOR,
         (0b1010101 ^ 0b0101010) & 0x7F,
         "XOR 0x55 ^ 0x2A = 0x7F [alternating — all bits set]"),

        (0x7F, 0x00, OP_XOR,
         0x7F,
         "XOR 0x7F ^ 0x00 = 0x7F [XOR identity]"),

        # ══════════════════════════════════════════════════════════════════════
        # BLOCK E — SUBTRACTION (op = 100)
        # RTL reference: 3'b100: result = {1'b0, A} - {1'b0, B}
        # result[7] = borrow flag (1 when A < B; negative result in two's C)
        # ══════════════════════════════════════════════════════════════════════
        (50,  20,  OP_SUB,
         (50  - 20) & 0xFF,
         "SUB  50 -  20 =  30   [positive result, no borrow]"),

        (77,  77,  OP_SUB,
         0x00,
         "SUB  77 -  77 = 0x00  [A equals B — zero result]"),

        (10,  30,  OP_SUB,
         (10  - 30) & 0xFF,
         "SUB  10 -  30 = 0xEC  [underflow, borrow, two's complement]"),

        (127, 0,   OP_SUB,
         0x7F,
         "SUB 127 -   0 = 0x7F  [B = 0, no borrow]"),

    ]

    # ─────────────────────────────────────────────────────────────────────────
    # EXECUTION AND VERIFICATION LOOP
    # ─────────────────────────────────────────────────────────────────────────
    passed   = 0
    failed   = 0
    failures = []

    for idx, (A, B, op, expected, desc) in enumerate(test_cases):

        await reset_dut(dut)
        result, done = await run_alu(dut, A, B, op)

        ok     = (result == expected) and done
        status = "PASS" if ok else "FAIL"

        dut._log.info(
            "[%02d] %-52s  got=0x%02X  exp=0x%02X  Done=%d  [%s]"
            % (idx + 1, desc, result, expected, int(done), status)
        )

        if ok:
            passed += 1
        else:
            failed += 1
            failures.append((idx + 1, desc, result, expected, done))

    # ─────────────────────────────────────────────────────────────────────────
    # FINAL SUMMARY
    # ─────────────────────────────────────────────────────────────────────────
    dut._log.info("=" * 65)
    dut._log.info(
        "SUMMARY: %d PASS  /  %d FAIL  (total %d cases)"
        % (passed, failed, len(test_cases))
    )

    if failures:
        dut._log.error("FAILED CASES:")
        for num, desc, got, exp, d in failures:
            dut._log.error(
                "  [%02d] %s → got=0x%02X  exp=0x%02X  Done=%s  diff_bits=0x%02X"
                % (num, desc, got, exp, d, got ^ exp)
            )

    dut._log.info("=" * 65)

    # ─────────────────────────────────────────────────────────────────────────
    # INDIVIDUAL ASSERTIONS (reported by pytest in results.xml)
    # ─────────────────────────────────────────────────────────────────────────
    for num, desc, got, exp, d in failures:
        assert d, (
            "[%02d] %s: uio_out[0] (Done) was never asserted. "
            "Check: 14 bits transmitted, LSB-first protocol, "
            "FSM transition S_RECV → S_CALC at bit_count == CNT_B_END (13)."
            % (num, desc)
        )
        assert got == exp, (
            "[%02d] %s: incorrect result. "
            "got=0x%02X  expected=0x%02X  error_bits=0x%02X"
            % (num, desc, got, exp, got ^ exp)
        )