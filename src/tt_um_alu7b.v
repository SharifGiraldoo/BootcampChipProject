/*
 * tt_um_alu7b.v — TinyTapeout Top-Level Module for the 7-bit Serial→Parallel ALU
 *
 * Bootcamp IC Design & Fabrication — IEEE OpenSilicon / IEEE CASS UTP 2026
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * DESCRIPTION
 * ─────────────────────────────────────────────────────────────────────────────
 * Top-level TinyTapeout wrapper that maps the standard TinyTapeout port
 * interface (ui_in, uo_out, uio_in, uio_out, uio_oe, ena, clk, rst_n) to the
 * serial_alu_ctrl module, which in turn instantiates the combinational alu_7b.
 *
 * This module contains NO logic of its own — it performs only port mapping,
 * signal routing, and unused-pin tie-off. All functional behaviour is in
 * serial_alu_ctrl and alu_7b.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * PIN MAPPING
 * ─────────────────────────────────────────────────────────────────────────────
 *
 *   Input  ui_in[0]   → Bit_in  : Serial data input, LSB first
 *   Input  ui_in[3:1] → op[2:0] : Operation code (parallel, stable during op)
 *   Input  ui_in[7:4] → unused  : Tied to _unused wire (suppresses linter warnings)
 *
 *   Output uo_out[7:0] → Data_out[7:0] : 8-bit parallel result
 *                         uo_out[7] = carry (ADD) or borrow (SUB)
 *
 *   Output uio_out[0]  → Done   : One-cycle high pulse when result is ready
 *   Output uio_out[7:1]→ 0      : Always driven low (unused pins)
 *   Output uio_oe      → 8'b0000_0001 : Only uio[0] is configured as output
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * SERIAL INPUT PROTOCOL
 * ─────────────────────────────────────────────────────────────────────────────
 *
 *   Rising edge  1 ..  7  → Operand A [6:0], LSB first  (bit_count 0..6)
 *   Rising edge  8 .. 14  → Operand B [6:0], LSB first  (bit_count 7..13)
 *   Rising edge 15        → FSM S_CALC: result latched, Done = 1 for one cycle
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * OPERATION TABLE (op = ui_in[3:1])
 * ─────────────────────────────────────────────────────────────────────────────
 *   3'b000 → ADD   uo_out = A + B           uo_out[7] = carry-out
 *   3'b001 → AND   uo_out = {1'b0, A & B}   uo_out[7] = 0
 *   3'b010 → OR    uo_out = {1'b0, A | B}   uo_out[7] = 0
 *   3'b011 → XOR   uo_out = {1'b0, A ^ B}   uo_out[7] = 0
 *   3'b100 → SUB   uo_out = A - B           uo_out[7] = borrow (two's complement)
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * DESIGN CONSTRAINTS
 * ─────────────────────────────────────────────────────────────────────────────
 *   Maximum clock frequency : 50 MHz (TinyTapeout digital I/O limit)
 *   Clock period            : 20 ns
 *   Technology              : SkyWater 130 nm (sky130A PDK)
 *   Tile size               : 1×1 (160 × 100 µm)
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * NOTE ON `timescale
 * ─────────────────────────────────────────────────────────────────────────────
 * `timescale is intentionally omitted from all synthesisable RTL files.
 * The Verilator TIMESCALEMOD warning suppression below prevents false warnings
 * when this file is compiled alongside SKY130 PDK black-box models that also
 * lack a `timescale directive.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

/* verilator lint_off TIMESCALEMOD */
`default_nettype none

module tt_um_alu7b (
    // ── Dedicated inputs (TinyTapeout standard interface) ─────────────────────
    input  wire [7:0] ui_in,    // ui_in[0]   = Bit_in  (serial data, LSB first)
                                 // ui_in[3:1] = op[2:0] (opcode, parallel, stable)
                                 // ui_in[7:4] = unused

    // ── Dedicated outputs ─────────────────────────────────────────────────────
    output wire [7:0] uo_out,   // uo_out[7:0] = Data_out[7:0] (8-bit result)

    // ── Bidirectional I/O (only uio[0] used as output) ───────────────────────
    input  wire [7:0] uio_in,   // Bidirectional input path — unused
    output wire [7:0] uio_out,  // uio_out[0] = Done (one-cycle pulse)
                                 // uio_out[7:1] = 0 (always low)
    output wire [7:0] uio_oe,   // Output-enable: 1 = output, 0 = input
                                 // Only bit 0 is set to output

    // ── Control signals ───────────────────────────────────────────────────────
    input  wire       ena,      // Always 1 when the design is powered (TinyTapeout)
    input  wire       clk,      // System clock — up to 50 MHz
    input  wire       rst_n     // Active-low synchronous reset
);

    // ─────────────────────────────────────────────────────────────────────────
    // Internal signal: Done pulse from serial_alu_ctrl
    // ─────────────────────────────────────────────────────────────────────────
    wire done_reg;

    // ─────────────────────────────────────────────────────────────────────────
    // serial_alu_ctrl instance
    //
    // Connects the TinyTapeout pin interface to the FSM + shift register module.
    // The ALU result is routed directly to uo_out through the alu instance wire.
    // ─────────────────────────────────────────────────────────────────────────
    serial_alu_ctrl alu (
        .CLK      (clk),
        .RST_n    (rst_n),
        .Bit_in   (ui_in[0]),    // ui_in[0] = serial input, LSB first
        .op       (ui_in[3:1]),  // ui_in[3:1] = opcode (parallel)
        .Data_out (uo_out[7:0]), // 8-bit parallel result → dedicated outputs
        .Done     (done_reg)
    );

    // ─────────────────────────────────────────────────────────────────────────
    // Bidirectional I/O output assignments
    //   uio_out[0] : Done flag (one-cycle high pulse from serial_alu_ctrl)
    //   uio_out[7:1]: driven low (unused pins must not float)
    //   uio_oe[0]  : 1 — uio[0] configured as digital output
    //   uio_oe[7:1]: 0 — all other uio pins remain inputs
    // ─────────────────────────────────────────────────────────────────────────
    assign uio_out = {7'b0, done_reg};  // Only bit 0 carries a meaningful signal
    assign uio_oe  = 8'b0000_0001;      // uio[0] = output; uio[7:1] = input

    // ─────────────────────────────────────────────────────────────────────────
    // Unused input tie-off
    //
    // Connects unused input pins to a single wire using a reduction AND with
    // a constant 0, ensuring the signal is never optimised away. This suppresses
    // Verilator unused-signal warnings and avoids synthesis warnings from Yosys.
    // ─────────────────────────────────────────────────────────────────────────
    wire _unused = &{ena, uio_in, ui_in[7:4], 1'b0};

endmodule
/* verilator lint_on TIMESCALEMOD */