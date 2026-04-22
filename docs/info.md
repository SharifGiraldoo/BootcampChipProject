# 7-bit ALU — Serial Input / Parallel Output

**Bootcamp IC Design & Fabrication — IEEE OpenSilicon / IEEE CASS UTP 2026**
**Author:** Sharif Obando · Discord: `sharif_g230`
**Shuttle:** SKY26a · **PDK:** sky130A (130 nm) · **Tile:** 1×1

---

## Overview

This project implements a **7-bit Arithmetic Logic Unit (ALU)** for fabrication on TinyTapeout (shuttle SKY26a, PDK sky130A, 130 nm node).

The system receives two 7-bit operands and a 3-bit operation code **serially** (LSB first) through a single input pin (`ui_in[0]`). The 8-bit result is presented **in parallel** on `uo_out[7:0]` once computation is complete, accompanied by a one-cycle pulse on `uio_out[0]` (`Done`).

---

## How it works

### Module hierarchy

```
tt_um_alu7b  (TinyTapeout top-level — tt_um_alu7b.v)
    └── serial_alu_ctrl  (FSM + shift register — serial_alu_ctrl.v)
            └── alu_7b   (combinational ALU — alu_7b.v)
```

### Serial input protocol

Data is sent bit by bit through `ui_in[0]` (`Bit_in`), synchronised with the rising edge of `clk`, **LSB first**:

| Clock edge(s) | Data received |
|---|---|
| 1 .. 7 | Operand A [6:0], LSB first |
| 8 .. 14 | Operand B [6:0], LSB first |
| 15 (automatic) | FSM → S_CALC: result ready, Done = 1 |

The **opcode** `op[2:0]` is applied as a **stable parallel input** on `ui_in[3:1]` throughout the entire operation.

### Shift register mechanism (shift-right, LSB first)

The serial capture uses a shift-right shift register with the new bit entering at the MSB:

```verilog
reg_A <= { Bit_in, reg_A[6:1] };   // Edges 0..6  → Operand A
reg_B <= { Bit_in, reg_B[6:1] };   // Edges 7..13 → Operand B
```

After N capture edges, `reg[0]` holds the first received bit (LSB) and `reg[N-1]` holds the last (MSB), correctly reconstructing the original operand.

### Supported operations

| `op[2:0]` | Operation | RTL Expression | Bit[7] of result |
|---|---|---|---|
| `000` | **ADD** | `{1'b0,A} + {1'b0,B}` | Carry-out |
| `001` | **AND** | `{1'b0, A & B}` | 0 (always) |
| `010` | **OR** | `{1'b0, A \| B}` | 0 (always) |
| `011` | **XOR** | `{1'b0, A ^ B}` | 0 (always) |
| `100` | **SUB** | `{1'b0,A} - {1'b0,B}` | Borrow (two's complement) |

> **Bit[7]:** In addition it indicates carry-out; in subtraction it indicates borrow (negative result in 8-bit two's complement). For AND, OR and XOR bit[7] is always `0`.

### State machine (FSM)

The design implements a three-state synchronous FSM with active-low reset:

```
          /RST=0
            │
            ▼
┌─────────────────────┐  bit_count==13   ┌──────────────┐  1 cycle  ┌──────────┐
│       S_RECV        │ ───────────────► │    S_CALC    │ ────────► │  S_DONE  │
│  Serial reception   │                  │  Latch ALU   │           │  Result  │
│  shift-right        │                  │   Done = 1   │           │  stable  │
└─────────────────────┘                  └──────────────┘           └──────────┘
          ▲                                                               │
          └──────────────────────── /RST = 0 ──────────────────────────────┘
```

- **S_RECV:** Bit-by-bit capture via shift register. Counter `bit_count` advances from 0 to 13 (14 bits = 7A + 7B). At `CNT_B_END = 13` the FSM transitions to S_CALC.
- **S_CALC:** `reg_A` and `reg_B` are stable; the combinational ALU (`alu_out`) already holds the correct result. It is latched into `reg_result` and `done_reg` is asserted for exactly one clock cycle.
- **S_DONE:** The result is stable on `Data_out`. The system remains here until `/RST = 0` initiates a new operation cycle.

---

## Pin map

### Inputs

| Pin | Signal | Description |
|---|---|---|
| `ui[0]` | `Bit_in` | Serial data input (LSB first: 7b A, 7b B) |
| `ui[1]` | `op[0]` | Opcode bit 0 (LSB) — stable parallel input |
| `ui[2]` | `op[1]` | Opcode bit 1 |
| `ui[3]` | `op[2]` | Opcode bit 2 (MSB) |
| `ui[7:4]` | — | Unused |
| `clk` | CLK | System clock (up to 50 MHz) |
| `rst_n` | /RST | Active-low reset — returns FSM to S_RECV |

### Outputs

| Pin | Signal | Description |
|---|---|---|
| `uo[6:0]` | `Data_out[6:0]` | 7-bit result (LSB at `uo[0]`) |
| `uo[7]` | `Data_out[7]` | Carry (ADD) or Borrow (SUB) |
| `uio[0]` | `Done` | One-cycle high pulse when operation is complete |
| `uio[7:1]` | — | Unused (always `0`) |

> `uio_oe = 8'b0000_0001`: only `uio[0]` is configured as an output.

---

## How to test

### Operating procedure

1. Assert reset: `rst_n = 0` for at least 2 clock cycles.
2. Release reset: `rst_n = 1`.
3. Set `ui_in[3:1]` to the desired opcode (stable throughout the operation).
4. Send the **7 bits of Operand A** through `ui[0]`, LSB first, one bit per rising edge.
5. Send the **7 bits of Operand B** through `ui[0]`, LSB first.
6. Wait **1 additional clock cycle** (automatic S_CALC transition).
7. Read the result on `uo_out[7:0]`.
8. Verify that `uio_out[0]` (Done) is `1` for exactly one clock cycle.
9. For a new operation, return to step 1 (reset).

### Example: 20 + 30 = 50

```
Operand A = 20 = 7'b0010100  →  send LSB first: 0, 0, 1, 0, 1, 0, 0
Operand B = 30 = 7'b0011110  →  send LSB first: 0, 1, 1, 1, 1, 0, 0
Opcode = 000 (ADD)           →  ui_in[3:1] = 3'b000  (parallel)

Expected result: uo_out = 8'h32 = 50  |  Done = 1 at edge 15
```

### Example: 10 - 30 (two's complement underflow)

```
Operand A = 10, Operand B = 30, op = 3'b100 (SUB)
Result = (10 - 30) & 0xFF = 0xEC = 236
Bit[7] = 1  →  indicates borrow (negative result in two's complement)
```

### Example: 100 + 100 (carry-out)

```
Operand A = 100, Operand B = 100, op = 3'b000 (ADD)
Result = (100 + 100) & 0xFF = 0xC8 = 200
Bit[7] = 1  →  indicates carry-out (sum exceeds 127, the 7-bit range)
```

---

## Test coverage

The cocotb testbench (`test/test.py`) runs **20 test cases** covering all operations with edge-case scenarios:

| Operation | Cases | Scenarios covered |
|---|---|---|
| **ADD** | 6 | Normal (×2), carry (100+100), zero (0+0), limit (127+1), both max (127+127) |
| **AND** | 4 | Partial mask, annihilation (&0), identity (&0x7F), crossed opposite pattern |
| **OR** | 3 | Partial complements, identity (\|0), both max |
| **XOR** | 4 | Difference, self-cancellation (A⊕A=0), full alternating, identity (A⊕0) |
| **SUB** | 3 | Positive no-borrow, A=B (zero), two's complement underflow |

Each case verifies:
- `uo_out[7:0]` exactly matches the expected value computed in Python as `(A OP B) & 0xFF`.
- `uio_out[0]` (Done) is asserted for **exactly one cycle** within a 4-edge capture window after the 14 transmitted bits.

The native Verilog testbench (`test/serial_tb.v`) runs **20 additional cases** compatible with Icarus Verilog, including 5 extended cases (Block F) that complement coverage.

---

## External hardware

No external hardware is required for basic operation.

Optional hardware for demonstration:

- LEDs connected to `uo_out[7:0]` for result visualisation
- Push buttons for manual serial input and clock stepping
- Logic analyser for waveform inspection
- FPGA board or TinyTapeout DevKit
