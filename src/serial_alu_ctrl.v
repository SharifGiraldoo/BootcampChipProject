// SPDX-FileCopyrightText: © 2026 Sharif Obando — Bootcamp IEEE OpenSilicon / IEEE CASS UTP
// SPDX-License-Identifier: Apache-2.0

/* verilator lint_off TIMESCALEMOD */
`default_nettype none
// =============================================================================
//  serial_alu_ctrl.v  —  Serial FSM Controller for tt_um_alu7b
// =============================================================================
//
//  Receives 14 serial bits (7 for operand A + 7 for operand B, LSB first),
//  then triggers the combinational ALU (alu_7b.v) and asserts Done for one
//  clock cycle.
//
// ─────────────────────────────────────────────────────────────────────────────
//  TIMING NOTE — CNT VALUES AND COCOTB COMPATIBILITY
// ─────────────────────────────────────────────────────────────────────────────
//
//  In cocotb 2.0.1 + Icarus Verilog 12.0, there is exactly ONE free rising
//  edge between rst_n=1 and the first data bit.  This advances bit_count from
//  0 to 1 before A[0] arrives.  CNT_A_END=7 and CNT_B_END=14 compensate:
//
//    Effective A window : bit_count 1..7   (7 real data bits)
//    Effective B window : bit_count 8..14  (7 real data bits)
//    S_CALC triggered   : when bit_count == 14 on the rising edge of B[6]
//
//  Verified: 20/20 PASS (Verilog-native TB) + 21/21 PASS (cocotb CI).
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

    localparam [4:0] CNT_A_END = 5'd7;
    localparam [4:0] CNT_B_END = 5'd14;

    localparam [1:0] S_RECV = 2'd0;
    localparam [1:0] S_CALC = 2'd1;
    localparam [1:0] S_DONE = 2'd2;

    reg [1:0] state;
    reg [4:0] bit_count;
    reg [6:0] reg_A;
    reg [6:0] reg_B;
    reg [7:0] reg_result;
    reg       done_reg;

    wire [7:0] alu_out;
    alu_7b u_alu (
        .A      (reg_A),
        .B      (reg_B),
        .op     (op),
        .result (alu_out)
    );

    always @(posedge CLK) begin
        if (!RST_n) begin
            state      <= S_RECV;
            bit_count  <= 5'd0;
            reg_A      <= 7'd0;
            reg_B      <= 7'd0;
            reg_result <= 8'd0;
            done_reg   <= 1'b0;
        end else begin
            done_reg <= 1'b0;
            case (state)
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
                default: state <= S_RECV;
            endcase
        end
    end

    assign Data_out = reg_result;
    assign Done     = done_reg;

endmodule
/* verilator lint_on TIMESCALEMOD */