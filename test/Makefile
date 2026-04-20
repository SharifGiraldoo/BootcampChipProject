# Makefile — Simulación RTL y Gate-Level para tt_um_alu7b
# Documentación cocotb: https://docs.cocotb.org/en/stable/quickstart.html

# ── Valores por defecto ───────────────────────────────────────────────────────
SIM          ?= icarus
FST          ?= -fst
TOPLEVEL_LANG ?= verilog
SRC_DIR       = $(PWD)/../src

# ── Fuentes del proyecto — DEBE coincidir con info.yaml:source_files ──────────
PROJECT_SOURCES = tt_um_alu7b.v

ifneq ($(GATES),yes)

# ── Simulación RTL ────────────────────────────────────────────────────────────
SIM_BUILD        = sim_build/rtl
VERILOG_SOURCES += $(addprefix $(SRC_DIR)/,$(PROJECT_SOURCES))

else

# ── Simulación Gate-Level ─────────────────────────────────────────────────────
SIM_BUILD        = sim_build/gl
COMPILE_ARGS    += -DGL_TEST
COMPILE_ARGS    += -DFUNCTIONAL
COMPILE_ARGS    += -DUSE_POWER_PINS
COMPILE_ARGS    += -DSIM
COMPILE_ARGS    += -DUNIT_DELAY=\#1
VERILOG_SOURCES += $(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/verilog/primitives.v
VERILOG_SOURCES += $(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/verilog/sky130_fd_sc_hd.v
VERILOG_SOURCES += $(PWD)/gate_level_netlist.v

endif

# ── Permitir includes desde src/ (para `include compartido) ──────────────────
COMPILE_ARGS += -I$(SRC_DIR)

# ── Testbench ─────────────────────────────────────────────────────────────────
VERILOG_SOURCES += $(PWD)/tb.v
TOPLEVEL         = tb

# ── Módulos de prueba cocotb (sin extensión .py, separados por coma) ─────────
COCOTB_TEST_MODULES = test

# ── Incluir reglas de cocotb ──────────────────────────────────────────────────
include $(shell cocotb-config --makefiles)/Makefile.sim
