![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg) ![](../../workflows/fpga/badge.svg)

# IEEE 7-bit ALU — Serial Input / Parallel Output

**Bootcamp IC Design & Fabrication — IEEE OpenSilicon / IEEE CASS UTP 2026**  
Shuttle: SKY26a · PDK: sky130A (130 nm) · Tile: 1×1  
**Author:** Sharif Obando · Discord: `sharif_g230`

---

## Project Description

This project implements a **7-bit Arithmetic Logic Unit (ALU)** designed for real silicon fabrication through the [TinyTapeout](https://tinytapeout.com) platform (shuttle SKY26a, PDK sky130A, 130 nm node), in the context of the Bootcamp IC Design & Fabrication organised by IEEE OpenSilicon and IEEE CASS at Universidad Tecnológica de Pereira (UTP), 2026.

The system receives two 7-bit operands **serially** (LSB first) through a single input pin (`ui_in[0]`), and delivers the 8-bit result **in parallel** on `uo_out[7:0]` once computation is complete. The `Done` signal pulses for exactly one clock cycle on `uio_out[0]` to indicate result availability.

The design targets a maximum clock frequency of **50 MHz**, which is the upper bound for TinyTapeout digital I/O bandwidth.

---

## System Architecture

The design is structured in three hierarchical synthesisable Verilog modules:

| Module | File | Role |
|---|---|---|
| `tt_um_alu7b` | `src/tt_um_alu7b.v` | TinyTapeout top-level: TT pin mapping and module wiring |
| `serial_alu_ctrl` | `src/serial_alu_ctrl.v` | Serial receive FSM + shift register + ALU instantiation |
| `alu_7b` | `src/alu_7b.v` | Pure combinational 7-bit ALU (leaf module) |

### Module Hierarchy

```
tt_um_alu7b  (top-level, TinyTapeout interface)
└── serial_alu_ctrl  (FSM + shift register controller)
    └── alu_7b  (combinational ALU — leaf module)
```

### Finite State Machine (FSM)

`serial_alu_ctrl` implements a three-state synchronous Moore FSM that governs the complete serial-to-parallel reception and computation protocol:

```
          rst_n = 0
              │
              ▼
┌─────────────────────┐  bit_count == 13   ┌──────────────┐  1 cycle  ┌──────────────┐
│       S_RECV        │ ─────────────────► │    S_CALC    │ ────────► │   S_DONE     │
│   Serial reception  │                    │ Latch result │           │ Result stable │
│  shift-right LSB-1st│                    │   Done = 1   │           │ awaiting /RST │
└─────────────────────┘                    └──────────────┘           └──────────────┘
          ▲                                                                    │
          └──────────────────────── rst_n = 0 ──────────────────────────────────┘
```

**State descriptions:**

- **S_RECV:** On each rising clock edge, the incoming serial bit is inserted at the MSB of the target register using a shift-right mechanism: `reg <= {Bit_in, reg[N-1:1]}`. After 7 rising edges, `reg_A` is fully loaded; after the next 7, `reg_B` is loaded. When `bit_count` reaches 13 (14 bits total), the FSM transitions to `S_CALC`.
- **S_CALC:** Registers `reg_A` and `reg_B` are stable. The combinational ALU output `alu_out` (which has been computing continuously) is latched into `reg_result`, and `done_reg` is asserted for exactly one clock cycle. FSM moves to `S_DONE`.
- **S_DONE:** The result remains stable on `Data_out`. The system remains here until `rst_n = 0` is asserted, which returns the FSM to `S_RECV` and clears all registers for the next operation.

---

## Serial Input Protocol

Data is sent bit-by-bit through `ui_in[0]` (`Bit_in`), captured on the **rising edge** of `clk`, **LSB first**:

```
Rising edge  1 ..  7  → Operand A [6:0], LSB first  (bit_count 0..6)
Rising edge  8 .. 14  → Operand B [6:0], LSB first  (bit_count 7..13)
Rising edge 15        → FSM transitions to S_CALC: result latched, Done = 1 (one cycle)
```

The **opcode** `op[2:0]` is applied as a **stable parallel input** on `ui_in[3:1]` throughout the entire operation. It does not need to be serialised.

### Shift-Register Mechanics

The shift register uses a shift-right-with-MSB-input convention:

```verilog
reg_A <= { Bit_in, reg_A[6:1] };
```

After 7 rising edges with bits `b0, b1, ... b6` (LSB first):
- At edge 1: `reg_A = {b0, xxxxxx}`
- At edge 2: `reg_A = {b1, b0, xxxxx}`
- ...
- At edge 7: `reg_A = {b6, b5, b4, b3, b2, b1, b0}` → `reg_A[0] = b0 = A[0]` ✓

### Timing Diagram (Example: `20 + 30`)

```
A = 20 = 7'b0010100  →  LSB-first sequence: 0, 0, 1, 0, 1, 0, 0
B = 30 = 7'b0011110  →  LSB-first sequence: 0, 1, 1, 1, 1, 0, 0
op = 3'b000 (ADD)    →  ui_in[3:1] = 3'b000  (parallel, stable throughout)

Clock edge:   1  2  3  4  5  6  7  |  8  9  10 11 12 13 14  | 15
Bit_in:       0  0  1  0  1  0  0  |  0  1   1  1  1  0  0  |  —
              ─────── Operand A ────   ──────── Operand B ────   CALC
uo_out:       ─────────────────────────────────────────────── = 8'h32 (50)
Done:         _______________________________________________‾‾‾____
```

---

## Supported Operations

| `op[2:0]` | Operation | RTL Expression | Bit [7] Meaning |
|---|---|---|---|
| `000` | **ADD** | `{1'b0, A} + {1'b0, B}` | Carry-out |
| `001` | **AND** | `{1'b0, A & B}` | Always `0` |
| `010` | **OR** | `{1'b0, A \| B}` | Always `0` |
| `011` | **XOR** | `{1'b0, A ^ B}` | Always `0` |
| `100` | **SUB** | `{1'b0, A} - {1'b0, B}` | Borrow (two's complement) |

**Notes on Bit[7]:**
- **ADD:** `result[7] = 1` when `A + B ≥ 128`, indicating carry-out beyond 7 bits.
- **SUB:** `result[7] = 1` when `A < B`, indicating borrow; the lower 7 bits represent the two's complement of the magnitude.
- **AND / OR / XOR:** `result[7]` is always `0` since the logical operations are bounded to 7-bit values.

---

## Pin Map

### Input Pins

| Pin | Signal | Direction | Description |
|---|---|---|---|
| `ui[0]` | `Bit_in` | Input | Serial data input — LSB first (A[6:0] then B[6:0]) |
| `ui[1]` | `op[0]` | Input | Opcode bit 0 (LSB) — stable parallel input |
| `ui[2]` | `op[1]` | Input | Opcode bit 1 |
| `ui[3]` | `op[2]` | Input | Opcode bit 2 (MSB) |
| `ui[7:4]` | — | Input | Unused (tied to `_unused` wire internally) |
| `clk` | CLK | Input | System clock — up to 50 MHz |
| `rst_n` | /RST | Input | Active-low synchronous reset — returns FSM to `S_RECV` |

### Output Pins

| Pin | Signal | Direction | Description |
|---|---|---|---|
| `uo[0]` | `Data_out[0]` | Output | Result bit 0 — LSB |
| `uo[1]` | `Data_out[1]` | Output | Result bit 1 |
| `uo[2]` | `Data_out[2]` | Output | Result bit 2 |
| `uo[3]` | `Data_out[3]` | Output | Result bit 3 |
| `uo[4]` | `Data_out[4]` | Output | Result bit 4 |
| `uo[5]` | `Data_out[5]` | Output | Result bit 5 |
| `uo[6]` | `Data_out[6]` | Output | Result bit 6 — MSB of operand result |
| `uo[7]` | `Data_out[7]` | Output | Carry-out (ADD) or Borrow (SUB) |
| `uio[0]` | `Done` | Output | One-cycle high pulse when operation is complete |
| `uio[7:1]` | — | Output | Always `0` (tied low) |

> `uio_oe = 8'b0000_0001`: only `uio[0]` is configured as a digital output. All other bidirectional pins are inputs.

---

## Repository Structure

```
myBootcampChip/
├── src/
│   ├── alu_7b.v             ← Pure combinational 7-bit ALU (leaf module)
│   ├── serial_alu_ctrl.v    ← FSM + shift register + ALU instantiation
│   ├── tt_um_alu7b.v        ← TinyTapeout top-level (pin mapping)
│   └── config.json          ← LibreLane / OpenLane synthesis configuration
├── test/
│   ├── test.py              ← cocotb testbench (20 test cases, Python)
│   ├── tb.v                 ← Verilog wrapper for cocotb
│   ├── serial_tb.v          ← Native Verilog testbench (20 cases, Icarus)
│   ├── Makefile             ← RTL and gate-level simulation build rules
│   ├── tb.gtkw              ← GTKWave signal configuration file
│   ├── requirements.txt     ← Python dependencies (pytest==8.4.2, cocotb==2.0.1)
│   └── README.md            ← Simulation and testbench instructions
├── docs/
│   └── info.md              ← Project datasheet (TinyTapeout submission)
├── .github/workflows/
│   ├── gds.yaml             ← Full GDS flow + precheck + GL test + layout viewer
│   ├── test.yaml            ← RTL simulation CI (iverilog + cocotb + pytest)
│   ├── docs.yaml            ← Documentation build CI
│   └── fpga.yaml            ← FPGA bitstream (ICE40UP5K, TinyTapeout ASIC Sim)
├── .devcontainer/
│   ├── Dockerfile           ← Ubuntu 24.04 with LibreLane, iverilog, cocotb, Verible
│   ├── devcontainer.json    ← VS Code Dev Container configuration
│   └── copy_tt_support_tools.sh  ← TinyTapeout support tools setup script
├── .vscode/
│   ├── settings.json        ← Linting (Verilator) and formatting (Verible) settings
│   └── extensions.json      ← Recommended VS Code extensions
├── info.yaml                ← TinyTapeout project metadata and pin assignment
├── .gitignore               ← Excludes synthesis runs, waveforms, build artefacts
├── LICENSE                  ← Apache 2.0
└── README.md                ← This file
```

---

## Getting Started

### 1. Clone the Repository

```bash
git clone https://github.com/<your-username>/myBootcampChip.git
cd myBootcampChip
```

### 2. Run RTL Simulation (cocotb + iverilog)

```bash
cd test
pip install -r requirements.txt   # pytest==8.4.2  cocotb==2.0.1
make -B
```

The output prints a summary of all 20 test cases. To assert no failures:

```bash
! grep failure results.xml
```

### 3. Native Verilog Simulation (Icarus Verilog, no cocotb)

```bash
cd src
iverilog -o serial_tb.vvp ../test/serial_tb.v serial_alu_ctrl.v alu_7b.v
vvp serial_tb.vvp
```

Expected output: 20 PASS / 0 FAIL with a final summary banner.

### 4. View Waveforms

```bash
# GTKWave — loads the pre-configured signal layout automatically
gtkwave test/tb.fst test/tb.gtkw

# Surfer
surfer test/tb.fst
```

### 5. Synthesis with LibreLane (inside devcontainer or IIC-OSIC-TOOLS)

```bash
cd src
librelane config.json

# Inspect the layout in KLayout
librelane --last-run --flow OpenInKlayout config.json
```

Final artefacts are placed in `runs/<RUN_FOLDER>/final/`.

### 6. Gate-Level Simulation

After completing the LibreLane synthesis flow:

```bash
cp runs/<RUN_FOLDER>/final/pnl/tt_um_alu7b.pnl.v test/gate_level_netlist.v
cd test
make -B GATES=yes
```

---

## Test Coverage

The cocotb testbench (`test/test.py`) runs **20 test cases** covering all five ALU operations with both nominal and edge-case scenarios:

| Operation | Cases | Scenarios covered |
|---|---|---|
| **ADD** | 6 | Nominal (×2), carry out (100+100), zero (0+0), 7-bit limit (127+1), both max (127+127) |
| **AND** | 4 | Partial mask, annihilation (& 0x00), identity (& 0x7F), crossed alternating pattern |
| **OR** | 3 | Partial complements, identity (\| 0x00), both operands at maximum |
| **XOR** | 4 | Difference, self-cancellation (A⊕A=0), full alternating (0x7F), identity (A⊕0) |
| **SUB** | 3 | Positive result (no borrow), A=B (zero result), two's complement underflow |

Each test case verifies simultaneously:
1. `uo_out[7:0]` exactly matches the expected 8-bit result computed as `(A OP B) & 0xFF`.
2. `uio_out[0]` (Done) pulses **high for exactly one clock cycle** within a 4-edge capture window after the 14th transmitted bit.

The native Verilog testbench (`test/serial_tb.v`) runs **20 additional cases** compatible with plain Icarus Verilog (no cocotb dependency), including 5 extended cases (Block F) for additional coverage on boundary values.

---

## Development Environment

The `.devcontainer/` directory provides a fully reproducible Ubuntu 24.04 environment with the following pre-installed tools:

| Tool | Version / Role |
|---|---|
| **LibreLane** | 2.4.2 — Open-source RTL-to-GDS synthesis flow |
| **iverilog** | Icarus Verilog — RTL simulation |
| **cocotb** | 2.0.1 — Python-driven hardware simulation framework |
| **pytest** | 8.4.2 — Test execution and XML result reporting |
| **Verilator** | RTL linting and static analysis |
| **Verible** | Verilog/SystemVerilog code formatting (`verible-verilog-format`) |
| **GTKWave** | Waveform viewer (`.fst` / `.vcd`) |
| **PDK** | sky130A — SkyWater 130 nm open-source process design kit |

---

## Design Constraints and Specifications

| Parameter | Value |
|---|---|
| Technology node | SkyWater 130 nm (sky130A PDK) |
| Supply voltage | 1.8 V (sky130A nominal) |
| Maximum clock frequency | 50 MHz |
| Clock period | 20 ns |
| Tile size | 1×1 (160 × 100 µm) |
| Serial data width | 14 bits per operation (7b A + 7b B) |
| Result width | 8 bits |
| Protocol latency | 15 clock cycles (14 receive + 1 compute) |
| Reset type | Synchronous, active-low |

---

## Context: Bootcamp IEEE OpenSilicon / IEEE CASS UTP 2026

This project was developed as part of the **Bootcamp IC Design & Fabrication** organised by the IEEE OpenSilicon initiative and the IEEE Circuits and Systems Society (CASS) at the Universidad Tecnológica de Pereira (UTP), held on April 11 and 18, 2026. The shuttle target is SKY26a (SKY130 nm PDK), with a project submission deadline of April 22, 2026, and a shuttle deadline of May 9, 2026.

The bootcamp covered the full ASIC design flow: RTL design in Verilog, HDL simulation with cocotb and iverilog, static timing analysis, synthesis with LibreLane (OpenROAD-based), physical design with KLayout, and submission to TinyTapeout for multi-project wafer (MPW) fabrication.

---

## Resources

- [TinyTapeout — Getting Started](https://tinytapeout.com)
- [TinyTapeout SKY26a Shuttle](https://app.tinytapeout.com/shuttles/ttsky26a)
- [LibreLane Documentation](https://librelane.readthedocs.io/en/latest/)
- [SkyWater PDK Documentation](https://skywater-pdk.readthedocs.io)
- [cocotb Documentation](https://docs.cocotb.org/en/stable/)
- [IEEE CASS UNIC-CASS Initiative](https://ieee-cas.org/universalization-ic-design-cass-unic-cass)
- [IIC-OSIC-TOOLS](https://github.com/iic-jku/IIC-OSIC-TOOLS)
- [TinyTapeout Digital Design Lessons](https://tinytapeout.com/digital_design/)
- [SiliWiz — Learn Semiconductor Basics](https://tinytapeout.com/siliwiz/)

---

## License

Copyright 2026 Bootcamp IEEE OpenSilicon / IEEE CASS UTP.  
Distributed under the [Apache 2.0](LICENSE) license.