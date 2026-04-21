# SPDX-FileCopyrightText: © 2026 Bootcamp IEEE OpenSilicon / IEEE CASS UTP
# SPDX-License-Identifier: Apache-2.0

"""
test.py — cocotb testbench para tt_um_alu7b
============================================

Módulo bajo prueba (DUT): tt_um_alu7b  (instanciado en tb.v como user_project)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ARQUITECTURA DEL SISTEMA — DOS MÓDULOS RTL COMPLEMENTARIOS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  serial_alu_ctrl.v  (verificado por serial_tb.v, Icarus Verilog)
  ┌──────────────────────────────────────────────────────────────┐
  │  Protocolo : 14 bits seriales (7 bits A + 7 bits B), LSB-1st │
  │  Opcode    : puerto PARALELO op[2:0]                          │
  │  CNT_B_END : 5'd13 → transición a S_CALC en posedge 14       │
  │  Done      : posedge 15 (S_CALC), pulso de 1 ciclo           │
  │  Testbench : serial_tb.v — 20 casos Icarus Verilog           │
  └──────────────────────────────────────────────────────────────┘

  tt_um_alu7b.v  (verificado por este archivo, cocotb)
  ┌──────────────────────────────────────────────────────────────┐
  │  Protocolo : 17 bits seriales (7A + 7B + 3op), LSB-1st       │
  │  Opcode    : llega también en SERIE (bits 14..16)            │
  │  CNT_OP_END: 5'd16 → transición a S_CALC en posedge 17       │
  │  Done      : posedge 18 (S_CALC), pulso de 1 ciclo           │
  │              en uio_out[0]                                    │
  │  Testbench : test.py — 20 casos cocotb                       │
  └──────────────────────────────────────────────────────────────┘

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PROTOCOLO SERIAL tt_um_alu7b (referencia RTL: tt_um_alu7b.v)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Posedge  1 ..  7  → Operando A [6:0], LSB primero  (bit_count 0..6)
  Posedge  8 .. 14  → Operando B [6:0], LSB primero  (bit_count 7..13)
  Posedge 15 .. 17  → Opcode   [2:0], LSB primero    (bit_count 14..16)
  Posedge 18        → S_CALC: reg_result←alu_out, done_reg←1, uo_out válido

Mecanismo shift-right (RTL, líneas ~76-80 de tt_um_alu7b.v):
  reg_A  <= {bit_in, reg_A[6:1]}   → A[0] primer bit, queda en reg_A[0]
  reg_B  <= {bit_in, reg_B[6:1]}   → idem para B
  reg_op <= {bit_in, reg_op[2:1]}  → idem para opcode
  Enviar en orden bit[0]→bit[N-1] (LSB primero) ✓

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
TABLA DE OPERACIONES (referencia alu_7b.v)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  000 → ADD  result = {1'b0,A} + {1'b0,B}  [8 bits]  bit[7]=carry-out
  001 → AND  result = {1'b0, A & B}                   bit[7]=0
  010 → OR   result = {1'b0, A | B}                   bit[7]=0
  011 → XOR  result = {1'b0, A ^ B}                   bit[7]=0
  100 → SUB  result = {1'b0,A} - {1'b0,B}  [8 bits]  bit[7]=borrow (C2)
  default → 8'b0

  En Python (A, B ∈ [0, 127]):
    ADD expected = (A + B) & 0xFF
    SUB expected = (A - B) & 0xFF   (complemento a 2 de 8 bits)
    AND expected = (A & B) & 0x7F   (bit[7] siempre 0)
    OR  expected = (A | B) & 0x7F
    XOR expected = (A ^ B) & 0x7F

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
COBERTURA DE PRUEBAS (20 casos)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  ADD (6): normal, carry, cero, límite 7-bit, ambos_max, identidad (A+0)
  AND (4): máscara, con_cero, identidad, patrón_cruzado
  OR  (3): complementos, identidad, ambos_max
  XOR (4): diferencia, autocancelación, patrón_alternado, identidad (A^0)
  SUB (3): normal, A=B→cero, underflow_complemento2 + caso B=0

  Alineación con serial_tb.v Bloques A-F:
    ADD 127+127=254 (carry)   ← Bloque F.1
    SUB 127-0 =127 (sin borrow) ← Bloque F.2
    XOR 0b1010101^0b0101010=0x7F ← Bloque F.3
    OR  0x7F|0x7F=0x7F           ← Bloque F.4
    AND 0b0101010&0b1010101=0    ← Bloque F.5
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, FallingEdge

# ── Opcodes (coinciden con alu_7b.v, tt_um_alu7b.v y serial_tb.v) ────────────
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
# sin un FallingEdge extra, alineando correctamente los 17 posedges
# de captura con bit_count 0..16 del RTL.
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
# Envía 17 bits seriales LSB-first: A[6:0] + B[6:0] + op[2:0].
# Precondición: control en FallingEdge (tras reset_dut).
#
# Temporización:
#   bit[0]   : presentar dato → RisingEdge (sin FallingEdge previo)
#   bit[i>0] : FallingEdge → presentar dato → RisingEdge
#
# Tras 17 posedges (bit_count llega a CNT_OP_END=16), la FSM transiciona
# de S_RECV a S_CALC. En el posedge 18 (S_CALC) se latchea el resultado
# y done_reg se activa por 1 ciclo.
#
# Ventana de captura de Done: hasta 4 iteraciones FallingEdge→RisingEdge.
# En condiciones normales Done aparece en la primera iteración (posedge 18).
# ─────────────────────────────────────────────────────────────────────────────
async def run_alu(dut, A, B, op):
    """
    Transmite 17 bits seriales (A + B + op, LSB-first).
    Retorna (result: int, done_seen: bool).
    """
    # Secuencia: 7 bits de A (LSB→MSB) + 7 bits de B + 3 bits de op
    bits  = [(A  >> i) & 1 for i in range(7)]
    bits += [(B  >> i) & 1 for i in range(7)]
    bits += [(op >> i) & 1 for i in range(3)]
    # Total: 17 bits → 17 posedges de captura (bit_count 0..16)

    for i, bit in enumerate(bits):
        if i > 0:
            await FallingEdge(dut.clk)   # Setup window: semiciclo bajo
        dut.ui_in.value = int(bit)       # Dato estable antes del posedge
        await RisingEdge(dut.clk)        # Posedge: DUT captura bit_count=i

    # Limpiar entrada y esperar pulso de Done en uio_out[0]
    dut.ui_in.value = 0
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
    la especificación del RETO_DEL_BOOTCAMP y serial_tb.v Bloques A-F.
    """
    dut._log.info("=" * 65)
    dut._log.info("  tt_um_alu7b — Bootcamp IEEE OpenSilicon / IEEE CASS UTP 2026")
    dut._log.info("  Protocolo: 17 bits serial (7A + 7B + 3op), LSB-first")
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
        # A.1 Suma normal sin carry
        (20,  30,  OP_ADD,
         (20  + 30)   & 0xFF,
         "ADD  20 +  30 =  50   [sin carry]"),

        # A.2 Segunda suma normal sin carry
        (10,  15,  OP_ADD,
         (10  + 15)   & 0xFF,
         "ADD  10 +  15 =  25   [sin carry]"),

        # A.3 Suma con carry: 100+100=200 → bit[7]=1 (complemento C2)
        (100, 100, OP_ADD,
         (100 + 100)  & 0xFF,
         "ADD 100 + 100 = 0xC8  [carry bit[7]=1]"),

        # A.4 Suma con ambos operandos cero
        (0,   0,   OP_ADD,
         0,
         "ADD   0 +   0 = 0x00  [caso cero]"),

        # A.5 Límite de 7 bits: 127+1=128 → bit[7]=1
        (127, 1,   OP_ADD,
         (127 + 1)    & 0xFF,
         "ADD 127 +   1 = 0x80  [límite 7 bits, carry]"),

        # A.6 Ambos operandos en máximo: 127+127=254 → Bloque F.1 serial_tb.v
        (127, 127, OP_ADD,
         (127 + 127)  & 0xFF,
         "ADD 127 + 127 = 0xFE  [ambos máximos, carry]"),

        # ══════════════════════════════════════════════════════════════════════
        # BLOQUE B — AND (lógico, bit[7] siempre 0)
        # Referencia RTL: 3'b001: result = {1'b0, A & B}
        # ══════════════════════════════════════════════════════════════════════
        # B.1 Máscara parcial
        (0b1010101, 0b1100110, OP_AND,
         (0b1010101 & 0b1100110) & 0x7F,
         "AND 0x55 & 0x66 = 0x44 [máscara parcial]"),

        # B.2 AND con cero → resultado siempre cero
        (0x7F, 0x00, OP_AND,
         0x00,
         "AND 0x7F & 0x00 = 0x00 [anulación]"),

        # B.3 AND identidad (A & A = A)
        (0x7F, 0x7F, OP_AND,
         0x7F,
         "AND 0x7F & 0x7F = 0x7F [identidad]"),

        # B.4 Patrón cruzado alternado → resultado cero  (Bloque F.5 serial_tb.v)
        (0b0101010, 0b1010101, OP_AND,
         0x00,
         "AND 0x2A & 0x55 = 0x00 [patrón opuesto]"),

        # ══════════════════════════════════════════════════════════════════════
        # BLOQUE C — OR (lógico, bit[7] siempre 0)
        # Referencia RTL: 3'b010: result = {1'b0, A | B}
        # ══════════════════════════════════════════════════════════════════════
        # C.1 OR de complementos a 1: 0b0101010 | 0b0010101 = 0x3F
        (0b0101010, 0b0010101, OP_OR,
         (0b0101010 | 0b0010101) & 0x7F,
         "OR  0x2A | 0x15 = 0x3F [complementos parciales]"),

        # C.2 OR identidad: 0 | 0x7F = 0x7F
        (0x00, 0x7F, OP_OR,
         0x7F,
         "OR  0x00 | 0x7F = 0x7F [identidad OR]"),

        # C.3 Ambos operandos máximos   (Bloque F.4 serial_tb.v)
        (0x7F, 0x7F, OP_OR,
         0x7F,
         "OR  0x7F | 0x7F = 0x7F [ambos máximos]"),

        # ══════════════════════════════════════════════════════════════════════
        # BLOQUE D — XOR (lógico, bit[7] siempre 0)
        # Referencia RTL: 3'b011: result = {1'b0, A ^ B}
        # ══════════════════════════════════════════════════════════════════════
        # D.1 XOR diferencia: 0x7F ^ 0x55 = 0x2A
        (0b1111111, 0b1010101, OP_XOR,
         (0b1111111 ^ 0b1010101) & 0x7F,
         "XOR 0x7F ^ 0x55 = 0x2A [diferencia]"),

        # D.2 Autocancelación: A ^ A = 0
        (0b1100110, 0b1100110, OP_XOR,
         0x00,
         "XOR  A   ^  A   = 0x00 [autocancelación]"),

        # D.3 Patrón alternado cruzado: 0b1010101 ^ 0b0101010 = 0x7F  (Bloque F.3)
        (0b1010101, 0b0101010, OP_XOR,
         (0b1010101 ^ 0b0101010) & 0x7F,
         "XOR 0x55 ^ 0x2A = 0x7F [alternado, todos los bits]"),

        # D.4 XOR identidad: A ^ 0 = A
        (0x7F, 0x00, OP_XOR,
         0x7F,
         "XOR 0x7F ^ 0x00 = 0x7F [identidad XOR]"),

        # ══════════════════════════════════════════════════════════════════════
        # BLOQUE E — SUB (resta complemento a 2, bit[7] = borrow)
        # Referencia RTL: 3'b100: result = {1'b0, A} - {1'b0, B}
        # bit[7]=1 → borrow (resultado negativo en C2)
        # Python: (A - B) & 0xFF reproduce exactamente el comportamiento RTL
        # ══════════════════════════════════════════════════════════════════════
        # E.1 Resta positiva normal: 50 - 20 = 30
        (50,  20,  OP_SUB,
         (50  - 20)  & 0xFF,
         "SUB  50 -  20 =  30   [resultado positivo, sin borrow]"),

        # E.2 Resta A = B: resultado exactamente cero
        (77,  77,  OP_SUB,
         0x00,
         "SUB  77 -  77 = 0x00  [A igual a B]"),

        # E.3 Underflow: 10 - 30 → borrow, resultado en C2 = 0xEC
        (10,  30,  OP_SUB,
         (10  - 30)  & 0xFF,
         "SUB  10 -  30 = 0xEC  [borrow, complemento a 2]"),

        # E.4 B = 0, sin borrow: 127 - 0 = 127   (Bloque F.2 serial_tb.v)
        (127, 0,   OP_SUB,
         0x7F,
         "SUB 127 -   0 = 0x7F  [B=0, sin borrow]"),

    ]

    # ─────────────────────────────────────────────────────────────────────────
    # EJECUCIÓN Y VERIFICACIÓN
    # ─────────────────────────────────────────────────────────────────────────
    passed   = 0
    failed   = 0
    failures = []   # (num, desc, got, exp, done)

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
    # cocotb reporta cada aserción fallida de forma independiente en el XML.
    # Se itera sobre los fallos acumulados para no interrumpir el log completo.
    # ─────────────────────────────────────────────────────────────────────────
    for num, desc, got, exp, d in failures:
        assert d, (
            "[%02d] %s: uio_out[0] (Done) nunca se activó. "
            "Verificar: 17 bits transmitidos, protocolo LSB-first, "
            "transición S_RECV→S_CALC en bit_count==CNT_OP_END(16)."
            % (num, desc)
        )
        assert got == exp, (
            "[%02d] %s: resultado incorrecto. "
            "got=0x%02X  expected=0x%02X  bits_en_error=0x%02X"
            % (num, desc, got, exp, got ^ exp)
        )