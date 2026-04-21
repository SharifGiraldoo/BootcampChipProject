/*
 * tt_um_alu7b.v — TinyTapeout top-level for the 7-bit serial→parallel ALU
 *
 * Bootcamp IC Design & Fabrication — IEEE OpenSilicon / IEEE CASS UTP 2026
 *
 * Implements the serial receive FSM and instantiates the combinational alu_7b
 * module.
 *
 * SERIAL INPUT PROTOCOL  (ui_in[0] = Bit_in, LSB first):
 *
 *   Posedge  1 ..  7  → Operand A [6:0]
 *   Posedge  8 .. 14  → Operand B [6:0]
 *   Posedge 15        → FSM S_CALC: result latched in uo_out, Done=1 on uio_out[0]
 *
 * OPCODE (parallel input):
 *   ui_in[3:1] = op[2:0]  — stable during the entire operation
 *
 * LSB-FIRST SHIFT REGISTER (shift-right, new bit enters at MSB):
 *   reg <= {bit_in, reg[N-1:1]}
 *   After N posedges: reg[N-1]=MSB ... reg[0]=LSB  ✓
 *
 * OUTPUTS:
 *   uo_out[7:0]  — 8-bit parallel result
 *   uio_out[0]   — Done: one-cycle high pulse when result is ready
 *
 * RESET:
 *   rst_n = 0 → synchronous reset to initial state; all registers cleared
 *
 * SPDX-License-Identifier: Apache-2.0
 */

/* verilator lint_off TIMESCALEMOD */
`default_nettype none

module tt_um_alu7b (
    input  wire [7:0] ui_in,    // ui_in[0]=Bit_in (serial), ui_in[3:1]=op[2:0]
    output wire [7:0] uo_out,   // Dedicated outputs — result[7:0]
    input  wire [7:0] uio_in,   // Bidirectional IOs: input path  (unused)
    output wire [7:0] uio_out,  // Bidirectional IOs: output path — uio_out[0] = Done
    output wire [7:0] uio_oe,   // Bidirectional IOs: enable path (active high: 1=output)
    input  wire       ena,      // Always 1 when the design is powered
    input  wire       clk,      // System clock
    input  wire       rst_n     // Active-low reset
);

    // ── Bit-count limits (0-indexed, 5-bit counter) ───────────────────────────
    localparam [4:0] CNT_A_END = 5'd6;   // bits 0..6   → reg_A  (7 bits)
    localparam [4:0] CNT_B_END = 5'd13;  // bits 7..13  → reg_B  (7 bits)

    // ── FSM states ────────────────────────────────────────────────────────────
    localparam [1:0] S_RECV = 2'd0,   // Serial receive
                     S_CALC = 2'd1,   // Compute and latch result
                     S_DONE = 2'd2;   // Result stable, waiting for reset

    // ── Internal registers ────────────────────────────────────────────────────
    reg [1:0] state;
    reg [4:0] bit_count;
    reg [6:0] reg_A;
    reg [6:0] reg_B;
    reg [7:0] reg_result;
    reg       done_reg;

    wire       bit_in = ui_in[0];
    wire [2:0] op     = ui_in[3:1];   // Parallel opcode, stable during operation

    // ── Combinational ALU instance ────────────────────────────────────────────
    wire [7:0] alu_out;
    alu_7b u_alu (
        .A      (reg_A),
        .B      (reg_B),
        .op     (op),
        .result (alu_out)
    );

    // ── FSM + Datapath ────────────────────────────────────────────────────────
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_RECV;
            bit_count  <= 5'd0;
            reg_A      <= 7'd0;
            reg_B      <= 7'd0;
            reg_result <= 8'd0;
            done_reg   <= 1'b0;
        end else begin
            done_reg <= 1'b0;   // Done is a one-cycle pulse; clear every edge

            case (state)

                // S_RECV: LSB-first shift-right capture.
                // New bit enters at [MSB] and shifts toward [LSB].
                // After N posedges: reg[N-1]=MSB ... reg[0]=LSB  ✓
                S_RECV: begin
                    if (bit_count <= CNT_A_END)
                        reg_A <= {bit_in, reg_A[6:1]};
                    else
                        reg_B <= {bit_in, reg_B[6:1]};

                    if (bit_count == CNT_B_END) begin
                        state     <= S_CALC;
                        bit_count <= 5'd0;
                    end else
                        bit_count <= bit_count + 5'd1;
                end

                // S_CALC: reg_A / reg_B / op are stable.
                // The combinational ALU already has the correct result.
                // Latch result and assert Done for one cycle.
                S_CALC: begin
                    reg_result <= alu_out;
                    done_reg   <= 1'b1;
                    state      <= S_DONE;
                end

                // S_DONE: result stable on uo_out.
                // Wait for rst_n = 0 to start a new operation.
                S_DONE: state <= S_DONE;

                default: state <= S_RECV;
            endcase
        end
    end

    // ── Output assignments ────────────────────────────────────────────────────
    assign uo_out  = reg_result;
    assign uio_out = {7'b0, done_reg};  // uio_out[0] = Done; uio_out[7:1] = 0
    assign uio_oe  = 8'b0000_0001;      // Only uio[0] is an output

    // ── Unused input tie-off (suppresses linter warnings) ────────────────────
    wire _unused = &{ena, uio_in, ui_in[7:4], 1'b0};

endmodule
/* verilator lint_on TIMESCALEMOD */