![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg) ![](../../workflows/fpga/badge.svg)

# 7-bit ALU — Serial Input / Parallel Output

**Bootcamp IC Design & Fabrication — IEEE OpenSilicon / IEEE CASS UTP 2026**
Shuttle: SKY26a · PDK: sky130A (130 nm) · Tile: 1×1
**Author:** Sharif Obando · Discord: `sharif_g230`

---

## Project Description

This project implements a **7-bit Arithmetic Logic Unit (ALU)** designed for real silicon fabrication through the [TinyTapeout](https://tinytapeout.com) platform (shuttle SKY26a, PDK sky130A, 130 nm node).

The system receives two 7-bit operands and a 3-bit operation code **serially** (LSB first) through a single input pin, and delivers the 8-bit result **in parallel** once computation is complete. The `Done` signal pulses for exactly one clock cycle to indicate result availability.

---

## System Architecture

The design is structured in three hierarchical Verilog modules:

| Module | File | Role |
|---|---|---|
| `tt_um_alu7b` | `tt_um_alu7b.v` | TinyTapeout top-level: pin mapping and wiring |
| `serial_alu_ctrl` | `serial_alu_ctrl.v` | Serial receive FSM + shift register |
| `alu_7b` | `alu_7b.v` | Pure combinational 7-bit ALU |

### Finite State Machine (FSM)

The three-state synchronous FSM implemented in `serial_alu_ctrl` governs the full protocol:

```
          /RST=0
            │
            ▼
┌─────────────────────┐  bit_count==13   ┌──────────────┐  1 cycle  ┌──────────┐
│       S_RECV        │ ───────────────► │    S_CALC    │ ────────► │  S_DONE  │
│  Serial reception   │                  │ Latch result │           │  Result  │
│  shift-right LSB-1st│                  │   Done = 1   │           │  stable  │
└─────────────────────┘                  └──────────────┘           └──────────┘
          ▲                                                               │
          └──────────────────────── /RST = 0 ──────────────────────────────┘
```

- **S_RECV:** Serial bit capture via shift-right shift register. The incoming bit is inserted at the MSB: `reg <= {Bit_in, reg[N-1:1]}`. After N rising edges, `reg[0]` holds the original LSB.
- **S_CALC:** Registers `reg_A` and `reg_B` are stable. The combinational `alu_out` is latched into `reg_result` and `done_reg` is asserted for exactly one clock cycle.
- **S_DONE:** The result remains stable on `Data_out`. The system waits for `/RST = 0` to restart.

---

## Serial Input Protocol

Data is sent bit by bit through `ui_in[0]` (`Bit_in`), synchronised with the rising edge of `clk`, **LSB first**:

```
Rising edge  1 ..  7  → Operand A [6:0], LSB first  (bit_count 0..6)
Rising edge  8 .. 14  → Operand B [6:0], LSB first  (bit_count 7..13)
Rising edge 15        → FSM transitions to S_CALC: result ready, Done=1
```

The **opcode** `op[2:0]` is applied as a **stable parallel input** on `ui_in[3:1]` throughout the entire operation (not serialised).

### Example frame for `20 + 30 = 50`

```
A = 20 = 7'b0010100  →  send LSB first: 0, 0, 1, 0, 1, 0, 0
B = 30 = 7'b0011110  →  send LSB first: 0, 1, 1, 1, 1, 0, 0
op = 000 (ADD)       →  ui_in[3:1] = 3'b000  (parallel, stable)

Expected result: uo_out = 8'h32 = 50  |  Done = 1 at rising edge 15
```

---

## Supported Operations

| `op[2:0]` | Operation | RTL Expression | Bit[7] |
|---|---|---|---|
| `000` | **ADD** | `{1'b0,A} + {1'b0,B}` | Carry-out |
| `001` | **AND** | `{1'b0, A & B}` | 0 (always) |
| `010` | **OR** | `{1'b0, A \| B}` | 0 (always) |
| `011` | **XOR** | `{1'b0, A ^ B}` | 0 (always) |
| `100` | **SUB** | `{1'b0,A} - {1'b0,B}` | Borrow (two's complement) |

> **Bit[7] of result:** In addition it indicates carry-out; in subtraction it indicates borrow (negative result in 8-bit two's complement). For logical operations (AND, OR, XOR) bit[7] is always `0`.

---

## Pin Map

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

## Repository Structure

```
myBootcampChip/
├── src/
│   ├── alu_7b.v             ← Pure combinational 7-bit ALU (leaf module)
│   ├── serial_alu_ctrl.v    ← FSM + shift register + ALU instantiation
│   ├── tt_um_alu7b.v        ← TinyTapeout top-level (pin mapping)
│   ├── project.v            ← Synthesis entry point (empty — no logic)
│   └── config.json          ← LibreLane / OpenLane configuration
├── test/
│   ├── test.py              ← cocotb testbench (20 test cases)
│   ├── tb.v                 ← Verilog wrapper for cocotb
│   ├── serial_tb.v          ← Native Verilog testbench (20 cases, Icarus)
│   ├── Makefile             ← RTL and gate-level build
│   ├── tb.gtkw              ← GTKWave signal configuration
│   ├── requirements.txt     ← Python dependencies (pytest, cocotb)
│   └── README.md            ← Simulation instructions
├── docs/
│   └── info.md              ← Project datasheet
├── .github/workflows/
│   ├── gds.yaml             ← Full GDS flow + precheck + GL test + viewer
│   ├── test.yaml            ← RTL test CI (iverilog + cocotb)
│   ├── docs.yaml            ← Documentation build
│   └── fpga.yaml            ← FPGA bitstream (ICE40UP5K)
├── .devcontainer/
│   ├── Dockerfile           ← Environment with LibreLane, iverilog, cocotb, Verible
│   ├── devcontainer.json    ← VS Code Dev Container configuration
│   └── copy_tt_support_tools.sh
├── .vscode/
│   ├── settings.json        ← Linting (Verilator) and formatting (Verible)
│   └── extensions.json      ← Recommended extensions
├── info.yaml                ← TinyTapeout project metadata
├── .gitignore
├── LICENSE                  ← Apache 2.0
└── README.md                ← This file
```

---

## Getting Started

### 1. Clone the repository

```bash
git clone https://github.com/<your-username>/myBootcampChip.git
cd myBootcampChip
```

### 2. Run RTL simulation

```bash
cd test
pip install -r requirements.txt   # pytest==8.4.2  cocotb==2.0.1
make -B
```

The output prints a summary of all 20 test cases. To check for failures:

```bash
! grep failure results.xml
```

### 3. Native Verilog simulation (without cocotb)

```bash
cd src
iverilog -o serial_tb.vvp ../test/serial_tb.v serial_alu_ctrl.v alu_7b.v
vvp serial_tb.vvp
```

### 4. View waveforms

```bash
# GTKWave (loads signal configuration automatically)
gtkwave test/tb.fst test/tb.gtkw

# Surfer
surfer test/tb.fst
```

### 5. Synthesis with LibreLane (inside devcontainer or IIC-OSIC-TOOLS)

```bash
cd src
librelane config.json
# View layout:
librelane --last-run --flow OpenInKlayout config.json
```

### 6. Gate-level simulation

After completing the synthesis flow, copy the netlist and run:

```bash
cp runs/<RUN_FOLDER>/final/pnl/tt_um_alu7b.pnl.v test/gate_level_netlist.v
cd test
make -B GATES=yes
```

---

## Test Coverage

The cocotb testbench (`test/test.py`) runs **20 test cases** covering all operations with edge-case scenarios:

| Operation | Cases | Scenarios covered |
|---|---|---|
| **ADD** | 6 | Normal (×2), carry (100+100), zero (0+0), limit (127+1), both max (127+127) |
| **AND** | 4 | Partial mask, annihilation (&0), identity (&0x7F), crossed opposite pattern |
| **OR** | 3 | Partial complements, identity (\|0), both max |
| **XOR** | 4 | Difference, self-cancellation (A⊕A=0), full alternating, identity (A⊕0) |
| **SUB** | 3 | Positive no-borrow, A=B (zero), two's complement underflow |

Each case verifies simultaneously:
1. `uo_out[7:0]` exactly matches the expected result computed as `(A OP B) & 0xFF`.
2. `uio_out[0]` (Done) is asserted for **exactly one clock cycle** within a 4-edge capture window after the 14 transmitted bits.

The native Verilog testbench (`test/serial_tb.v`) runs **20 additional cases** compatible with Icarus Verilog, including 5 extended cases (Block F) that complement coverage.

---

## Development Environment

The devcontainer includes the following pre-installed tools:

| Tool | Version / Role |
|---|---|
| **LibreLane** | 2.4.2 — Open-source synthesis flow |
| **iverilog** | RTL Verilog simulation |
| **cocotb** | 2.0.1 — Python-based testbench framework |
| **pytest** | 8.4.2 — XML test result reporting |
| **Verilator** | RTL linting |
| **Verible** | Verilog code formatting |
| **GTKWave** | Waveform viewer (.fst / .vcd) |
| **PDK** | sky130A — SkyWater 130 nm process |

---

## TinyTapeout Resources

- [FAQ](https://tinytapeout.com/faq/)
- [Digital design lessons](https://tinytapeout.com/digital_design/)
- [Specifications](https://tinytapeout.com/specs)
- [SKY26a shuttle](https://app.tinytapeout.com/shuttles/ttsky26a)
- [Discord community](https://tinytapeout.com/discord)
- [Build locally](https://www.tinytapeout.com/guides/local-hardening/)

---

## License

Copyright 2026 Bootcamp IEEE OpenSilicon / IEEE CASS UTP.
Distributed under the [Apache 2.0](LICENSE) license.
