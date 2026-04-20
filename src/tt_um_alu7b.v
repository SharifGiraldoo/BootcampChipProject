/*
 * tt_um_alu7b.v — Interfaz TinyTapeout para la ALU serial→paralela de 7 bits
 *
 * Bootcamp Diseño y Fabricación de Chips — IEEE OpenSilicon / IEEE CASS UTP 2026
 *
 * Módulo top-level que implementa la FSM de recepción serial e instancia
 * el módulo combinacional alu_7b.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * PROTOCOLO DE ENTRADA SERIAL (ui_in[0] = Bit_in, LSB primero):
 *
 *   Posedge  1 ..  7  → Operando A [6:0]
 *   Posedge  8 .. 14  → Operando B [6:0]
 *   Posedge 15 .. 17  → Opcode   [2:0]
 *   Posedge 18        → FSM S_CALC: resultado en uo_out, Done=1 en uio_out[0]
 *
 * SHIFT-REGISTER LSB-FIRST (shift-right, bit nuevo en MSB):
 *   reg <= {bit_in, reg[N-1:1]}
 *   Tras N posedges: reg[N-1]=MSB ... reg[0]=LSB  ✓
 *
 * SALIDAS:
 *   uo_out[7:0]  — Resultado de 8 bits en paralelo
 *   uio_out[0]   — Done: pulso alto de exactamente 1 ciclo de reloj
 *
 * RESET:
 *   rst_n = 0 → estado inicial, contadores y registros en cero
 *
 * SPDX-License-Identifier: Apache-2.0
 */

`timescale 1ns / 1ps
`default_nettype none

module tt_um_alu7b (
    input  wire [7:0] ui_in,    // Dedicated inputs  — ui_in[0] = Bit_in
    output wire [7:0] uo_out,   // Dedicated outputs — resultado[7:0]
    input  wire [7:0] uio_in,   // IOs: Input path   (no utilizado)
    output wire [7:0] uio_out,  // IOs: Output path  — uio_out[0] = Done
    output wire [7:0] uio_oe,   // IOs: Enable path  (active high: 1=output)
    input  wire       ena,      // Siempre 1 cuando el diseño está activo
    input  wire       clk,      // Reloj del sistema
    input  wire       rst_n     // Reset activo bajo
);

    // ─── Parámetros: límites de bit_count (0-indexado, 5 bits) ───────────────
    localparam [4:0] CNT_A_END  = 5'd6;   // bits 0..6   → reg_A  (7 bits)
    localparam [4:0] CNT_B_END  = 5'd13;  // bits 7..13  → reg_B  (7 bits)
    localparam [4:0] CNT_OP_END = 5'd16;  // bits 14..16 → reg_op (3 bits)

    // ─── Estados FSM ──────────────────────────────────────────────────────────
    localparam [1:0] S_RECV = 2'd0,   // Recepción serial
                     S_CALC = 2'd1,   // Cálculo y captura de resultado
                     S_DONE = 2'd2;   // Resultado estable, espera reset

    // ─── Registros internos ───────────────────────────────────────────────────
    reg [1:0] state;
    reg [4:0] bit_count;
    reg [6:0] reg_A;
    reg [6:0] reg_B;
    reg [2:0] reg_op;
    reg [7:0] reg_result;
    reg       done_reg;

    wire bit_in = ui_in[0];

    // ─── Instancia del módulo combinacional alu_7b ────────────────────────────
    wire [7:0] alu_out;
    alu_7b u_alu (
        .A      (reg_A),
        .B      (reg_B),
        .op     (reg_op),
        .result (alu_out)
    );

    // ─── FSM + Datapath ───────────────────────────────────────────────────────
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_RECV;
            bit_count  <= 5'd0;
            reg_A      <= 7'd0;
            reg_B      <= 7'd0;
            reg_op     <= 3'd0;
            reg_result <= 8'd0;
            done_reg   <= 1'b0;
        end else begin
            done_reg <= 1'b0;   // Done es pulso de exactamente 1 ciclo de reloj

            case (state)

                // S_RECV: captura serial con shift-right LSB-first
                // Bit nuevo entra en [MSB], corre hacia [LSB].
                // Tras N posedges: reg[N-1]=MSB ... reg[0]=LSB  ✓
                S_RECV: begin
                    if (bit_count <= CNT_A_END)
                        reg_A  <= {bit_in, reg_A[6:1]};
                    else if (bit_count <= CNT_B_END)
                        reg_B  <= {bit_in, reg_B[6:1]};
                    else
                        reg_op <= {bit_in, reg_op[2:1]};

                    if (bit_count == CNT_OP_END) begin
                        state     <= S_CALC;
                        bit_count <= 5'd0;
                    end else
                        bit_count <= bit_count + 5'd1;
                end

                // S_CALC: reg_A / reg_B / reg_op estables
                // La ALU combinacional ya tiene el resultado correcto.
                // Latchar resultado y generar pulso Done.
                S_CALC: begin
                    reg_result <= alu_out;
                    done_reg   <= 1'b1;
                    state      <= S_DONE;
                end

                // S_DONE: resultado estable en uo_out.
                // Espera rst_n=0 para iniciar una nueva operación.
                S_DONE: state <= S_DONE;

                default: state <= S_RECV;
            endcase
        end
    end

    // ─── Asignación de salidas ────────────────────────────────────────────────
    assign uo_out  = reg_result;
    assign uio_out = {7'b0, done_reg};  // uio_out[0] = Done
    assign uio_oe  = 8'b0000_0001;      // Solo uio[0] es salida

    // ─── Pines de entrada no usados (elimina warnings del linter) ────────────
    wire _unused = &{ena, uio_in, ui_in[7:1], 1'b0};

endmodule
