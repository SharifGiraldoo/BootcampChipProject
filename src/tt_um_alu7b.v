`timescale 1ns / 1ps
/*
 * tt_um_alu7b.v — ALU de 7 bits, entrada serial LSB-first, salida paralela
 *
 * Bootcamp Diseño y Fabricación de Chips — IEEE OpenSilicon / IEEE CASS UTP 2026
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * PROTOCOLO DE ENTRADA SERIAL (ui_in[0] = Bit_in):
 *
 *   Posedge  1 ..  7  → Operando A [6:0], LSB primero
 *   Posedge  8 .. 14  → Operando B [6:0], LSB primero
 *   Posedge 15 .. 17  → Opcode   [2:0], LSB primero
 *   Posedge 18        → FSM S_CALC: resultado en uo_out, Done=1 en uio_out[0]
 *
 * SHIFT-REGISTER LSB-FIRST CORRECTO (shift-right, nuevo bit en MSB):
 *   reg <= {bit_in, reg[N-1:1]}
 *   Tras N posedges: reg[N-1]=MSB ... reg[0]=LSB  ✓
 *
 * TABLA DE OPERACIONES (op[2:0]):
 *   000 → Suma    result = A + B   (bit[7] = carry)
 *   001 → AND     result = A & B
 *   010 → OR      result = A | B
 *   011 → XOR     result = A ^ B
 *   100 → Resta   result = A - B   (bit[7] = borrow en complemento a 2)
 *
 * SALIDAS:
 *   uo_out[7:0]  — Resultado de 8 bits (paralelo)
 *   uio_out[0]   — Done: pulso alto de exactamente 1 ciclo de reloj
 *
 * RESET:
 *   rst_n = 0 → estado inicial, bit_count = 0, registros = 0
 *
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

// ─────────────────────────────────────────────────────────────────────────────
// Módulo 1: ALU combinacional de 7 bits
// ─────────────────────────────────────────────────────────────────────────────
module alu_7b (
    input  wire [6:0] A,       // Operando A (7 bits)
    input  wire [6:0] B,       // Operando B (7 bits)
    input  wire [2:0] op,      // Código de operación
    output reg  [7:0] result   // Resultado de 8 bits (incluye carry/borrow)
);
    always @(*) begin
        case (op)
            3'b000: result = {1'b0, A} + {1'b0, B};  // Suma  — bit[7] = carry
            3'b001: result = {1'b0, A & B};            // AND
            3'b010: result = {1'b0, A | B};            // OR
            3'b011: result = {1'b0, A ^ B};            // XOR
            3'b100: result = {1'b0, A} - {1'b0, B};   // Resta — bit[7] = borrow C2
            default: result = 8'b0;
        endcase
    end
endmodule


// ─────────────────────────────────────────────────────────────────────────────
// Módulo 2 (top-level): Interfaz TinyTapeout para la ALU serial→paralela
// ─────────────────────────────────────────────────────────────────────────────
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

    // ─── Instancia ALU combinacional ──────────────────────────────────────────
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

                // ── S_RECV: Captura serial con shift-right LSB-first ─────────
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
                        // Último bit (índice 16) recibido → pasar a calcular
                        state     <= S_CALC;
                        bit_count <= 5'd0;
                    end else
                        bit_count <= bit_count + 5'd1;
                end

                // ── S_CALC: reg_A / reg_B / reg_op estables ──────────────────
                // La ALU combinacional ya tiene el resultado correcto.
                // Latchar resultado y generar pulso Done.
                S_CALC: begin
                    reg_result <= alu_out;
                    done_reg   <= 1'b1;
                    state      <= S_DONE;
                end

                // ── S_DONE: Resultado estable en uo_out ──────────────────────
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
