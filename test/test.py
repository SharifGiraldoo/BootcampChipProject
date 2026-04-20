# SPDX-FileCopyrightText: © 2026 Bootcamp IEEE OpenSilicon / IEEE CASS UTP
# SPDX-License-Identifier: Apache-2.0

"""
test.py — Banco de pruebas cocotb para tt_um_alu7b
============================================================

Protocolo (17 posedges de captura + 1 posedge S_CALC):

  Posedge  1.. 7  → Operando A [6:0], LSB primero, por ui_in[0]
  Posedge  8..14  → Operando B [6:0], LSB primero, por ui_in[0]
  Posedge 15..17  → Opcode    [2:0], LSB primero, por ui_in[0]
  Posedge 18      → FSM S_CALC: Done=1, resultado en uo_out

Secuencia dentro de run_alu():
  reset_dut() termina en FallingEdge → semiciclo bajo listo para bit[0].
  • bit[0]: poner dato inmediatamente → RisingEdge (captura)
  • bit[1..16]: FallingEdge → poner dato → RisingEdge (captura)
  Esto garantiza exactamente 17 posedges de captura sin offset.

Operaciones (op[2:0]):
  000=Suma  001=AND  010=OR  011=XOR  100=Resta
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, FallingEdge

# ── Constantes de opcode ──────────────────────────────────────────────────────
OP_ADD = 0b000
OP_AND = 0b001
OP_OR  = 0b010
OP_XOR = 0b011
OP_SUB = 0b100

CLK_PERIOD_NS = 10   # Periodo de reloj: 10 ns → 100 MHz


# ─────────────────────────────────────────────────────────────────────────────
# Función auxiliar: reset
# Termina en FallingEdge para que el siguiente bit se alinee sin offset.
# ─────────────────────────────────────────────────────────────────────────────
async def reset_dut(dut):
    """Aplica reset activo bajo y deja el control en semiciclo bajo."""
    dut.rst_n.value  = 0
    dut.ui_in.value  = 0
    dut.uio_in.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await FallingEdge(dut.clk)   # posicionar en semiciclo bajo


# ─────────────────────────────────────────────────────────────────────────────
# Función auxiliar: envío serial y captura de resultado
# ─────────────────────────────────────────────────────────────────────────────
async def run_alu(dut, A, B, op):
    """
    Envía 17 bits seriales LSB-first y retorna (resultado, done_visto).

    Precondición: llamar justo después de reset_dut(), que deja el
    control en FallingEdge. El primer bit se presenta sin FallingEdge
    adicional, evitando un offset de +1 ciclo.
    """
    # Construir secuencia de bits: A (7) + B (7) + op (3) = 17 bits
    bits  = [(A  >> i) & 1 for i in range(7)]
    bits += [(B  >> i) & 1 for i in range(7)]
    bits += [(op >> i) & 1 for i in range(3)]

    for i, bit in enumerate(bits):
        if i > 0:
            await FallingEdge(dut.clk)  # semiciclo bajo para bits 1..16
        dut.ui_in.value = int(bit)      # dato estable antes del posedge
        await RisingEdge(dut.clk)       # posedge: DUT captura el bit

    # Esperar el posedge de S_CALC (exactamente 1 ciclo tras el bit 16)
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
# Test principal
# ─────────────────────────────────────────────────────────────────────────────
@cocotb.test()
async def test_project(dut):
    """Prueba completa de la ALU de 7 bits — todas las operaciones."""
    dut._log.info("Iniciando pruebas de tt_um_alu7b")

    # Arrancar reloj
    clock = Clock(dut.clk, CLK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())

    # Reset inicial
    dut._log.info("Aplicando reset inicial")
    dut.ena.value    = 1
    dut.ui_in.value  = 0
    dut.uio_in.value = 0
    dut.rst_n.value  = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await FallingEdge(dut.clk)

    dut._log.info("Comenzando casos de prueba")

    # ── Tabla de casos de prueba: (A, B, op, esperado, descripción) ──────────
    test_cases = [
        # ── Suma ──────────────────────────────────────────────────────────────
        (20,  30,  OP_ADD, (20  + 30)  & 0xFF, "ADD  20 +  30 =  50"),
        (10,  15,  OP_ADD, (10  + 15)  & 0xFF, "ADD  10 +  15 =  25"),
        (100, 100, OP_ADD, (100 + 100) & 0xFF, "ADD 100 + 100 = 200 (carry en bit 7)"),
        (0,   0,   OP_ADD, 0,                  "ADD   0 +   0 =   0"),
        (127, 1,   OP_ADD, (127 + 1)   & 0xFF, "ADD 127 +   1 = 128"),
        # ── AND ───────────────────────────────────────────────────────────────
        (0b1010101, 0b1100110, OP_AND,
         (0b1010101 & 0b1100110) & 0xFF,        "AND 0x55 & 0x66 = 0x44"),
        (0x7F, 0x00, OP_AND, 0x00,              "AND 0x7F & 0x00 = 0x00"),
        (0x7F, 0x7F, OP_AND, 0x7F,              "AND 0x7F & 0x7F = 0x7F"),
        # ── OR ────────────────────────────────────────────────────────────────
        (0b0101010, 0b0010101, OP_OR,
         (0b0101010 | 0b0010101) & 0xFF,         "OR  0x2A | 0x15 = 0x3F"),
        (0x00, 0x7F, OP_OR, 0x7F,               "OR  0x00 | 0x7F = 0x7F"),
        # ── XOR ───────────────────────────────────────────────────────────────
        (0b1111111, 0b1010101, OP_XOR,
         (0b1111111 ^ 0b1010101) & 0xFF,         "XOR 0x7F ^ 0x55 = 0x2A"),
        (0b1100110, 0b1100110, OP_XOR, 0,        "XOR  A  ^  A  =   0"),
        # ── Resta ─────────────────────────────────────────────────────────────
        (50,  20,  OP_SUB, (50  - 20)  & 0xFF,  "SUB  50 -  20 =  30"),
        (77,  77,  OP_SUB, 0,                    "SUB   A -  A  =   0"),
        (10,  30,  OP_SUB, (10  - 30)  & 0xFF,  "SUB  10 -  30 (underflow C2)"),
    ]

    # ── Ejecución de casos ────────────────────────────────────────────────────
    passed = 0
    failed = 0

    for idx, (A, B, op, expected, desc) in enumerate(test_cases):
        await reset_dut(dut)
        result, done = await run_alu(dut, A, B, op)

        ok = (result == expected) and done
        status = "PASS" if ok else "FAIL"

        dut._log.info(
            f"[{idx+1:02d}] {desc:<45s}  "
            f"got=0x{result:02X}  exp=0x{expected:02X}  "
            f"Done={int(done)}  [{status}]"
        )

        if ok:
            passed += 1
        else:
            failed += 1

        assert done, \
            f"[{idx+1}] {desc}: Done nunca se activó (uio_out[0] siempre 0)"
        assert result == expected, \
            f"[{idx+1}] {desc}: got=0x{result:02X}, esperado=0x{expected:02X}"

    # ── Resumen ───────────────────────────────────────────────────────────────
    dut._log.info(
        f"──────────────────────────────────────────────────────────────"
    )
    dut._log.info(
        f"RESUMEN: {passed} PASS  /  {failed} FAIL  "
        f"(total {len(test_cases)} casos)"
    )
    dut._log.info(
        f"──────────────────────────────────────────────────────────────"
    )
