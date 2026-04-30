// =============================================================================
// tt_um_alu7b_tb.v — Testbench nativo Verilog para tt_um_alu7b
//
// Bootcamp IC Design & Fabrication — IEEE OpenSilicon / IEEE CASS UTP 2026
// Autor del diseño : Sharif Obando
// Repositorio      : SharifGiraldoo/myBootcampChip
//
// ─────────────────────────────────────────────────────────────────────────────
// PROPÓSITO
// ─────────────────────────────────────────────────────────────────────────────
// Verificar el funcionamiento completo del módulo tt_um_alu7b mediante
// simulación Verilog pura (Icarus Verilog), sin dependencias de cocotb,
// Python ni frameworks externos.
//
// El testbench instancia directamente el top-level TinyTapeout (tt_um_alu7b)
// y ejerce el protocolo serial completo definido en el reto del Bootcamp:
//
//   PROTOCOLO SERIAL (Bit_in = ui_in[0], LSB primero):
//     Flancos  1 ..  7  → Operando A [6:0]   (A[0] primero)
//     Flancos  8 .. 14  → Operando B [6:0]   (B[0] primero)
//     Flanco  15        → FSM S_CALC: resultado disponible, Done = 1 (1 ciclo)
//
//   OPCODE PARALELO:
//     ui_in[3:1] = op[2:0] — estable durante toda la operación
//
//   TABLA DE OPERACIONES:
//     3'b000 → Suma    result = A + B   (bit[7] = carry)
//     3'b001 → AND     result = A & B
//     3'b010 → OR      result = A | B
//     3'b011 → XOR     result = A ^ B
//     3'b100 → Resta   result = A - B   (bit[7] = borrow, complemento a 2)
//
// ─────────────────────────────────────────────────────────────────────────────
// COBERTURA DE PRUEBAS — 20 CASOS
// ─────────────────────────────────────────────────────────────────────────────
//   SUMA (6 casos) : normal ×2, carry, cero, límite 7 bits, ambos máximos
//   AND  (4 casos) : máscara parcial, aniquilación, identidad, patrón cruzado
//   OR   (3 casos) : complementarios, identidad, ambos máximos
//   XOR  (4 casos) : diferencia, auto-cancelación, alternado, identidad (A^0)
//   SUB  (3 casos) : positivo, A=B (cero), underflow (complemento a 2)
//
// ─────────────────────────────────────────────────────────────────────────────
// COMPILACIÓN Y SIMULACIÓN (Icarus Verilog):
//   iverilog -o tt_um_alu7b_tb.vvp tt_um_alu7b_tb.v \
//            ../src/tt_um_alu7b.v ../src/serial_alu_ctrl.v ../src/alu_7b.v
//   vvp tt_um_alu7b_tb.vvp
//   gtkwave tt_um_alu7b_tb.vcd
//
// SPDX-License-Identifier: Apache-2.0
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module tt_um_alu7b_tb;

    // =========================================================================
    // 1. PARÁMETROS DEL TESTBENCH
    // =========================================================================

    // Período de reloj: 20 ns → 50 MHz (límite máximo TinyTapeout IO)
    localparam CLK_PERIOD = 20;
    localparam CLK_HALF   = CLK_PERIOD / 2;

    // Opcodes — deben coincidir con alu_7b.v y serial_alu_ctrl.v
    localparam [2:0] OP_ADD = 3'b000;
    localparam [2:0] OP_AND = 3'b001;
    localparam [2:0] OP_OR  = 3'b010;
    localparam [2:0] OP_XOR = 3'b011;
    localparam [2:0] OP_SUB = 3'b100;

    // Número de bits por operando
    localparam N_BITS = 7;

    // =========================================================================
    // 2. SEÑALES — INTERFAZ TinyTapeout (tt_um_alu7b)
    // =========================================================================

    // Entradas al DUT (Device Under Test)
    reg        clk;         // Reloj del sistema
    reg        rst_n;       // Reset activo-bajo (/RST del enunciado)
    reg        ena;         // Enable TinyTapeout (siempre 1 en operación normal)
    reg  [7:0] ui_in;       // ui_in[0]=Bit_in serial, ui_in[3:1]=op[2:0]
    reg  [7:0] uio_in;      // Bidirectional input (no utilizado en este diseño)

    // Salidas del DUT
    wire [7:0] uo_out;      // Data_out[7:0] — resultado paralelo de 8 bits
    wire [7:0] uio_out;     // uio_out[0] = Done (pulso activo-alto, 1 ciclo)
    wire [7:0] uio_oe;      // Dirección pines bidireccionales (uio_oe[0]=1 → salida)

    // Contadores globales de resultado
    integer passed;
    integer failed;
    integer test_num;

    // Variables de captura por caso de prueba
    reg [7:0] result_out;
    reg       done_seen;

    // =========================================================================
    // 3. INSTANCIA DEL DUT — tt_um_alu7b (top-level TinyTapeout)
    //
    //    Se instancia directamente el módulo top-level que se sintetizará
    //    para el chip. Esto garantiza que el testbench verifique exactamente
    //    el mismo RTL que se enviará al shuttle SKY26a.
    // =========================================================================

    tt_um_alu7b DUT (
        .ui_in   (ui_in),
        .uo_out  (uo_out),
        .uio_in  (uio_in),
        .uio_out (uio_out),
        .uio_oe  (uio_oe),
        .ena     (ena),
        .clk     (clk),
        .rst_n   (rst_n)
    );

    // =========================================================================
    // 4. GENERACIÓN DE RELOJ
    //    El reloj oscila libremente. El DUT se controla mediante rst_n y la
    //    secuencia de bits en ui_in[0] (Bit_in).
    // =========================================================================

    initial clk = 1'b0;
    always #(CLK_HALF) clk = ~clk;

    // =========================================================================
    // 5. DUMP DE FORMAS DE ONDA
    //    Genera tt_um_alu7b_tb.vcd para inspección en GTKWave o Surfer.
    //    Incluye todas las señales internas del DUT para depuración completa.
    // =========================================================================

    initial begin
        $dumpfile("tt_um_alu7b_tb.vcd");
        $dumpvars(0, tt_um_alu7b_tb);
    end

    // =========================================================================
    // 6. TAREA: reset_dut
    //
    //    Aplica reset activo-bajo al DUT a través de la interfaz TinyTapeout.
    //    El reset es SÍNCRONO en el RTL (se procesa en el posedge CLK).
    //    Se mantiene durante 5 ciclos completos para garantizar inicialización
    //    robusta en todos los registros internos.
    //
    //    Protocolo de temporización:
    //      - rst_n = 0 se aplica en un flanco de bajada
    //      - Se esperan 5 flancos de subida completos (reset síncrono activo)
    //      - rst_n = 1 se libera en el siguiente flanco de bajada
    //      - La tarea termina en el flanco de bajada post-reset, lista para
    //        presentar el primer bit de A en el próximo posedge CLK
    //
    //    Postcondición del DUT:
    //      state=S_RECV, bit_count=0, reg_A=0, reg_B=0, reg_result=0, Done=0
    // =========================================================================

    task reset_dut;
        begin
            @(negedge clk);          // Alinear al semiciclo bajo
            rst_n   = 1'b0;
            ui_in   = 8'h00;         // Bit_in=0, op=000
            uio_in  = 8'h00;
            // Mantener reset durante 5 flancos de subida
            @(posedge clk);
            @(posedge clk);
            @(posedge clk);
            @(posedge clk);
            @(posedge clk);
            @(negedge clk);          // Liberar reset en flanco de bajada
            rst_n = 1'b1;
            // DUT está en S_RECV, listo para recibir bits
        end
    endtask

    // =========================================================================
    // 7. TAREA: send_serial
    //
    //    Envía un operando de N_BITS bits de forma serial, LSB primero,
    //    manteniendo el opcode en ui_in[3:1] durante la transmisión.
    //
    //    Mecánica del shift-right con inserción por MSB (RTL reference):
    //      reg <= { Bit_in, reg[N-1:1] }
    //    Tras N flancos: reg[N-1]=MSB ... reg[0]=LSB ✓
    //
    //    Cada bit se presenta en el semiciclo bajo ANTES del flanco de subida
    //    que lo captura, garantizando el tiempo de setup necesario.
    //
    //    Parámetros:
    //      data  [6:0] — valor a serializar (7 bits, LSB primero)
    //      op_v  [2:0] — opcode a mantener estable en ui_in[3:1]
    //
    //    Secuencia por bit i (i = 0 .. N_BITS-1):
    //      1. [negedge] Presentar {op_v, data[i]} → ui_in[3:0]
    //      2. [posedge] DUT captura Bit_in y actualiza shift register
    // =========================================================================

    task send_serial;
        input [6:0] data;
        input [2:0] op_v;
        integer i;
        begin
            for (i = 0; i < N_BITS; i = i + 1) begin
                @(negedge clk);
                // ui_in[0]   = Bit_in (bit i del operando)
                // ui_in[3:1] = op[2:0] (opcode paralelo, estable)
                // ui_in[7:4] = 0 (no utilizados)
                ui_in = {4'b0000, op_v, data[i]};
                @(posedge clk);      // Captura en flanco de subida
            end
        end
    endtask

    // =========================================================================
    // 8. TAREA: run_operation
    //
    //    Ejecuta una operación ALU completa sobre la interfaz TinyTapeout:
    //      1. reset_dut            — inicializa FSM a S_RECV
    //      2. Establece op[2:0]    — opcode paralelo en ui_in[3:1]
    //      3. send_serial(A, op)   — 7 flancos de subida para operando A
    //      4. send_serial(B, op)   — 7 flancos de subida para operando B
    //                                Al flanco 14 (bit_count==13) → S_CALC
    //      5. Espera Done          — máximo 4 ciclos de margen (Done aparece
    //                                normalmente en el flanco 15)
    //      6. Captura resultado    — uo_out cuando Done=1
    //
    //    Escritura de resultados en registros compartidos del TB:
    //      result_out [7:0] — valor de uo_out cuando Done fue observado
    //      done_seen        — 1 si Done pulsó dentro del tiempo de espera
    //
    //    Parámetros:
    //      A_val  [6:0] — operando A (7 bits)
    //      B_val  [6:0] — operando B (7 bits)
    //      op_val [2:0] — opcode de la operación
    // =========================================================================

    task run_operation;
        input [6:0] A_val;
        input [6:0] B_val;
        input [2:0] op_val;
        integer wait_cycles;
        begin
            // ── Paso 1: Reset del DUT ─────────────────────────────────────────
            reset_dut;

            // ── Paso 2: Opcode paralelo estable (se mantendrá durante send_serial)
            // (el opcode se incluye en cada llamada a send_serial vía ui_in[3:1])

            // ── Paso 3: Transmisión serial de A (7 bits, LSB primero) ─────────
            send_serial(A_val, op_val);

            // ── Paso 4: Transmisión serial de B (7 bits, LSB primero) ─────────
            //    Al completar el bit 13 (bit_count == CNT_B_END = 13),
            //    la FSM transiciona automáticamente de S_RECV a S_CALC.
            send_serial(B_val, op_val);

            // ── Paso 5: Mantener opcode estable durante S_CALC ────────────────
            //    Asegurar que ui_in[3:1] = op_val mientras la ALU calcula.
            @(negedge clk);
            ui_in = {4'b0000, op_val, 1'b0};  // Bit_in=0, op estable

            // ── Paso 6: Esperar el pulso de Done (máximo 4 ciclos) ────────────
            done_seen  = 1'b0;
            result_out = 8'hXX;

            for (wait_cycles = 0; wait_cycles < 4; wait_cycles = wait_cycles + 1) begin
                @(posedge clk);
                if (uio_out[0] === 1'b1) begin
                    done_seen  = 1'b1;
                    result_out = uo_out;
                    wait_cycles = 4;     // Salir del loop
                end else begin
                    @(negedge clk);
                end
            end

            // Dejar ui_in en estado neutro
            @(negedge clk);
            ui_in = 8'h00;
        end
    endtask

    // =========================================================================
    // 9. TAREA: check_result
    //
    //    Compara result_out con expected y verifica done_seen.
    //    Imprime un reporte PASS/FAIL con todos los detalles del caso.
    //    Actualiza los contadores globales passed / failed.
    //
    //    Parámetros:
    //      A_val    [6:0]  — operando A (para reporte)
    //      B_val    [6:0]  — operando B (para reporte)
    //      op_val   [2:0]  — opcode (para reporte)
    //      expected [7:0]  — resultado esperado (calculado externamente)
    //      desc     [79:0] — descripción del caso (hasta 10 caracteres ASCII)
    // =========================================================================

    task check_result;
        input [6:0]  A_val;
        input [6:0]  B_val;
        input [2:0]  op_val;
        input [7:0]  expected;
        input [79:0] desc;
        begin
            test_num = test_num + 1;

            if (done_seen && (result_out === expected)) begin
                $display("[%02d] PASS | %-10s | A=%3d B=%3d op=%3b | got=0x%02X exp=0x%02X | Done=%b",
                         test_num, desc, A_val, B_val, op_val,
                         result_out, expected, done_seen);
                passed = passed + 1;
            end else begin
                $display("[%02d] FAIL | %-10s | A=%3d B=%3d op=%3b | got=0x%02X exp=0x%02X | Done=%b  <<<",
                         test_num, desc, A_val, B_val, op_val,
                         result_out, expected, done_seen);
                failed = failed + 1;
            end
        end
    endtask

    // =========================================================================
    // 10. BLOQUE PRINCIPAL DE PRUEBAS
    //
    //     Cubre los 20 casos de prueba organizados en 5 bloques funcionales,
    //     siguiendo el protocolo del reto del Bootcamp IEEE OpenSilicon 2026.
    // =========================================================================

    initial begin
        // ── Inicialización de señales y contadores ────────────────────────────
        clk      = 1'b0;
        rst_n    = 1'b0;
        ena      = 1'b1;         // TinyTapeout: always enabled
        ui_in    = 8'h00;
        uio_in   = 8'h00;
        passed   = 0;
        failed   = 0;
        test_num = 0;

        $display("================================================================");
        $display("  tt_um_alu7b_tb — Bootcamp IEEE OpenSilicon / IEEE CASS UTP 2026");
        $display("  DUT: tt_um_alu7b (TinyTapeout top-level)");
        $display("  Protocolo: 14 bits serial (7A + 7B), opcode paralelo ui_in[3:1]");
        $display("  Shuttle: SKY26a  |  PDK: sky130A  |  Reloj: %0dns (%0dMHz)",
                 CLK_PERIOD, 1000/CLK_PERIOD);
        $display("================================================================");
        $display("  #  | ESTADO | CASO       | A   B   op  | got  exp  | Done");
        $display("----------------------------------------------------------------");

        // =====================================================================
        // BLOQUE A — SUMA (op = 3'b000)
        //
        //   RTL: result = {1'b0, A} + {1'b0, B}
        //   result[7] = carry-out (1 cuando A + B >= 128)
        //
        //   Fórmula Python equivalente: expected = (A + B) & 0xFF
        // =====================================================================

        // A.1 — Suma normal sin carry: 20 + 30 = 50
        run_operation(7'd20, 7'd30, OP_ADD);
        check_result(7'd20, 7'd30, OP_ADD,
                     (8'd20 + 8'd30) & 8'hFF, "ADD_NRM_1 ");

        // A.2 — Suma normal sin carry: 10 + 15 = 25
        run_operation(7'd10, 7'd15, OP_ADD);
        check_result(7'd10, 7'd15, OP_ADD,
                     (8'd10 + 8'd15) & 8'hFF, "ADD_NRM_2 ");

        // A.3 — Suma con carry: 100 + 100 = 200 = 0xC8 (bit[7]=1)
        run_operation(7'd100, 7'd100, OP_ADD);
        check_result(7'd100, 7'd100, OP_ADD,
                     (8'd100 + 8'd100) & 8'hFF, "ADD_CARRY ");

        // A.4 — Suma con ambos operandos en cero: 0 + 0 = 0
        run_operation(7'd0, 7'd0, OP_ADD);
        check_result(7'd0, 7'd0, OP_ADD,
                     8'd0, "ADD_ZERO  ");

        // A.5 — Límite 7 bits: 127 + 1 = 128 = 0x80 (carry, resultado = 2^7)
        run_operation(7'd127, 7'd1, OP_ADD);
        check_result(7'd127, 7'd1, OP_ADD,
                     (8'd127 + 8'd1) & 8'hFF, "ADD_LIMIT ");

        // A.6 — Ambos operandos al máximo: 127 + 127 = 254 = 0xFE (carry)
        run_operation(7'd127, 7'd127, OP_ADD);
        check_result(7'd127, 7'd127, OP_ADD,
                     (8'd127 + 8'd127) & 8'hFF, "ADD_MAXMAX");

        // =====================================================================
        // BLOQUE B — AND LÓGICO (op = 3'b001)
        //
        //   RTL: result = {1'b0, A & B}
        //   result[7] = 0 siempre (operación lógica de 7 bits)
        //
        //   Fórmula Python equivalente: expected = (A & B) & 0x7F
        // =====================================================================

        // B.1 — Máscara parcial: 0b1010101 & 0b1100110 = 0b1000100 = 0x44
        run_operation(7'b1010101, 7'b1100110, OP_AND);
        check_result(7'b1010101, 7'b1100110, OP_AND,
                     {1'b0, 7'b1010101 & 7'b1100110}, "AND_MASK  ");

        // B.2 — Aniquilación: cualquier valor & 0 = 0
        run_operation(7'h7F, 7'h00, OP_AND);
        check_result(7'h7F, 7'h00, OP_AND,
                     8'h00, "AND_ZERO  ");

        // B.3 — Identidad: 0x7F & 0x7F = 0x7F
        run_operation(7'h7F, 7'h7F, OP_AND);
        check_result(7'h7F, 7'h7F, OP_AND,
                     8'h7F, "AND_IDET  ");

        // B.4 — Patrón cruzado alternado: 0b0101010 & 0b1010101 = 0
        run_operation(7'b0101010, 7'b1010101, OP_AND);
        check_result(7'b0101010, 7'b1010101, OP_AND,
                     8'h00, "AND_XALT  ");

        // =====================================================================
        // BLOQUE C — OR LÓGICO (op = 3'b010)
        //
        //   RTL: result = {1'b0, A | B}
        //   result[7] = 0 siempre
        //
        //   Fórmula Python equivalente: expected = (A | B) & 0x7F
        // =====================================================================

        // C.1 — Patrones complementarios: 0b0101010 | 0b0010101 = 0b0111111 = 0x3F
        run_operation(7'b0101010, 7'b0010101, OP_OR);
        check_result(7'b0101010, 7'b0010101, OP_OR,
                     {1'b0, 7'b0101010 | 7'b0010101}, "OR_CMPL   ");

        // C.2 — Identidad del OR: 0x00 | 0x7F = 0x7F
        run_operation(7'h00, 7'h7F, OP_OR);
        check_result(7'h00, 7'h7F, OP_OR,
                     8'h7F, "OR_IDET   ");

        // C.3 — Ambos máximos: 0x7F | 0x7F = 0x7F
        run_operation(7'h7F, 7'h7F, OP_OR);
        check_result(7'h7F, 7'h7F, OP_OR,
                     8'h7F, "OR_MAXMAX ");

        // =====================================================================
        // BLOQUE D — XOR LÓGICO (op = 3'b011)
        //
        //   RTL: result = {1'b0, A ^ B}
        //   result[7] = 0 siempre
        //
        //   Fórmula Python equivalente: expected = (A ^ B) & 0x7F
        // =====================================================================

        // D.1 — Diferencia de bits: 0b1111111 ^ 0b1010101 = 0b0101010 = 0x2A
        run_operation(7'b1111111, 7'b1010101, OP_XOR);
        check_result(7'b1111111, 7'b1010101, OP_XOR,
                     {1'b0, 7'b1111111 ^ 7'b1010101}, "XOR_DIFF  ");

        // D.2 — Auto-cancelación: A ^ A = 0 (para cualquier A)
        run_operation(7'b1100110, 7'b1100110, OP_XOR);
        check_result(7'b1100110, 7'b1100110, OP_XOR,
                     8'h00, "XOR_SELF  ");

        // D.3 — Alternado completo: 0b1010101 ^ 0b0101010 = 0b1111111 = 0x7F
        run_operation(7'b1010101, 7'b0101010, OP_XOR);
        check_result(7'b1010101, 7'b0101010, OP_XOR,
                     {1'b0, 7'b1010101 ^ 7'b0101010}, "XOR_ALT   ");

        // D.4 — Identidad XOR: A ^ 0 = A (con A = 0x7F)
        run_operation(7'h7F, 7'h00, OP_XOR);
        check_result(7'h7F, 7'h00, OP_XOR,
                     8'h7F, "XOR_IDET  ");

        // =====================================================================
        // BLOQUE E — RESTA (op = 3'b100)
        //
        //   RTL: result = {1'b0, A} - {1'b0, B}  (aritmética 8 bits)
        //   result[7] = 1 cuando A < B (borrow, representación en complemento a 2)
        //
        //   Fórmula Python equivalente: expected = (A - B) & 0xFF
        //   Caso underflow: resultado negativo en complemento a 2 de 8 bits
        //     Ejemplo: 10 - 30 = -20 → 0x100 - 20 = 0xEC = 236
        // =====================================================================

        // E.1 — Resta positiva: 50 - 20 = 30 (sin borrow)
        run_operation(7'd50, 7'd20, OP_SUB);
        check_result(7'd50, 7'd20, OP_SUB,
                     (8'd50 - 8'd20) & 8'hFF, "SUB_POS   ");

        // E.2 — A igual B: 77 - 77 = 0 (sin borrow)
        run_operation(7'd77, 7'd77, OP_SUB);
        check_result(7'd77, 7'd77, OP_SUB,
                     8'h00, "SUB_ZERO  ");

        // E.3 — Underflow: 10 - 30 → complemento a 2 → 0xEC, bit[7]=1 (borrow)
        run_operation(7'd10, 7'd30, OP_SUB);
        check_result(7'd10, 7'd30, OP_SUB,
                     (8'd10 - 8'd30) & 8'hFF, "SUB_UNDF  ");

        // =====================================================================
        // FIN DE LOS CASOS DE PRUEBA
        // =====================================================================

        #(CLK_PERIOD * 4);   // Margen de estabilización antes del resumen

        $display("================================================================");
        $display("  RESUMEN FINAL: %0d PASS  /  %0d FAIL  (total %0d casos)",
                 passed, failed, passed + failed);
        $display("================================================================");

        if (failed == 0) begin
            $display("  RESULTADO GLOBAL: *** TODOS LOS CASOS PASARON EXITOSAMENTE ***");
            $display("  El módulo tt_um_alu7b cumple el protocolo del Bootcamp.");
        end else begin
            $display("  RESULTADO GLOBAL: *** %0d CASO(S) FALLARON — REVISAR RTL ***",
                     failed);
            $display("  Verifique: protocolo serial LSB-first, FSM states,");
            $display("  opcode en ui_in[3:1], Done en uio_out[0].");
        end

        $display("================================================================");
        $finish;
    end

    // =========================================================================
    // 11. WATCHDOG — Límite de tiempo de simulación
    //
    //     Evita que la simulación corra indefinidamente en caso de deadlock
    //     (por ejemplo, si Done nunca llega).
    //     Límite: 200 µs = 10.000 ciclos de 20 ns.
    // =========================================================================

    initial begin
        #200000;
        $display("[WATCHDOG] Tiempo límite de simulación superado (200 us). Abortando.");
        $display("[WATCHDOG] Posible deadlock: verificar FSM y protocolo serial.");
        $finish;
    end

endmodule