# ALU de 7 bits — Entrada Serial / Salida Paralela

**Bootcamp Diseño y Fabricación de Chips — IEEE OpenSilicon / IEEE CASS UTP 2026**

---

## Descripción general

Este proyecto implementa una **Unidad Aritmético-Lógica (ALU) de 7 bits** para
fabricación en TinyTapeout (shuttle SKY26a, PDK sky130A).

El sistema recibe dos operandos de 7 bits y un código de operación de 3 bits de
forma **serial** a través de un único pin de entrada (`ui_in[0]`), usando
formato LSB-first. El resultado de 8 bits se presenta de forma **paralela** en
`uo_out[7:0]` al finalizar el cómputo.

---

## Cómo funciona

### Protocolo de entrada serial

Los datos se envían bit a bit por `ui_in[0]` sincronizados con el flanco de
subida del reloj `clk`, en el siguiente orden:

| Ciclo(s) de reloj | Dato recibido        |
|-------------------|----------------------|
| 1 .. 7            | Operando A [6:0], LSB primero |
| 8 .. 14           | Operando B [6:0], LSB primero |
| 15 .. 17          | Opcode [2:0], LSB primero     |
| 18 (automático)   | FSM calcula y presenta resultado |

### Operaciones soportadas

| op[2:0] | Operación | Expresión           |
|---------|-----------|---------------------|
| `000`   | Suma      | `result = A + B`    |
| `001`   | AND       | `result = A & B`    |
| `010`   | OR        | `result = A \| B`   |
| `011`   | XOR       | `result = A ^ B`    |
| `100`   | Resta     | `result = A - B`    |

> **Bit 7 del resultado:** En la suma indica *carry*; en la resta indica
> *borrow* (complemento a dos).

### Máquina de estados (FSM)

El diseño utiliza una FSM de 3 estados:

```
S_RECV ──(17 bits recibidos)──► S_CALC ──(1 ciclo)──► S_DONE
   ▲                                                       │
   └────────────────────(rst_n = 0)───────────────────────┘
```

- **S_RECV:** Captura serial con shift-register LSB-first (shift-right).
- **S_CALC:** Latch del resultado de la ALU combinacional + pulso `Done`.
- **S_DONE:** Resultado estable; espera `rst_n = 0` para nueva operación.

---

## Mapa de pines

### Entradas

| Pin      | Señal   | Descripción                                      |
|----------|---------|--------------------------------------------------|
| `ui[0]`  | Bit_in  | Bit de entrada serial (LSB primero: A, B, opcode)|
| `ui[7:1]`| —       | No utilizados                                    |
| `clk`    | CLK     | Reloj del sistema (hasta 50 MHz)                 |
| `rst_n`  | /RST    | Reset activo bajo — reinicia a S_RECV            |

### Salidas

| Pin      | Señal        | Descripción                              |
|----------|--------------|------------------------------------------|
| `uo[6:0]`| Data_out[6:0]| 7 bits de resultado (LSB = `uo[0]`)      |
| `uo[7]`  | Data_out[7]  | Carry (suma) o Borrow (resta)            |
| `uio[0]` | Done         | Pulso alto de 1 ciclo al finalizar       |

---

## Cómo probar el diseño

### Procedimiento de operación

1. Aplicar reset: `rst_n = 0` durante al menos 2 ciclos.
2. Liberar reset: `rst_n = 1`.
3. Enviar los 7 bits del **Operando A** por `ui[0]`, LSB primero, uno por flanco de reloj.
4. Enviar los 7 bits del **Operando B** por `ui[0]`, LSB primero.
5. Enviar los 3 bits del **opcode** por `ui[0]`, LSB primero.
6. Esperar 1 ciclo adicional (S_CALC automático).
7. Leer el resultado en `uo_out[7:0]`.
8. Verificar que `uio_out[0]` (Done) esté en `1` durante exactamente 1 ciclo.

### Ejemplo: 20 + 30 = 50

```
Operando A = 20 = 7'b0010100  → enviar LSB primero: 0,0,1,0,1,0,0
Operando B = 30 = 7'b0011110  → enviar LSB primero: 0,1,1,1,1,0,0
Opcode     =  0 = 3'b000      → enviar LSB primero: 0,0,0

Resultado esperado: uo_out = 8'b00110010 = 50
Done = 1 en el ciclo 18
```

### Ejemplo: 10 - 30 (underflow en complemento a 2)

```
Operando A = 10, Operando B = 30, op = 3'b100
Resultado = (10 - 30) & 0xFF = (-20) & 0xFF = 0xEC = 236
Bit[7] = 1 indica borrow (resultado negativo en complemento a 2)
```

---

## Hardware externo

No se requiere hardware externo para el funcionamiento básico.

Hardware opcional para demostración:

- LEDs conectados a `uo_out[7:0]` para visualización del resultado
- Pulsadores para entrada serial manual y clock
- Analizador lógico para inspección de formas de onda
- Placa FPGA o tarjeta de desarrollo TinyTapeout DevKit
