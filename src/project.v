/*
 * project.v — Archivo de integración del proyecto ALU 7 bits
 *
 * Bootcamp Diseño y Fabricación de Chips — IEEE OpenSilicon / IEEE CASS UTP 2026
 *
 * Este archivo es el punto de entrada del proyecto para el flujo de síntesis
 * de LibreLane. No contiene lógica propia; la funcionalidad está distribuida en:
 *
 *   alu_7b.v       — ALU combinacional de 7 bits (módulo funcional)
 *   tt_um_alu7b.v  — Top-level TinyTapeout con FSM serial→paralela
 *
 * Todos los archivos se listan en info.yaml (source_files) y en test/Makefile
 * (PROJECT_SOURCES) para que tanto la síntesis como la simulación los procesen.
 *
 * JERARQUÍA DE MÓDULOS:
 *
 *   tt_um_alu7b  (top-level, interfaz TinyTapeout)
 *       └── alu_7b  (instancia u_alu, lógica combinacional)
 *
 * SPDX-License-Identifier: Apache-2.0
 */

// Este archivo es intencional y vacío de lógica.
// Los módulos alu_7b y tt_um_alu7b están definidos en sus respectivos
// archivos .v y son compilados en conjunto por el flujo de síntesis.
