`default_nettype none
`timescale 1ns / 1ps

/*
 * tb.v — Verilog testbench for tt_um_alu7b
 *
 * Bootcamp IC Design & Fabrication — IEEE OpenSilicon / IEEE CASS UTP 2026
 *
 * Instantiates the tt_um_alu7b top-level module and exposes all signals
 * so that cocotb (test.py) can drive and observe them.
 *
 * Compatible with both RTL simulation and gate-level simulation (GATES=yes).
 *
 * SPDX-License-Identifier: Apache-2.0
 */

module tb ();

    //Waveform dump (GTKWave / Surfer) 
    initial begin
        $dumpfile("tb.fst");
        $dumpvars(0, tb);
        #1;
    end

    //Signal declarations
    reg        clk;
    reg        rst_n;
    reg        ena;
    reg  [7:0] ui_in;    // ui_in[0] = Bit_in (serial data input)
    reg  [7:0] uio_in;   // Not used in this design

    wire [7:0] uo_out;   // Data_out[7:0] — parallel result
    wire [7:0] uio_out;  // uio_out[0] = Done flag
    wire [7:0] uio_oe;   // Bidirectional direction control

`ifdef GL_TEST
    wire VPWR = 1'b1;
    wire VGND = 1'b0;
`endif

    //Device Under Test instantiation
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