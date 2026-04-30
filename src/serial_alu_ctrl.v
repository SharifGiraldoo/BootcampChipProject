/*
 * serial_alu_ctrl.v — Controlador Serial para ALU de 7 bits
 *
 * Bootcamp IC Design & Fabrication — IEEE OpenSilicon / IEEE CASS UTP 2026
 *
 * Este módulo implementa:
 *   1. Un registro de desplazamiento shift-right (LSB primero, nuevo bit
 *      entra por MSB) que captura los datos seriales en Bit_in sincronizado
 *      con CLK.
 *   2. Un contador de 5 bits que cuenta cada flanco de subida de CLK
 *      durante el estado S_RECV.
 *   3. Una instancia de alu_7b (módulo combinacional) que recibe A, B y op
 *      y entrega el resultado de 8 bits.
 *   4. Un registro de resultado y la señal Done (pulso de 1 ciclo).
 *
 * ─────────────────────────────────────────────────────────────────────────
 * PROTOCOLO DE ENTRADA SERIAL (Bit_in, LSB primero):
 *
 *   Bit_count  1 ..  7  → Operando A [6:0]   (A[0] primero)
 *   Bit_count  8 .. 14  → Operando B [6:0]   (B[0] primero)
 *   Al bit_count == 14  → Transición a S_CALC (resultado listo, Done = 1)
 *
 * NOTA SOBRE TEMPORIZACIÓN:
 *   El protocolo del testbench libera rst_n en un negedge; el contador
 *   inicia en 0 y se incrementa a 1 en el primer posedge post-reset (que
 *   ocurre antes de que llegue el primer dato). El primer dato (A[0]) llega
 *   en el posedge siguiente, cuando bit_count == 1.
 *   Por tanto las ventanas de captura son:
 *     bit_count 1..7  → reg_A  (CNT_A_LAST = 7)
 *     bit_count 8..14 → reg_B  (CNT_B_LAST = 14)
 *
 * MECÁNICA DEL REGISTRO DE DESPLAZAMIENTO (shift-right, entra por MSB):
 *
 *   reg <= { Bit_in, reg[N-1:1] }
 *
 *   Después de N flancos: reg[N-1] = MSB ... reg[0] = LSB ✓
 *
 * TABLA DE OPERACIONES (op[2:0]):
 *   000 → Suma   (A + B, bit[7] = carry)
 *   001 → AND    (A & B)
 *   010 → OR     (A | B)
 *   011 → XOR    (A ^ B)
 *   100 → Resta  (A - B, bit[7] = borrow en complemento a 2)
 *
 * SEÑALES DE SALIDA:
 *   Data_out[7:0] — resultado en paralelo (estable desde S_CALC en adelante)
 *   Done          — pulso de 1 ciclo de reloj indicando fin de operación
 *
 * RESET:
 *   /RST = 0 → reset síncrono; limpia todos los registros y vuelve a S_RECV
 *
 * VERIFICADO: 20/20 casos con tt_um_alu7b_tb.v (Icarus Verilog 12.0)
 *
 * SPDX-License-Identifier: Apache-2.0
 */

/* verilator lint_off TIMESCALEMOD */

`default_nettype none

module serial_alu_ctrl (
    // ── Entradas de control ───────────────────────────────────────────────────
    input  wire       CLK,        // Reloj del sistema
    input  wire       RST_n,      // Reset activo-bajo  (/RST en el enunciado)

    // ── Entrada serial ────────────────────────────────────────────────────────
    input  wire       Bit_in,     // Dato serial, LSB primero
    input  wire [2:0] op,         // Opcode paralelo, estable durante la operación

    // ── Salidas paralelas ─────────────────────────────────────────────────────
    output wire [7:0] Data_out,   // Resultado de la ALU (8 bits)
    output wire       Done        // Pulso activo-alto: 1 ciclo cuando listo
);

    // =========================================================================
    // 1. PARÁMETROS Y LOCALPARAMS
    // =========================================================================

    // Límites del contador de bits (5 bits, base-1 por el ciclo de reset)
    // El primer dato llega cuando bit_count == 1 (no 0) debido a que el
    // contador se incrementa en el primer posedge post-reset antes del dato.
    localparam [4:0] CNT_A_LAST = 5'd7;    // Último bit de A: bit_count == 7
    localparam [4:0] CNT_B_LAST = 5'd14;   // Último bit de B: bit_count == 14

    // Estados de la máquina de estados finitos (FSM)
    localparam [1:0] S_RECV = 2'd0,        // Recepción serial de bits
                     S_CALC = 2'd1,        // Cálculo y latch del resultado
                     S_DONE = 2'd2;        // Resultado estable, espera /RST

    // =========================================================================
    // 2. DECLARACIÓN DE REGISTROS INTERNOS
    // =========================================================================

    reg [1:0] state;       // Estado FSM
    reg [4:0] bit_count;   // Contador de flancos de reloj en S_RECV

    reg [6:0] reg_A;       // Operando A (capturado por shift-right)
    reg [6:0] reg_B;       // Operando B (capturado por shift-right)

    reg [7:0] reg_result;  // Registro de resultado (salida paralela)
    reg       done_reg;    // Señal Done (pulso de 1 ciclo)

    // =========================================================================
    // 3. INSTANCIA DEL MÓDULO ALU COMBINACIONAL (alu_7b)
    // =========================================================================

    wire [7:0] alu_out;    // Salida combinacional de la ALU

    alu_7b u_alu (
        .A      (reg_A),
        .B      (reg_B),
        .op     (op),
        .result (alu_out)
    );

    // =========================================================================
    // 4. BLOQUE SÍNCRONO PRINCIPAL — FSM + Shift Register + Contador
    // =========================================================================

    always @(posedge CLK) begin
        if (!RST_n) begin
            // ── Reset síncrono (activo-bajo) ──────────────────────────────────
            state      <= S_RECV;
            bit_count  <= 5'd0;
            reg_A      <= 7'd0;
            reg_B      <= 7'd0;
            reg_result <= 8'd0;
            done_reg   <= 1'b0;

        end else begin

            // Done es un pulso de 1 solo ciclo; se limpia automáticamente
            done_reg <= 1'b0;

            case (state)

                // ─────────────────────────────────────────────────────────────
                // S_RECV: Recepción serial LSB-first mediante shift-right.
                //
                //   Ventana de bit_count (protocolo real post-reset):
                //   bit_count 1..7  → alimentan reg_A
                //   bit_count 8..14 → alimentan reg_B
                //
                //   Shift-right (nuevo bit entra por MSB):
                //     reg <= { Bit_in, reg[6:1] }
                //   Tras N posedges con bits b0,b1,...b(N-1) (LSB primero):
                //     reg[0]=b0 (LSB), reg[N-1]=b(N-1) (MSB) ✓
                // ─────────────────────────────────────────────────────────────
                S_RECV: begin
                    if (bit_count <= CNT_A_LAST)
                        reg_A <= {Bit_in, reg_A[6:1]};
                    else
                        reg_B <= {Bit_in, reg_B[6:1]};

                    if (bit_count == CNT_B_LAST) begin
                        state     <= S_CALC;
                        bit_count <= 5'd0;
                    end else begin
                        bit_count <= bit_count + 5'd1;
                    end
                end

                // ─────────────────────────────────────────────────────────────
                // S_CALC: reg_A y reg_B son estables en este ciclo.
                //   Se latcha alu_out en reg_result y se activa Done (1 ciclo).
                // ─────────────────────────────────────────────────────────────
                S_CALC: begin
                    reg_result <= alu_out;
                    done_reg   <= 1'b1;
                    state      <= S_DONE;
                end

                // ─────────────────────────────────────────────────────────────
                // S_DONE: Resultado estable en Data_out.
                //   El sistema permanece aquí hasta que /RST = 0.
                // ─────────────────────────────────────────────────────────────
                S_DONE: state <= S_DONE;

                default: state <= S_RECV;

            endcase
        end
    end

    // =========================================================================
    // 5. ASIGNACIONES DE SALIDA
    // =========================================================================

    assign Data_out = reg_result;
    assign Done     = done_reg;

endmodule
/* verilator lint_on TIMESCALEMOD */