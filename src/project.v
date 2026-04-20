/*
 * project.v — Project integration entry point
 *
 * Bootcamp IC Design & Fabrication — IEEE OpenSilicon / IEEE CASS UTP 2026
 *
 * This file is the synthesis entry point for the LibreLane flow.
 * It contains NO module logic. All functionality is implemented in:
 *
 *   alu_7b.v       — 7-bit combinational ALU
 *   tt_um_alu7b.v  — TinyTapeout top-level with serial→parallel FSM
 *
 * Both files are listed in info.yaml (source_files) and in test/Makefile
 * (PROJECT_SOURCES) so that synthesis and simulation compile them together.
 *
 * MODULE HIERARCHY:
 *
 *   tt_um_alu7b  (top-level — TinyTapeout interface)
 *       └── alu_7b  (instance u_alu — combinational logic)
 *
 * SPDX-License-Identifier: Apache-2.0
 */

// Intentionally empty — all modules are defined in their own .v files.