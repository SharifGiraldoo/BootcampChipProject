![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg) ![](../../workflows/fpga/badge.svg)

# 7-bit ALU — Serial Input / Parallel Output

**Bootcamp IC Design & Fabrication — IEEE OpenSilicon / IEEE CASS UTP 2026**
Shuttle: SKY26a · PDK: sky130A (130 nm) · Tile: 1×1

---

## Project description

This project implements a **7-bit Arithmetic Logic Unit (ALU)** designed for
real silicon fabrication through the [TinyTapeout](https://tinytapeout.com)
platform.

The system receives two 7-bit operands and a 3-bit operation code **serially**
(LSB first) through a single input pin, and delivers the 8-bit result **in
parallel** when the computation is complete.

### Supported operations

| op[2:0] | Operation | Description                          |
|---------|-----------|--------------------------------------|
| `000`   | ADD       | `result = A + B` (bit[7] = carry)    |
| `001`   | AND       | `result = A & B`                     |
| `010`   | OR        | `result = A \| B`                    |
| `011`   | XOR       | `result = A ^ B`                     |
| `100`   | SUB       | `result = A - B` (bit[7] = borrow)   |

### Serial input protocol

```
Posedge  1.. 7  → Operand A [6:0], LSB first
Posedge  8..14  → Operand B [6:0], LSB first
Posedge 15..17  → Opcode [2:0],   LSB first
Posedge 18      → Result on uo_out, Done=1 on uio_out[0]
```

---

## Repository structure

```
myBootcampChip/
├── src/
│   ├── project.v        ← Synthesis entry point (empty — no module logic)
│   ├── alu_7b.v         ← 7-bit combinational ALU
│   ├── tt_um_alu7b.v    ← TinyTapeout top-level with serial→parallel FSM
│   └── config.json      ← LibreLane / OpenLane configuration
├── test/
│   ├── test.py          ← cocotb testbench (15 test cases)
│   ├── tb.v             ← Verilog testbench wrapper
│   ├── Makefile         ← RTL and gate-level build
│   ├── tb.gtkw          ← GTKWave signal configuration
│   ├── requirements.txt ← Python dependencies
│   └── README.md        ← Simulation instructions
├── docs/
│   └── info.md          ← Project datasheet
├── .github/workflows/
│   ├── gds.yaml         ← Full GDS flow + precheck + GL test + viewer
│   ├── test.yaml        ← RTL test CI
│   ├── docs.yaml        ← Documentation build
│   └── fpga.yaml        ← FPGA bitstream (ICE40UP5K)
├── .devcontainer/
│   ├── Dockerfile       ← Environment with LibreLane, iverilog, cocotb
│   ├── devcontainer.json
│   └── copy_tt_support_tools.sh
├── .vscode/
│   ├── settings.json    ← Verilog linting and formatting
│   └── extensions.json  ← Recommended extensions
├── info.yaml            ← TinyTapeout project metadata
├── .gitignore
├── LICENSE
└── README.md            ← This file
```

---

## Getting started

### 1. Clone the repository

```bash
git clone https://github.com/<your-username>/myBootcampChip.git
cd myBootcampChip
```

### 2. Run RTL simulation

```bash
cd test
pip install -r requirements.txt
make -B
```

### 3. View waveforms

```bash
gtkwave tb.fst tb.gtkw
```

### 4. Synthesis with LibreLane (inside the devcontainer or IIC-OSIC-TOOLS)

```bash
cd src
librelane config.json
# View layout:
librelane --last-run --flow OpenInKlayout config.json
```

---

## TinyTapeout resources

- [FAQ](https://tinytapeout.com/faq/)
- [Digital design lessons](https://tinytapeout.com/digital_design/)
- [Specifications](https://tinytapeout.com/specs)
- [SKY26a shuttle](https://app.tinytapeout.com/shuttles/ttsky26a)
- [Discord community](https://tinytapeout.com/discord)
- [Build locally](https://www.tinytapeout.com/guides/local-hardening/)