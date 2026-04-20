# Banco de pruebas — tt_um_alu7b

Banco de pruebas cocotb para la ALU de 7 bits con entrada serial.

## Configuración

1. Verificar que `PROJECT_SOURCES` en `Makefile` apunte a `tt_um_alu7b.v`.
2. Verificar que el `TOPLEVEL` en `Makefile` sea `tb` y que `tb.v` instancie `tt_um_alu7b`.

## Ejecución

### Simulación RTL

```sh
make -B
```

### Simulación Gate-Level

Primero ejecutar el flujo completo de LibreLane/OpenLane para obtener el netlist
sintetizado y copiarlo como `gate_level_netlist.v`:

```sh
cp ../runs/<RUN_FOLDER>/final/pnl/tt_um_alu7b.pnl.v gate_level_netlist.v
make -B GATES=yes
```

### Guardar formas de onda en formato VCD (en lugar de FST)

Editar `tb.v` para usar `$dumpfile("tb.vcd")` y ejecutar:

```sh
make -B FST=
```

## Visualización de formas de onda

Con GTKWave (carga la configuración de señales automáticamente):

```sh
gtkwave tb.fst tb.gtkw
```

Con Surfer:

```sh
surfer tb.fst
```

## Cobertura de pruebas

El archivo `test.py` cubre las 5 operaciones de la ALU con 15 casos:

| Operación | Casos | Escenarios cubiertos                      |
|-----------|-------|-------------------------------------------|
| ADD       | 5     | Normal, carry, cero, límite (127+1=128)   |
| AND       | 3     | Máscara, identidad, cero                  |
| OR        | 2     | Complemento, identidad                    |
| XOR       | 2     | Diferencia, autocancelación (A^A=0)       |
| SUB       | 3     | Normal, A=B, underflow (complemento a 2)  |
