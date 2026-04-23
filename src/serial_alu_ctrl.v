/*
 * serial_alu_ctrl.v — Serial Input Controller for the 7-bit ALU
 *
 * Bootcamp IC Design & Fabrication — IEEE OpenSilicon / IEEE CASS UTP 2026
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * DESCRIPTION
 * ─────────────────────────────────────────────────────────────────────────────
 * This module implements the complete serial-to-parallel data path and control
 * logic for the 7-bit ALU system. It comprises:
 *
 *   1. Two 7-bit shift-right shift registers (reg_A, reg_B) that capture
 *      operand bits serially from Bit_in, synchronised to the rising edge
 *      of CLK. New bits are inserted at the MSB (shift-right convention).
 *
 *   2. A 5-bit bit counter (bit_count) that counts each rising edge of CLK
 *      during the S_RECV state and triggers the FSM transition when all 14
 *      operand bits have been received (bit_count == CNT_B_END = 13).
 *
 *   3. An instance of alu_7b — a purely combinational 7-bit ALU — that
 *      computes the result continuously from reg_A, reg_B, and the parallel
 *      opcode input op[2:0].
 *
 *   4. A result register (reg_result) and a one-cycle Done pulse (done_reg)
 *      that are generated in the S_CALC state once the FSM determines that
 *      both operands are fully received.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * SERIAL INPUT PROTOCOL (Bit_in, LSB first)
 * ─────────────────────────────────────────────────────────────────────────────
 *
 *   Rising edge  1 ..  7  → Operand A [6:0]  (A[0] first — LSB first)
 *   Rising edge  8 .. 14  → Operand B [6:0]  (B[0] first — LSB first)
 *   Rising edge 15        → FSM in S_CALC: result latched, Done = 1 (one cycle)
 *
 * The opcode op[2:0] is a PARALLEL input, stable throughout the entire
 * operation. It does not need to be serialised into Bit_in.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * SHIFT REGISTER MECHANICS (shift-right, new bit enters at MSB)
 * ─────────────────────────────────────────────────────────────────────────────
 *
 *   reg_A <= { Bit_in, reg_A[6:1] }
 *
 *   After 7 rising edges with bits b0, b1, b2, b3, b4, b5, b6 (LSB first):
 *
 *     Edge 1: reg_A = { b0, xxxxxx }
 *     Edge 2: reg_A = { b1, b0, xxxxx }
 *     Edge 3: reg_A = { b2, b1, b0, xxxx }
 *     ...
 *     Edge 7: reg_A = { b6, b5, b4, b3, b2, b1, b0 }
 *             → reg_A[6] = A[6] (MSB), reg_A[0] = A[0] (LSB)  ✓
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * OPERATION TABLE (op[2:0]) — see also alu_7b.v
 * ─────────────────────────────────────────────────────────────────────────────
 *   3'b000 → ADD   result = A + B   (8-bit; bit[7] = carry-out)
 *   3'b001 → AND   result = A & B   (bit[7] = 0 always)
 *   3'b010 → OR    result = A | B   (bit[7] = 0 always)
 *   3'b011 → XOR   result = A ^ B   (bit[7] = 0 always)
 *   3'b100 → SUB   result = A - B   (8-bit two's complement; bit[7] = borrow)
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * FSM STATE ENCODING
 * ─────────────────────────────────────────────────────────────────────────────
 *   S_RECV (2'b00) — Receive serial bits, update shift registers and bit_count.
 *                    Transition to S_CALC when bit_count == CNT_B_END (13).
 *   S_CALC (2'b01) — reg_A and reg_B are stable. Latch alu_out into reg_result,
 *                    assert done_reg for exactly one cycle. Move to S_DONE.
 *   S_DONE (2'b10) — Result stable on Data_out. Wait for rst_n = 0 to restart.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * OUTPUTS
 * ─────────────────────────────────────────────────────────────────────────────
 *   Data_out[7:0] — 8-bit parallel result (stable from S_CALC onward)
 *   Done          — One-cycle high pulse indicating operation is complete
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * RESET
 * ─────────────────────────────────────────────────────────────────────────────
 *   rst_n = 0 → Synchronous reset: clears all registers, returns FSM to S_RECV.
 *               Must be held low for at least one rising clock edge.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

/* verilator lint_off TIMESCALEMOD */
`default_nettype none

module serial_alu_ctrl (
    // ── Clock and reset ───────────────────────────────────────────────────────
    input  wire       CLK,        // System clock — rising-edge triggered
    input  wire       RST_n,      // Active-low synchronous reset

    // ── Serial data input ─────────────────────────────────────────────────────
    input  wire       Bit_in,     // Serial input — LSB first

    // ── Parallel opcode input ─────────────────────────────────────────────────
    input  wire [2:0] op,         // Operation code — stable during full operation

    // ── Parallel outputs ──────────────────────────────────────────────────────
    output wire [7:0] Data_out,   // 8-bit parallel result (valid after Done)
    output wire       Done        // One-cycle high pulse when result is ready
);

    // =========================================================================
    // 1. LOCAL PARAMETERS
    // =========================================================================

    // Bit counter boundary values (0-based, 5-bit counter)
    // 14 bits total: A[6:0] received at edges 0..6, B[6:0] at edges 7..13.
    localparam [4:0] CNT_A_END = 5'd6;    // Last edge for operand A (bit_count 0..6)
    localparam [4:0] CNT_B_END = 5'd13;   // Last edge for operand B (bit_count 7..13)

    // FSM state encoding (2-bit Gray-adjacent for minimal glitch)
    localparam [1:0] S_RECV = 2'd0,       // Serial reception state
                     S_CALC = 2'd1,       // Computation and result latch state
                     S_DONE = 2'd2;       // Idle/result-stable state

    // =========================================================================
    // 2. INTERNAL REGISTER DECLARATIONS
    // =========================================================================

    reg [1:0] state;          // Current FSM state
    reg [4:0] bit_count;      // Number of bits received so far (0-based)
    reg [6:0] reg_A;          // Shift register for operand A (7 bits)
    reg [6:0] reg_B;          // Shift register for operand B (7 bits)
    reg [7:0] reg_result;     // Registered ALU result (latched in S_CALC)
    reg       done_reg;       // Done pulse register (one clock cycle high)

    // =========================================================================
    // 3. COMBINATIONAL ALU INSTANCE
    //
    // alu_7b is a purely combinational module. Its output (alu_out) reflects
    // changes in reg_A, reg_B, and op with combinational propagation delay only.
    // In state S_CALC, reg_A and reg_B are fully stable, so alu_out is valid
    // and safe to latch into reg_result.
    // =========================================================================

    wire [7:0] alu_out;   // Combinational ALU output (continuously computed)

    alu_7b u_alu (
        .A      (reg_A),
        .B      (reg_B),
        .op     (op),
        .result (alu_out)
    );

    // =========================================================================
    // 4. SYNCHRONOUS FSM — SHIFT REGISTER, COUNTER, AND STATE TRANSITIONS
    //
    // A single synchronous always block handles:
    //   a) Synchronous active-low reset (rst_n = 0)
    //   b) Shift-right shift register update (new bit enters at MSB)
    //   c) Bit counter increment
    //   d) FSM state transitions
    //   e) Result latching and Done pulse generation
    //
    // DONE PULSE:
    //   done_reg is cleared at the start of every rising edge (default = 0)
    //   and is only asserted in S_CALC. This guarantees a one-cycle pulse.
    // =========================================================================

    always @(posedge CLK) begin
        if (!RST_n) begin
            // ── Synchronous reset — return to initial state ───────────────────
            state      <= S_RECV;
            bit_count  <= 5'd0;
            reg_A      <= 7'd0;
            reg_B      <= 7'd0;
            reg_result <= 8'd0;
            done_reg   <= 1'b0;

        end else begin

            // Default: clear Done every cycle (ensures one-cycle pulse only)
            done_reg <= 1'b0;

            case (state)

                // ─────────────────────────────────────────────────────────────
                // S_RECV: Serial reception via shift-right shift registers.
                //
                // Bits 0..6  (bit_count <= CNT_A_END=6):  captured into reg_A
                // Bits 7..13 (bit_count <= CNT_B_END=13): captured into reg_B
                //
                // Shift-right, MSB insertion:
                //   reg_X <= { Bit_in, reg_X[6:1] }
                //
                // After 7 edges:  reg_X[6]=MSB ... reg_X[0]=LSB  ✓
                //
                // Transition: when bit_count == CNT_B_END (13), all 14 operand
                // bits have been received. Reset bit_count to 0 and go to S_CALC.
                // ─────────────────────────────────────────────────────────────
                S_RECV: begin
                    if (bit_count <= CNT_A_END) begin
                        // Edges 0..6 → Operand A (LSB first, shift-right)
                        reg_A <= { Bit_in, reg_A[6:1] };

                    end else if (bit_count <= CNT_B_END) begin
                        // Edges 7..13 → Operand B (LSB first, shift-right)
                        reg_B <= { Bit_in, reg_B[6:1] };
                    end

                    // Transition check and counter update
                    if (bit_count == CNT_B_END) begin
                        // All 14 operand bits received — move to computation
                        state     <= S_CALC;
                        bit_count <= 5'd0;      // Reset for next operation
                    end else begin
                        bit_count <= bit_count + 5'd1;
                    end
                end

                // ─────────────────────────────────────────────────────────────
                // S_CALC: reg_A and reg_B are stable. alu_out is valid.
                //
                // Latch the combinational ALU result into reg_result.
                // Assert done_reg for exactly one clock cycle.
                // Transition to S_DONE.
                // ─────────────────────────────────────────────────────────────
                S_CALC: begin
                    reg_result <= alu_out;   // Latch combinational result
                    done_reg   <= 1'b1;      // Assert Done for one cycle
                    state      <= S_DONE;
                end

                // ─────────────────────────────────────────────────────────────
                // S_DONE: Result stable on Data_out. System is idle.
                //
                // Remains here until rst_n = 0 triggers synchronous reset.
                // done_reg is automatically cleared (default assignment above).
                // ─────────────────────────────────────────────────────────────
                S_DONE: state <= S_DONE;

                // Safety default: should never be reached in clean synthesis.
                // Returns to S_RECV to avoid locking the system.
                default: state <= S_RECV;

            endcase
        end
    end

    // =========================================================================
    // 5. OUTPUT ASSIGNMENTS
    // =========================================================================

    assign Data_out = reg_result;   // 8-bit parallel result (valid after Done)
    assign Done     = done_reg;     // One-cycle high pulse when result is ready

endmodule
/* verilator lint_on TIMESCALEMOD */