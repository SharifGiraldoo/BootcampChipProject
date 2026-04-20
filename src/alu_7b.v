/*
 * alu_7b.v — Unidad Aritmético-Lógica combinacional de 7 bits
 *
 * Bootcamp Diseño y Fabricación de Chips — IEEE OpenSilicon / IEEE CASS UTP 2026
 *
 * Módulo combinacional puro. Recibe dos operandos de 7 bits y un código
 * de operación de 3 bits; entrega el resultado en 8 bits (el bit [7]
 * corresponde al carry en suma o al borrow en resta).
 *
 * TABLA DE OPERACIONES (op[2:0]):
 *   000 → Suma    result = A + B   (bit[7] = carry)
 *   001 → AND     result = A & B
 *   010 → OR      result = A | B
 *   011 → XOR     result = A ^ B
 *   100 → Resta   result = A - B   (bit[7] = borrow, complemento a 2)
 *
 * SPDX-License-Identifier: Apache-2.0
 */

`timescale 1ns / 1ps
`default_nettype none

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
