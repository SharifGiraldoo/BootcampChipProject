// SPDX-FileCopyrightText: © 2026 Sharif Obando — Bootcamp IEEE OpenSilicon / IEEE CASS UTP
// SPDX-License-Identifier: Apache-2.0

/* verilator lint_off TIMESCALEMOD */
`default_nettype none
// =============================================================================
//  serial_alu_ctrl.v  —  Serial FSM Controller for tt_um_alu7b
// =============================================================================
//
//  Receives 14 serial bits (7 for A + 7 for B, LSB first) and triggers the
//  combinational ALU (alu_7b.v).  Done pulses high for exactly one clock cycle.
//
// ─────────────────────────────────────────────────────────────────────────────
//  FOUR-STATE FSM  (S_IDLE eliminates free-edge ambiguity)
// ─────────────────────────────────────────────────────────────────────────────
//
//  After rst_n=1, the FSM spends exactly ONE cycle in S_IDLE doing nothing.
//  This absorbs the free rising edge that occurs between rst_n release and the
//  first FallingEdge-aligned data bit — both in cocotb 2.0.1 and in any
//  native Verilog testbench that releases reset on a negedge.
//
//  S_IDLE  →  S_RECV  on the very next cycle (no condition needed)
//  S_RECV  →  S_CALC  when bit_count == CNT_B_END (14th bit received)
//  S_CALC  →  S_DONE  after 1 cycle (Done=1 on this transition cycle)
//  S_DONE  →  S_DONE  until rst_n=0
//
//  bit_count 0..6   : shift Bit_in into reg_A (CNT_A_END = 6)
//  bit_count 7..13  : shift Bit_in into reg_B (CNT_B_END = 13)
//
//  Shift-right, MSB insertion:  reg <= {Bit_in, reg[6:1]}
//  After 7 edges with b0..b6 (LSB first): reg[0]=b0=operand[0]  ✓
//
// =============================================================================

module serial_alu_ctrl (
    input  wire       CLK,
    input  wire       RST_n,
    input  wire       Bit_in,
    input  wire [2:0] op,
    output wire [7:0] Data_out,
    output wire       Done
);

    // ── Thresholds ───────────────────────────────────────────────────────────
    localparam [4:0] CNT_A_END = 5'd6;   // last bit_count for operand A window
    localparam [4:0] CNT_B_END = 5'd13;  // last bit_count: 14 bits received total

    // ── FSM states ───────────────────────────────────────────────────────────
    localparam [1:0] S_IDLE = 2'd0;   // absorbs free edge post-reset
    localparam [1:0] S_RECV = 2'd1;   // serial reception
    localparam [1:0] S_CALC = 2'd2;   // latch result, assert Done
    localparam [1:0] S_DONE = 2'd3;   // hold result

    // ── Registers ────────────────────────────────────────────────────────────
    reg [1:0] state;
    reg [4:0] bit_count;
    reg [6:0] reg_A;
    reg [6:0] reg_B;
    reg [7:0] reg_result;
    reg       done_reg;

    // ── Combinational ALU ────────────────────────────────────────────────────
    wire [7:0] alu_out;
    alu_7b u_alu (
        .A      (reg_A),
        .B      (reg_B),
        .op     (op),
        .result (alu_out)
    );

    // ── Sequential FSM ───────────────────────────────────────────────────────
    always @(posedge CLK) begin
        if (!RST_n) begin
            state      <= S_IDLE;
            bit_count  <= 5'd0;
            reg_A      <= 7'd0;
            reg_B      <= 7'd0;
            reg_result <= 8'd0;
            done_reg   <= 1'b0;
        end else begin
            done_reg <= 1'b0;

            case (state)
                S_IDLE: begin
                    // Absorb the free rising edge after reset release.
                    // No data is captured; FSM moves immediately to S_RECV.
                    bit_count <= 5'd0;
                    state     <= S_RECV;
                end

                S_RECV: begin
                    if (bit_count <= CNT_A_END)
                        reg_A <= {Bit_in, reg_A[6:1]};
                    else
                        reg_B <= {Bit_in, reg_B[6:1]};

                    if (bit_count == CNT_B_END) begin
                        state     <= S_CALC;
                        bit_count <= 5'd0;
                    end else begin
                        bit_count <= bit_count + 5'd1;
                    end
                end

                S_CALC: begin
                    reg_result <= alu_out;
                    done_reg   <= 1'b1;
                    state      <= S_DONE;
                end

                S_DONE: begin
                    state <= S_DONE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    assign Data_out = reg_result;
    assign Done     = done_reg;

endmodule
/* verilator lint_on TIMESCALEMOD */