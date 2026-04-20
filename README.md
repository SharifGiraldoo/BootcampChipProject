![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg) ![](../../workflows/fpga/badge.svg)

# ALU de 7 bits — Entrada Serial / Salida Paralela

**Bootcamp Diseño y Fabricación de Chips — IEEE OpenSilicon / IEEE CASS UTP 2026**
Shuttle: SKY26a · PDK: sky130A (130 nm) · Tile: 1×1

---

## Descripción del proyecto

Este proyecto implementa una **Unidad Aritmético-Lógica (ALU) de 7 bits** diseñada
para fabricación real en silicio a través de la plataforma [TinyTapeout](https://tinytapeout.com).

El sistema recibe dos operandos de 7 bits y un código de operación de 3 bits de
forma **serial** (LSB-first) a través de un único pin de entrada, y entrega el
resultado de 8 bits de forma **paralela** al finalizar el cómputo.

### Operaciones soportadas

| op[2:0] | Operación | Descripción                          |
|---------|-----------|--------------------------------------|
| `000`   | Suma      | `result = A + B` (bit[7] = carry)    |
| `001`   | AND       | `result = A & B`                     |
| `010`   | OR        | `result = A \| B`                    |
| `011`   | XOR       | `result = A ^ B`                     |
| `100`   | Resta     | `result = A - B` (bit[7] = borrow)   |

### Protocolo de entrada serial

```
Posedge  1.. 7  → Operando A [6:0], LSB primero
Posedge  8..14  → Operando B [6:0], LSB primero
Posedge 15..17  → Opcode [2:0],    LSB primero
Posedge 18      → Resultado en uo_out, Done=1 en uio_out[0]
```

---

## Estructura del repositorio

```
myBootcampChip/
├── src/
│   ├── project.v        ← Archivo de integración (punto de entrada del flujo)
│   ├── alu_7b.v         ← ALU combinacional de 7 bits (módulo funcional)
│   ├── tt_um_alu7b.v    ← Top-level TinyTapeout con FSM serial→paralela
│   └── config.json      ← Configuración LibreLane/OpenLane
├── test/
│   ├── test.py          ← Banco de pruebas cocotb (15 casos)
│   ├── tb.v             ← Testbench Verilog
│   ├── Makefile         ← Build RTL y Gate-Level
│   ├── tb.gtkw          ← Configuración de señales GTKWave
│   ├── requirements.txt ← Dependencias Python
│   └── README.md        ← Instrucciones de simulación
├── docs/
│   └── info.md          ← Datasheet del proyecto
├── .github/workflows/
│   ├── gds.yaml         ← Flujo completo GDS + precheck + GL test + viewer
│   ├── test.yaml        ← CI de pruebas RTL
│   ├── docs.yaml        ← Generación de documentación
│   └── fpga.yaml        ← Bitstream FPGA (ICE40UP5K)
├── .devcontainer/
│   ├── Dockerfile       ← Entorno con LibreLane, iverilog, cocotb
│   ├── devcontainer.json
│   └── copy_tt_support_tools.sh
├── .vscode/
│   ├── settings.json    ← Linting y formateo Verilog
│   └── extensions.json  ← Extensiones recomendadas
├── info.yaml            ← Metadatos del proyecto para TinyTapeout
├── .gitignore
├── LICENSE
└── README.md            ← Este archivo
```

---

## Configurar y ejecutar el proyecto

### 1. Clonar el repositorio

```bash
git clone https://github.com/<tu-usuario>/myBootcampChip.git
cd myBootcampChip
```

### 2. Ejecutar simulación RTL

```bash
cd test
pip install -r requirements.txt
make -B
```

### 3. Ver formas de onda

```bash
gtkwave tb.fst tb.gtkw
```

### 4. Síntesis con LibreLane (dentro del devcontainer o con IIC-OSIC-TOOLS)

```bash
cd src
librelane config.json
# Visualizar layout:
librelane --last-run --flow OpenInKlayout config.json
```

---

## Recursos TinyTapeout

- [FAQ](https://tinytapeout.com/faq/)
- [Lecciones de diseño digital](https://tinytapeout.com/digital_design/)
- [Documentación de especificaciones](https://tinytapeout.com/specs)
- [Shuttle SKY26a](https://app.tinytapeout.com/shuttles/ttsky26a)
- [Comunidad Discord](https://tinytapeout.com/discord)
- [Construir localmente](https://www.tinytapeout.com/guides/local-hardening/)
