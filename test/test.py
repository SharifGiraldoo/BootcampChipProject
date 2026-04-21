# SPDX-FileCopyrightText: © 2026 Bootcamp IEEE OpenSilicon / IEEE CASS UTP
# SPDX-License-Identifier: Apache-2.0

"""
test.py — cocotb testbench para tt_um_alu7b
============================================

Módulo bajo prueba (DUT): tt_um_alu7b  (instanciado en tb.v como user_project)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PROTOCOLO SERIAL tt_um_alu7b
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Posedge  1 ..  7  → Operando A [6:0], LSB primero  (bit_count 0..6)
  Posedge  8 .. 14  → Operando B [6:0], LSB primero  (bit_count 7..13)
  Posedge 15        → S_CALC: reg_result←alu_out, done_reg←1, uo_out válido

  Opcode : puerto PARALELO en ui_in[3:1] = op[2:0], estable durante
           toda la operación (igual que serial_alu_ctrl.v).

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
TABLA DE OPERACIONES (referencia alu_7b.v)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  000 → ADD  result = {1'b0,A} + {1'b0,B}  [8 bits]  bit[7]=carry-out
  001 → AND  result = {1'b0, A & B}                   bit[7]=0
  010 → OR   result = {1'b0, A | B}                   bit[7]=0
  011 → XOR  result = {1'b0, A ^ B}                   bit[7]=0
  100 → SUB  result = {1'b0,A} - {1'b0,B}  [8 bits]  bit[7]=borrow (C2)

  En Python (A, B ∈ [0, 127]):
    ADD expected = (A + B) & 0xFF
    SUB expected = (A - B) & 0xFF   (complemento a 2 de 8 bits)
    AND expected = (A & B) & 0x7F   (bit[7] siempre 0)
    OR  expected = (A | B) & 0x7F
    XOR expected = (A ^ B) & 0x7F
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, FallingEdge

# ── Opcodes (coinciden con alu_7b.v y tt_um_alu7b.v) ─────────────────────────
OP_ADD = 0b000
OP_AND = 0b001
OP_OR  = 0b010
OP_XOR = 0b011
OP_SUB = 0b100

CLK_PERIOD_NS = 20   # 20 ns → 50 MHz (límite TinyTapeout IO)


# ─────────────────────────────────────────────────────────────────────────────
# HELPER: reset_dut
#
# Reset asíncrono activo-bajo (always @(posedge clk or negedge rst_n) en RTL).
# rst_n=0 tiene efecto inmediato; se mantiene 5 ciclos por margen robusto.
# Finaliza en FallingEdge para que el primer bit[0] de A sea presentado
# sin un FallingEdge extra, alineando correctamente los 14 posedges
# de captura con bit_count 0..13 del RTL.
# ─────────────────────────────────────────────────────────────────────────────
async def reset_dut(dut):
    """Reset asíncrono activo-bajo. Termina en FallingEdge listo para bit[0]."""
    dut.rst_n.value  = 0
    dut.ui_in.value  = 0
    dut.uio_in.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await FallingEdge(dut.clk)   # Semiciclo bajo: siguiente flanco es posedge


# ─────────────────────────────────────────────────────────────────────────────
# HELPER: run_alu
#
# Envía 14 bits seriales LSB-first: A[6:0] + B[6:0].
# El opcode se aplica en paralelo via ui_in[3:1] antes de iniciar la
# transmisión y se mantiene estable durante toda la operación.
#
# Precondición: control en FallingEdge (tras reset_dut).
#
# Temporización:
#   bit[0]   : presentar dato → RisingEdge (sin FallingEdge previo)
#   bit[i>0] : FallingEdge → presentar dato → RisingEdge
#
# Tras 14 posedges (bit_count llega a CNT_B_END=13), la FSM transiciona
# de S_RECV a S_CALC. En el posedge 15 (S_CALC) se latchea el resultado
# y done_reg se activa por 1 ciclo.
#
# Ventana de captura de Done: hasta 4 iteraciones FallingEdge→RisingEdge.
# En condiciones normales Done aparece en la primera iteración (posedge 15).
# ─────────────────────────────────────────────────────────────────────────────
async def run_alu(dut, A, B, op):
    """
    Transmite 14 bits seriales (A + B, LSB-first).
    El opcode se aplica en ui_in[3:1] como puerto paralelo.
    Retorna (result: int, done_seen: bool).
    """
    # Construir secuencia de 14 bits: A[6:0] LSB-first, luego B[6:0] LSB-first
    bits  = [(A >> i) & 1 for i in range(7)]
    bits += [(B >> i) & 1 for i in range(7)]
    # Total: 14 bits → 14 posedges de captura (bit_count 0..13)

    for i, bit in enumerate(bits):
        if i > 0:
            await FallingEdge(dut.clk)   # Setup window: semiciclo bajo
        # ui_in[0] = Bit_in, ui_in[3:1] = op[2:0], ui_in[7:4] = 0
        dut.ui_in.value = int(bit) | (op << 1)
        await RisingEdge(dut.clk)        # Posedge: DUT captura bit_count=i

    # Limpiar Bit_in pero mantener op estable
    dut.ui_in.value = op << 1
    done_seen  = False
    result_val = 0

    for _ in range(4):
        await FallingEdge(dut.clk)
        await RisingEdge(dut.clk)
        if int(dut.uio_out.value) & 0x01:
            done_seen  = True
            result_val = int(dut.uo_out.value)
            break

    return result_val, done_seen


# ─────────────────────────────────────────────────────────────────────────────
# TEST PRINCIPAL
# ─────────────────────────────────────────────────────────────────────────────
@cocotb.test()
async def test_project(dut):
    """
    Verificación completa de tt_um_alu7b — 20 casos de prueba.
    Cubre ADD, AND, OR, XOR y SUB con casos de borde alineados con
    la especificación del BOOTCAMP y serial_tb.v Bloques A-F.
    Protocolo: 14 bits serial (7A + 7B), op paralelo en ui_in[3:1].
    """
    dut._log.info("=" * 65)
    dut._log.info("  tt_um_alu7b — Bootcamp IEEE OpenSilicon / IEEE CASS UTP 2026")
    dut._log.info("  Protocolo: 14 bits serial (7A + 7B), op paralelo ui_in[3:1]")
    dut._log.info("  Reloj: %d ns (%d MHz)" % (CLK_PERIOD_NS, 1000 // CLK_PERIOD_NS))
    dut._log.info("=" * 65)

    # Iniciar reloj
    clock = Clock(dut.clk, CLK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())

    # Reset inicial robusto
    dut.ena.value    = 1
    dut.ui_in.value  = 0
    dut.uio_in.value = 0
    dut.rst_n.value  = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await FallingEdge(dut.clk)

    dut._log.info("Reset inicial completado. Iniciando casos de prueba.")
    dut._log.info("-" * 65)

    # ─────────────────────────────────────────────────────────────────────────
    # TABLA DE PRUEBAS
    # Formato: (A, B, op, expected, descripción)
    #
    # expected se calcula exactamente como lo hace el RTL (alu_7b.v):
    #   ADD/SUB : operación de 8 bits con extensión de cero → & 0xFF
    #   AND/OR/XOR : resultado de 7 bits con bit[7]=0       → & 0x7F
    # ─────────────────────────────────────────────────────────────────────────
    test_cases = [

        # ══════════════════════════════════════════════════════════════════════
        # BLOQUE A — ADD (suma, bit[7] = carry-out)
        # Referencia RTL: 3'b000: result = {1'b0, A} + {1'b0, B}
        # ══════════════════════════════════════════════════════════════════════
        (20,  30,  OP_ADD,
         (20  + 30)   & 0xFF,
         "ADD  20 +  30 =  50   [sin carry]"),

        (10,  15,  OP_ADD,
         (10  + 15)   & 0xFF,
         "ADD  10 +  15 =  25   [sin carry]"),

        (100, 100, OP_ADD,
         (100 + 100)  & 0xFF,
         "ADD 100 + 100 = 0xC8  [carry bit[7]=1]"),

        (0,   0,   OP_ADD,
         0,
         "ADD   0 +   0 = 0x00  [caso cero]"),

        (127, 1,   OP_ADD,
         (127 + 1)    & 0xFF,
         "ADD 127 +   1 = 0x80  [límite 7 bits, carry]"),

        (127, 127, OP_ADD,
         (127 + 127)  & 0xFF,
         "ADD 127 + 127 = 0xFE  [ambos máximos, carry]"),

        # ══════════════════════════════════════════════════════════════════════
        # BLOQUE B — AND (lógico, bit[7] siempre 0)
        # Referencia RTL: 3'b001: result = {1'b0, A & B}
        # ══════════════════════════════════════════════════════════════════════
        (0b1010101, 0b1100110, OP_AND,
         (0b1010101 & 0b1100110) & 0x7F,
         "AND 0x55 & 0x66 = 0x44 [máscara parcial]"),

        (0x7F, 0x00, OP_AND,
         0x00,
         "AND 0x7F & 0x00 = 0x00 [anulación]"),

        (0x7F, 0x7F, OP_AND,
         0x7F,
         "AND 0x7F & 0x7F = 0x7F [identidad]"),

        (0b0101010, 0b1010101, OP_AND,
         0x00,
         "AND 0x2A & 0x55 = 0x00 [patrón opuesto]"),

        # ══════════════════════════════════════════════════════════════════════
        # BLOQUE C — OR (lógico, bit[7] siempre 0)
        # Referencia RTL: 3'b010: result = {1'b0, A | B}
        # ══════════════════════════════════════════════════════════════════════
        (0b0101010, 0b0010101, OP_OR,
         (0b0101010 | 0b0010101) & 0x7F,
         "OR  0x2A | 0x15 = 0x3F [complementos parciales]"),

        (0x00, 0x7F, OP_OR,
         0x7F,
         "OR  0x00 | 0x7F = 0x7F [identidad OR]"),

        (0x7F, 0x7F, OP_OR,
         0x7F,
         "OR  0x7F | 0x7F = 0x7F [ambos máximos]"),

        # ══════════════════════════════════════════════════════════════════════
        # BLOQUE D — XOR (lógico, bit[7] siempre 0)
        # Referencia RTL: 3'b011: result = {1'b0, A ^ B}
        # ══════════════════════════════════════════════════════════════════════
        (0b1111111, 0b1010101, OP_XOR,
         (0b1111111 ^ 0b1010101) & 0x7F,
         "XOR 0x7F ^ 0x55 = 0x2A [diferencia]"),

        (0b1100110, 0b1100110, OP_XOR,
         0x00,
         "XOR  A   ^  A   = 0x00 [autocancelación]"),

        (0b1010101, 0b0101010, OP_XOR,
         (0b1010101 ^ 0b0101010) & 0x7F,
         "XOR 0x55 ^ 0x2A = 0x7F [alternado, todos los bits]"),

        (0x7F, 0x00, OP_XOR,
         0x7F,
         "XOR 0x7F ^ 0x00 = 0x7F [identidad XOR]"),

        # ══════════════════════════════════════════════════════════════════════
        # BLOQUE E — SUB (resta complemento a 2, bit[7] = borrow)
        # Referencia RTL: 3'b100: result = {1'b0, A} - {1'b0, B}
        # ══════════════════════════════════════════════════════════════════════
        (50,  20,  OP_SUB,
         (50  - 20)  & 0xFF,
         "SUB  50 -  20 =  30   [resultado positivo, sin borrow]"),

        (77,  77,  OP_SUB,
         0x00,
         "SUB  77 -  77 = 0x00  [A igual a B]"),

        (10,  30,  OP_SUB,
         (10  - 30)  & 0xFF,
         "SUB  10 -  30 = 0xEC  [borrow, complemento a 2]"),

        (127, 0,   OP_SUB,
         0x7F,
         "SUB 127 -   0 = 0x7F  [B=0, sin borrow]"),

    ]

    # ─────────────────────────────────────────────────────────────────────────
    # EJECUCIÓN Y VERIFICACIÓN
    # ─────────────────────────────────────────────────────────────────────────
    passed   = 0
    failed   = 0
    failures = []

    for idx, (A, B, op, expected, desc) in enumerate(test_cases):

        await reset_dut(dut)
        result, done = await run_alu(dut, A, B, op)

        ok     = (result == expected) and done
        status = "PASS" if ok else "FAIL"

        dut._log.info(
            "[%02d] %-52s  got=0x%02X  exp=0x%02X  Done=%d  [%s]"
            % (idx + 1, desc, result, expected, int(done), status)
        )

        if ok:
            passed += 1
        else:
            failed += 1
            failures.append((idx + 1, desc, result, expected, done))

    # ─────────────────────────────────────────────────────────────────────────
    # RESUMEN FINAL
    # ─────────────────────────────────────────────────────────────────────────
    dut._log.info("=" * 65)
    dut._log.info(
        "RESUMEN: %d PASS  /  %d FAIL  (total %d casos)"
        % (passed, failed, len(test_cases))
    )

    if failures:
        dut._log.error("CASOS FALLIDOS:")
        for num, desc, got, exp, d in failures:
            dut._log.error(
                "  [%02d] %s → got=0x%02X  exp=0x%02X  Done=%s  diff_bits=0x%02X"
                % (num, desc, got, exp, d, got ^ exp)
            )

    dut._log.info("=" * 65)

    # ─────────────────────────────────────────────────────────────────────────
    # ASERCIONES INDIVIDUALES
    # ─────────────────────────────────────────────────────────────────────────
    for num, desc, got, exp, d in failures:
        assert d, (
            "[%02d] %s: uio_out[0] (Done) nunca se activó. "
            "Verificar: 14 bits transmitidos, protocolo LSB-first, "
            "transición S_RECV→S_CALC en bit_count==CNT_B_END(13)."
            % (num, desc)
        )
        assert got == exp, (
            "[%02d] %s: resultado incorrecto. "
            "got=0x%02X  expected=0x%02X  bits_en_error=0x%02X"
            % (num, desc, got, exp, got ^ exp)
        )