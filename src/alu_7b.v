/*
 * alu_7b.v — 7-bit Arithmetic Logic Unit (Combinational)
 *
 * Bootcamp IC Design & Fabrication — IEEE OpenSilicon / IEEE CASS UTP 2026
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * DESCRIPTION
 * ─────────────────────────────────────────────────────────────────────────────
 * Pure combinational leaf module. Receives two 7-bit unsigned operands (A, B)
 * and a 3-bit operation code (op), and delivers an 8-bit result combinationally.
 *
 * Bit [7] of the result carries arithmetic overflow information:
 *   - Addition    : result[7] = carry-out (result >= 128)
 *   - Subtraction : result[7] = borrow    (A < B; two's complement representation)
 *   - Logic ops   : result[7] = 0         (always, output bounded to 7 bits)
 *
 * This module has no registers, no clock, and no reset. Its output is purely
 * a function of its inputs and changes within the combinational propagation delay.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * OPERATION TABLE (op[2:0])
 * ─────────────────────────────────────────────────────────────────────────────
 *   000 → ADD   result = {1'b0, A} + {1'b0, B}    bit[7] = carry-out
 *   001 → AND   result = {1'b0, A & B}             bit[7] = 0 (always)
 *   010 → OR    result = {1'b0, A | B}             bit[7] = 0 (always)
 *   011 → XOR   result = {1'b0, A ^ B}             bit[7] = 0 (always)
 *   100 → SUB   result = {1'b0, A} - {1'b0, B}    bit[7] = borrow (two's complement)
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * ARITHMETIC NOTES
 * ─────────────────────────────────────────────────────────────────────────────
 * All operands are zero-extended to 8 bits ({1'b0, A} and {1'b0, B}) before
 * arithmetic so that the carry/borrow propagates naturally into bit[7].
 *
 * ADD example: A=100, B=100 → {1'b0,100} + {1'b0,100} = 200 = 8'hC8
 *              result[7] = 1 (carry), result[6:0] = 72
 *
 * SUB example: A=10, B=30  → {1'b0,10} - {1'b0,30} = -20 in two's complement
 *              = 8'hEC = 236d, result[7] = 1 (borrow)
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * NOTE ON `timescale
 * ─────────────────────────────────────────────────────────────────────────────
 * `timescale is intentionally omitted from all synthesisable RTL files.
 * It is only meaningful in simulation and is declared in the testbench (tb.v).
 * Verilator issues a TIMESCALEMOD warning when some modules in a compilation
 * unit declare `timescale and others (e.g. SKY130 PDK black-box models) do not.
 * The suppress/restore directives below silence that warning on the PDK side;
 * this file simply does not declare `timescale at all, which is the correct
 * practice for synthesisable RTL.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

/* verilator lint_off TIMESCALEMOD */
`default_nettype none

module alu_7b (
    input  wire [6:0] A,       // Operand A — 7-bit unsigned
    input  wire [6:0] B,       // Operand B — 7-bit unsigned
    input  wire [2:0] op,      // Operation code (see operation table above)
    output reg  [7:0] result   // 8-bit result: result[6:0] = data, result[7] = carry/borrow
);

    
    // Combinational always block: result is a pure function of {A, B, op}.
    // Uses a priority-encoded case statement for clean synthesis to a MUX tree.
    // The default branch drives result to 0 to avoid inferred latches and
    // ensures clean synthesis with Yosys / LibreLane.
   
    always @(*) begin
        case (op)
            3'b000: result = {1'b0, A} + {1'b0, B};  // ADD — result[7] = carry-out
            3'b001: result = {1'b0, A & B};            // AND — result[7] = 0
            3'b010: result = {1'b0, A | B};            // OR  — result[7] = 0
            3'b011: result = {1'b0, A ^ B};            // XOR — result[7] = 0
            3'b100: result = {1'b0, A} - {1'b0, B};   // SUB — result[7] = borrow (two's C)
            default: result = 8'b0;                    // Safety default: op codes 101-111
        endcase
    end

endmodule
/* verilator lint_on TIMESCALEMOD */