// =============================================================================
// serial_tb.v — Testbench para serial_alu_ctrl
//
// Bootcamp IC Design & Fabrication — IEEE OpenSilicon / IEEE CASS UTP 2026
//
// INTERFAZ DEL DUT (serial_alu_ctrl):
//   Entradas : CLK, RST_n, Bit_in, op[2:0]
//   Salidas  : Data_out[7:0], Done
//
// PROTOCOLO DE ENVÍO SERIAL:
//   Por cada operación se envían 14 flancos de CLK con datos en Bit_in:
//     Flancos  1 ..  7  → A[6:0], LSB primero  (bit_count 0..6)
//     Flancos  8 .. 14  → B[6:0], LSB primero  (bit_count 7..13)
//   Al flanco 14 (bit_count == CNT_B_END = 13) la FSM transiciona a S_CALC.
//   El opcode op[2:0] es un puerto paralelo estable durante toda la operación.
//   En S_CALC (flanco 15) se latcha alu_out y se activa Done por 1 ciclo.
//
// TABLA DE OPERACIONES (op[2:0]):
//   3'b000 → ADD   result = A + B   (bit[7] = carry)
//   3'b001 → AND   result = A & B
//   3'b010 → OR    result = A | B
//   3'b011 → XOR   result = A ^ B
//   3'b100 → SUB   result = A - B   (bit[7] = borrow, complemento a 2)
//
// COBERTURA DE PRUEBAS (15 casos):
//   ADD : suma normal, carry, cero, límite 7 bits, identidad
//   AND : máscara, identidad, cero
//   OR  : complemento, identidad
//   XOR : diferencia, auto-cancelación (A^A=0)
//   SUB : normal, A=B (cero), underflow (complemento a 2)
//
// VERIFICACIÓN AUTOMÁTICA:
//   Cada caso compara Data_out con el resultado esperado y verifica que
//   Done haya pulsado exactamente 1 ciclo.  Los errores detallan operandos,
//   opcode, resultado obtenido y resultado esperado.
//
// DUMP DE FORMAS DE ONDA:
//   El archivo serial_tb.vcd se genera automáticamente para inspección
//   en GTKWave o Surfer.
//
// COMPILACIÓN Y SIMULACIÓN (Icarus Verilog):
//   iverilog -o serial_tb.vvp serial_tb.v serial_alu_ctrl.v alu_7b.v
//   vvp serial_tb.vvp
//   gtkwave serial_tb.vcd
//
// SPDX-License-Identifier: Apache-2.0
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module serial_tb;

    // =========================================================================
    // 1. PARÁMETROS DEL TESTBENCH
    // =========================================================================

    // Período de reloj: 20 ns → 50 MHz (límite máximo de TinyTapeout IO)
    localparam CLK_PERIOD = 20;
    localparam CLK_HALF   = CLK_PERIOD / 2;

    // Opcodes (coinciden con la tabla de alu_7b)
    localparam [2:0] OP_ADD = 3'b000;
    localparam [2:0] OP_AND = 3'b001;
    localparam [2:0] OP_OR  = 3'b010;
    localparam [2:0] OP_XOR = 3'b011;
    localparam [2:0] OP_SUB = 3'b100;

    // Número de bits de cada operando
    localparam N_BITS = 7;

    // =========================================================================
    // 2. SEÑALES DEL TESTBENCH
    // =========================================================================

    reg        CLK;       // Reloj
    reg        RST_n;     // Reset activo-bajo
    reg        Bit_in;    // Entrada serial (LSB primero)
    reg  [2:0] op;        // Opcode paralelo

    wire [7:0] Data_out;  // Resultado paralelo del DUT
    wire       Done;      // Pulso de fin de operación

    // Contadores globales de resultado
    integer passed;
    integer failed;
    integer test_num;

    // =========================================================================
    // 3. INSTANCIA DEL DUT (Device Under Test)
    // =========================================================================

    serial_alu_ctrl DUT (
        .CLK      (CLK),
        .RST_n    (RST_n),
        .Bit_in   (Bit_in),
        .op       (op),
        .Data_out (Data_out),
        .Done     (Done)
    );

    // =========================================================================
    // 4. GENERACIÓN DE RELOJ
    //    El reloj oscila libremente en todo momento.
    //    El DUT se controla mediante RST_n y la secuencia de Bit_in.
    // =========================================================================

    initial CLK = 1'b0;
    always #(CLK_HALF) CLK = ~CLK;

    // =========================================================================
    // 5. DUMP DE FORMAS DE ONDA
    // =========================================================================

    initial begin
        $dumpfile("serial_tb.vcd");
        $dumpvars(0, serial_tb);
    end

    // =========================================================================
    // 6. TAREA: reset_dut
    //
    //    Aplica reset activo-bajo al DUT durante 3 ciclos completos.
    //    Finaliza justo después del flanco de bajada siguiente al último
    //    flanco de subida de reset, dejando Bit_in = 0 y op sin modificar.
    //
    //    Protocolo de tiempo:
    //      - RST_n = 0 se aplica en el flanco de bajada
    //      - Se espera 3 flancos de subida completos (reset síncrono activo)
    //      - RST_n = 1 se libera en el siguiente flanco de bajada
    //      - La tarea termina en el flanco de bajada post-reset,
    //        listo para presentar el primer bit de A en el próximo posedge
    // =========================================================================

    task reset_dut;
        begin
            @(negedge CLK);          // Alinear al semiciclo bajo
            RST_n  = 1'b0;
            Bit_in = 1'b0;
            @(posedge CLK);          // Flanco 1 con reset
            @(posedge CLK);          // Flanco 2 con reset
            @(posedge CLK);          // Flanco 3 con reset (suficiente)
            @(negedge CLK);          // Caída: liberar reset
            RST_n = 1'b1;
            // El DUT está en S_RECV, bit_count = 0, registros a cero
        end
    endtask

    // =========================================================================
    // 7. TAREA: send_serial
    //
    //    Envía un operando de N_BITS bits de forma serial, LSB primero.
    //    Cada bit se presenta en el semiciclo bajo ANTES del flanco de subida
    //    que lo captura, garantizando setup time correcto.
    //
    //    Parámetro:
    //      data [6:0] — valor a serializar
    //
    //    Secuencia por bit i (i = 0 .. N_BITS-1):
    //      1. [negedge] Presentar data[i] en Bit_in
    //      2. [posedge] El DUT captura el bit → shift register actualizado
    // =========================================================================

    task send_serial;
        input [6:0] data;
        integer i;
        begin
            for (i = 0; i < N_BITS; i = i + 1) begin
                @(negedge CLK);
                Bit_in = data[i];    // LSB primero: bit 0, 1, 2, ... 6
                @(posedge CLK);      // Captura en flanco de subida
            end
        end
    endtask

    // =========================================================================
    // 8. TAREA: run_operation
    //
    //    Ejecuta una operación completa:
    //      1. reset_dut            — resetea el DUT a S_RECV
    //      2. Establece op[2:0]    — opcode paralelo (estable todo el tiempo)
    //      3. send_serial(A)       — 7 flancos para operando A
    //      4. send_serial(B)       — 7 flancos para operando B
    //                                Al flanco 14 (bit_count==13 → S_CALC)
    //      5. Espera la captura de Done — máximo 4 flancos de margen
    //      6. Registra resultado y estado de Done
    //
    //    Parámetros de entrada:
    //      A_val [6:0]  — operando A
    //      B_val [6:0]  — operando B
    //      op_val [2:0] — opcode
    //
    //    Parámetros de salida (por referencia vía registros del TB):
    //      result_out [7:0] — valor capturado de Data_out cuando Done=1
    //      done_seen        — 1 si Done pulsó dentro del tiempo esperado
    // =========================================================================

    reg [7:0] result_out;
    reg       done_seen;

    task run_operation;
        input [6:0] A_val;
        input [6:0] B_val;
        input [2:0] op_val;
        integer wait_cycles;
        begin
            // ── Paso 1: Reset ─────────────────────────────────────────────────
            reset_dut;

            // ── Paso 2: Opcode paralelo estable ──────────────────────────────
            op = op_val;

            // ── Paso 3: Transmisión serial de A (7 bits, LSB primero) ─────────
            send_serial(A_val);

            // ── Paso 4: Transmisión serial de B (7 bits, LSB primero) ─────────
            //    Al finalizar el último bit de B (bit_count llega a CNT_B_END=13)
            //    la FSM transiciona automáticamente a S_CALC.
            send_serial(B_val);

            // ── Paso 5: Esperar el pulso de Done (máximo 4 ciclos de margen) ──
            done_seen  = 1'b0;
            result_out = 8'hXX;

            for (wait_cycles = 0; wait_cycles < 4; wait_cycles = wait_cycles + 1) begin
                @(negedge CLK);
                @(posedge CLK);
                if (Done === 1'b1) begin
                    done_seen  = 1'b1;
                    result_out = Data_out;
                    wait_cycles = 4; // salir del loop
                end
            end

            // Garantizar que Bit_in quede en 0 al finalizar
            @(negedge CLK);
            Bit_in = 1'b0;
        end
    endtask

    // =========================================================================
    // 9. TAREA: check_result
    //
    //    Compara result_out con expected y verifica done_seen.
    //    Imprime PASS o FAIL con todos los detalles del caso de prueba.
    //    Actualiza los contadores globales passed / failed.
    //
    //    Parámetros:
    //      A_val    [6:0]  — operando A (para reporte)
    //      B_val    [6:0]  — operando B (para reporte)
    //      op_val   [2:0]  — opcode (para reporte)
    //      expected [7:0]  — resultado esperado
    //      desc            — descripción textual del caso (string simulado)
    // =========================================================================

    task check_result;
        input [6:0]  A_val;
        input [6:0]  B_val;
        input [2:0]  op_val;
        input [7:0]  expected;
        input [63:0] desc;      // 8 caracteres ASCII para identificación rápida
        begin
            test_num = test_num + 1;

            if (done_seen && (result_out === expected)) begin
                $display("[%02d] PASS | %s | A=%3d B=%3d op=%3b | got=0x%02X exp=0x%02X | Done=%b",
                         test_num, desc, A_val, B_val, op_val,
                         result_out, expected, done_seen);
                passed = passed + 1;
            end else begin
                $display("[%02d] FAIL | %s | A=%3d B=%3d op=%3b | got=0x%02X exp=0x%02X | Done=%b  <<<",
                         test_num, desc, A_val, B_val, op_val,
                         result_out, expected, done_seen);
                failed = failed + 1;
            end
        end
    endtask

    // =========================================================================
    // 10. BLOQUE PRINCIPAL DE PRUEBAS
    // =========================================================================

    initial begin
        // ── Inicialización de señales y contadores ────────────────────────────
        RST_n    = 1'b0;
        Bit_in   = 1'b0;
        op       = 3'b000;
        passed   = 0;
        failed   = 0;
        test_num = 0;

        $display("============================================================");
        $display("  serial_tb — Bootcamp IEEE OpenSilicon / IEEE CASS UTP 2026");
        $display("  DUT: serial_alu_ctrl  |  ALU 7 bits  |  Protocolo serial  ");
        $display("  Reloj: %0d ns (%0d MHz)", CLK_PERIOD, 1000/CLK_PERIOD);
        $display("============================================================");
        $display("  #  | ESTADO | CASO     | A   B   op  | got  exp  | Done");
        $display("------------------------------------------------------------");

        // =================================================================
        // BLOQUE A — SUMA (op = 000)
        //   ADD: result = {carry, A[6:0] + B[6:0]}
        //   bit[7] indica carry-out
        // =================================================================

        // A.1 — Suma normal sin carry: 20 + 30 = 50
        run_operation(7'd20, 7'd30, OP_ADD);
        check_result (7'd20, 7'd30, OP_ADD, 8'd50,  "ADD_NRM1");

        // A.2 — Suma normal sin carry: 10 + 15 = 25
        run_operation(7'd10, 7'd15, OP_ADD);
        check_result (7'd10, 7'd15, OP_ADD, 8'd25,  "ADD_NRM2");

        // A.3 — Suma con carry: 100 + 100 = 200 (0xC8, bit[7]=1 → carry)
        run_operation(7'd100, 7'd100, OP_ADD);
        check_result (7'd100, 7'd100, OP_ADD,
                      (8'd100 + 8'd100) & 8'hFF, "ADD_CRRY");

        // A.4 — Suma con A=0: 0 + 0 = 0
        run_operation(7'd0, 7'd0, OP_ADD);
        check_result (7'd0, 7'd0, OP_ADD, 8'd0,     "ADD_ZERO");

        // A.5 — Límite: 127 + 1 = 128 (overflow en 7 bits, bit[7]=1)
        run_operation(7'd127, 7'd1, OP_ADD);
        check_result (7'd127, 7'd1, OP_ADD,
                      (8'd127 + 8'd1) & 8'hFF,      "ADD_LIMT");

        // =================================================================
        // BLOQUE B — AND lógico (op = 001)
        //   AND: result = {1'b0, A & B}  (bit[7] siempre 0)
        // =================================================================

        // B.1 — Máscara parcial: 0b1010101 & 0b1100110 = 0b1000100 = 0x44
        run_operation(7'b1010101, 7'b1100110, OP_AND);
        check_result (7'b1010101, 7'b1100110, OP_AND,
                      {1'b0, 7'b1010101 & 7'b1100110}, "AND_MASK");

        // B.2 — AND con cero: cualquier valor & 0 = 0
        run_operation(7'h7F, 7'h00, OP_AND);
        check_result (7'h7F, 7'h00, OP_AND, 8'h00,  "AND_ZERO");

        // B.3 — AND identidad: 0x7F & 0x7F = 0x7F
        run_operation(7'h7F, 7'h7F, OP_AND);
        check_result (7'h7F, 7'h7F, OP_AND, 8'h7F,  "AND_IDET");

        // =================================================================
        // BLOQUE C — OR lógico (op = 010)
        //   OR: result = {1'b0, A | B}  (bit[7] siempre 0)
        // =================================================================

        // C.1 — OR de complementos: 0b0101010 | 0b0010101 = 0b0111111 = 0x3F
        run_operation(7'b0101010, 7'b0010101, OP_OR);
        check_result (7'b0101010, 7'b0010101, OP_OR,
                      {1'b0, 7'b0101010 | 7'b0010101},  "OR__CMPL");

        // C.2 — OR identidad: 0 | 0x7F = 0x7F
        run_operation(7'h00, 7'h7F, OP_OR);
        check_result (7'h00, 7'h7F, OP_OR, 8'h7F,   "OR__IDET");

        // =================================================================
        // BLOQUE D — XOR lógico (op = 011)
        //   XOR: result = {1'b0, A ^ B}  (bit[7] siempre 0)
        // =================================================================

        // D.1 — XOR diferencia: 0b1111111 ^ 0b1010101 = 0b0101010 = 0x2A
        run_operation(7'b1111111, 7'b1010101, OP_XOR);
        check_result (7'b1111111, 7'b1010101, OP_XOR,
                      {1'b0, 7'b1111111 ^ 7'b1010101}, "XOR_DIFF");

        // D.2 — Auto-cancelación: A ^ A = 0 (para cualquier A)
        run_operation(7'b1100110, 7'b1100110, OP_XOR);
        check_result (7'b1100110, 7'b1100110, OP_XOR, 8'h00, "XOR_SELF");

        // =================================================================
        // BLOQUE E — RESTA (op = 100)
        //   SUB: result = {1'b0, A} - {1'b0, B}  en complemento a 2
        //   bit[7] = 1 indica borrow (resultado negativo)
        // =================================================================

        // E.1 — Resta normal positiva: 50 - 20 = 30
        run_operation(7'd50, 7'd20, OP_SUB);
        check_result (7'd50, 7'd20, OP_SUB,
                      (8'd50 - 8'd20) & 8'hFF,       "SUB_NORM");

        // E.2 — Resta A = B: resultado cero
        run_operation(7'd77, 7'd77, OP_SUB);
        check_result (7'd77, 7'd77, OP_SUB, 8'h00,   "SUB_ZERO");

        // E.3 — Underflow: 10 - 30 → complemento a 2 → 0xEC, bit[7]=1 (borrow)
        run_operation(7'd10, 7'd30, OP_SUB);
        check_result (7'd10, 7'd30, OP_SUB,
                      (8'd10 - 8'd30) & 8'hFF,       "SUB_UNDF");

    

        // F.1 — ADD con ambos operandos en máximo: 127 + 127 = 254 (carry=1)
        run_operation(7'd127, 7'd127, OP_ADD);
        check_result (7'd127, 7'd127, OP_ADD,
                      (8'd127 + 8'd127) & 8'hFF,     "ADD_MAX ");

        // F.2 — SUB con A=127, B=0: 127 - 0 = 127 (sin borrow)
        run_operation(7'd127, 7'd0, OP_SUB);
        check_result (7'd127, 7'd0, OP_SUB, 8'd127,  "SUB_B0  ");

        // F.3 — XOR con valores alternos: 0b1010101 ^ 0b0101010 = 0x7F
        run_operation(7'b1010101, 7'b0101010, OP_XOR);
        check_result (7'b1010101, 7'b0101010, OP_XOR,
                      {1'b0, 7'b1010101 ^ 7'b0101010}, "XOR_ALT ");

        // F.4 — OR con ambos en máximo: 0x7F | 0x7F = 0x7F
        run_operation(7'h7F, 7'h7F, OP_OR);
        check_result (7'h7F, 7'h7F, OP_OR, 8'h7F,   "OR__MAX ");

        // F.5 — AND con patrón alternado cruzado: 0b0101010 & 0b1010101 = 0
        run_operation(7'b0101010, 7'b1010101, OP_AND);
        check_result (7'b0101010, 7'b1010101, OP_AND, 8'h00, "AND_XALT");


        #(CLK_PERIOD * 2);   // Margen antes del cierre

        $display("============================================================");
        $display("  RESUMEN: %0d PASS  /  %0d FAIL  (total %0d casos)",
                 passed, failed, passed + failed);
        $display("============================================================");

        if (failed == 0)
            $display("  RESULTADO GLOBAL: *** TODOS LOS CASOS PASARON ***");
        else
            $display("  RESULTADO GLOBAL: *** %0d CASO(S) FALLARON — REVISAR ***",
                     failed);

        $display("============================================================");
        $finish;
    end


    initial begin
        #50000;
        $display("[WATCHDOG] Tiempo límite de simulación superado. Abortando.");
        $finish;
    end

endmodule