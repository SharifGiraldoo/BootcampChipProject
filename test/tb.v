`default_nettype none
`timescale 1ns / 1ps

/*
 * tb.v — Testbench para tt_um_alu7b
 *
 * Bootcamp Diseño y Fabricación de Chips — IEEE OpenSilicon / IEEE CASS UTP 2026
 *
 * Instancia el módulo top-level tt_um_alu7b y expone las señales para
 * que cocotb (test.py) las controle y verifique.
 *
 * Compatible con simulación RTL y Gate-Level (GATES=yes).
 *
 * SPDX-License-Identifier: Apache-2.0
 */

module tb ();

    // ── Volcado de señales a archivo FST (GTKWave / Surfer) ──────────────────
    initial begin
        $dumpfile("tb.fst");
        $dumpvars(0, tb);
        #1;
    end

    // ── Declaración de señales ────────────────────────────────────────────────
    reg        clk;
    reg        rst_n;
    reg        ena;
    reg  [7:0] ui_in;    // ui_in[0] = Bit_in (dato serial)
    reg  [7:0] uio_in;   // No utilizado en este diseño

    wire [7:0] uo_out;   // Data_out[7:0] — resultado paralelo
    wire [7:0] uio_out;  // uio_out[0] = Done
    wire [7:0] uio_oe;   // Dirección de los pines uio

`ifdef GL_TEST
    wire VPWR = 1'b1;
    wire VGND = 1'b0;
`endif

    // ── Instancia del DUT (Device Under Test) ─────────────────────────────────
    tt_um_alu7b user_project (
`ifdef GL_TEST
        .VPWR    (VPWR),
        .VGND    (VGND),
`endif
        .ui_in   (ui_in),
        .uo_out  (uo_out),
        .uio_in  (uio_in),
        .uio_out (uio_out),
        .uio_oe  (uio_oe),
        .ena     (ena),
        .clk     (clk),
        .rst_n   (rst_n)
    );

endmodule
