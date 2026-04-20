# Testbench — tt_um_alu7b

cocotb testbench for the 7-bit serial-input ALU.

## Setup

1. Verify that `PROJECT_SOURCES` in `Makefile` lists `project.v alu_7b.v tt_um_alu7b.v`.
2. Verify that `TOPLEVEL` in `Makefile` is `tb` and that `tb.v` instantiates `tt_um_alu7b` as `user_project`.

## Running the tests

### RTL simulation

```sh
pip install -r requirements.txt
make -B
```

### Gate-level simulation

First run the full LibreLane flow to obtain the synthesised netlist, then copy it:

```sh
cp ../runs/<RUN_FOLDER>/final/pnl/tt_um_alu7b.pnl.v gate_level_netlist.v
make -B GATES=yes
```

### Save waveforms in VCD format instead of FST

Edit `tb.v` to use `$dumpfile("tb.vcd")` and run:

```sh
make -B FST=
```

## Viewing waveforms

With GTKWave (loads the signal configuration automatically):

```sh
gtkwave tb.fst tb.gtkw
```

With Surfer:

```sh
surfer tb.fst
```

## Test coverage

`test.py` covers all 5 ALU operations with 15 test cases:

| Operation | Cases | Scenarios covered                          |
|-----------|-------|--------------------------------------------|
| ADD       | 5     | Normal, carry (200), zero, limit (127+1)   |
| AND       | 3     | Mask, identity, zero                       |
| OR        | 2     | Complement, identity                       |
| XOR       | 2     | Difference, self-cancellation (A^A=0)      |
| SUB       | 3     | Normal, A=B (zero), underflow (two's comp) |