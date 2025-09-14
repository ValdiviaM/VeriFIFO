class checker_scoreboard #(parameter int bits=32, parameter int DEPTH=16);
  // Mailboxes
  mailbox mon2scb;  // pkt2 del monitor
  mailbox cmd2scb;  // pkt3 del test 

  bit [bits-1:0] ref_q[$]; // más viejo en ref_q[0]

  // Estadísticas
  longint n_items=0, n_idle=0, n_push=0, n_pop=0, n_both=0;
  longint n_mismatch=0, n_overflow=0, n_underflw=0;
  int occ_min=0, occ_max=0;

  function new(mailbox mon2scb_i, mailbox cmd2scb_i);
    mon2scb = mon2scb_i;
    cmd2scb = cmd2scb_i;
  endfunction

  task run();
    fork
      consume_pkt2();
      consume_cmds();
    join_none
  endtask

  task consume_cmds();
    pkt3 cmd;
    forever begin
      cmd2scb.get(cmd);
      if (cmd.reporte_completo) print_report("REPORTE_COMPLETO");
    end
  endtask

  task consume_pkt2();
    pkt2#(bits) it;
    forever begin
      mon2scb.get(it);
      n_items++;

      // Estado previo
      int occ_pre = ref_q.size();
      bit [bits-1:0] head_pre = (occ_pre>0) ? ref_q[0] : '0;

      bit do_push = it.push;
      bit do_pop  = it.pop;
      bit idle    = !(do_push || do_pop);

      // ================= IDLE =================
      if (idle) begin
        n_idle++;
        // Flags esperadas (post = pre)
        bit exp_pndng = (occ_pre > 0);
        bit exp_full  = (occ_pre == DEPTH);

        if (it.pndng !== exp_pndng) begin n_mismatch++; $error("[SCB][IDLE] pndng exp=%0b got=%0b (occ=%0d)", exp_pndng, it.pndng, occ_pre); end
        if (it.full  !== exp_full ) begin n_mismatch++; $error("[SCB][IDLE] full  exp=%0b got=%0b (occ=%0d)", exp_full , it.full , occ_pre); end
        if (occ_pre > 0 && it.Dout !== head_pre) begin
          n_mismatch++; $error("[SCB][IDLE] Dout estable exp=0x%0h got=0x%0h", head_pre, it.Dout);
        end

        update_occ_bounds(occ_pre);
        continue;
      end

      // =========== OPERACIONES (PUSH / POP / BOTH) ===========

      if (do_pop) begin
        if (occ_pre > 0) begin
          void'(ref_q.pop_front());
          occ_pre--; 
        end else begin
          n_underflw++;
        end
      end

      if (do_push) begin
        if (occ_pre < DEPTH) begin
          ref_q.push_back(it.Din);
          occ_pre++;
        end else begin
          // OVERFLOW: descartar el más viejo y luego agregar Din
          void'(ref_q.pop_front());
          ref_q.push_back(it.Din);
          // ocupación se mantiene en DEPTH
          n_overflow++;
        end
      end

      // Post-estado
      int occ_post = ref_q.size();
      bit exp_pndng = (occ_post > 0);
      bit exp_full  = (occ_post == DEPTH);
      bit [bits-1:0] exp_dout = (occ_post > 0) ? ref_q[0] : '0;

      // Contadores de tipo de op
      if (do_push && do_pop) n_both++;
      else if (do_push)      n_push++;
      else                   n_pop++;

      // Comparaciones
      if (it.pndng !== exp_pndng) begin n_mismatch++; $error("[SCB] pndng exp=%0b got=%0b (occ=%0d)", exp_pndng, it.pndng, occ_post); end
      if (it.full  !== exp_full ) begin n_mismatch++; $error("[SCB] full  exp=%0b got=%0b (occ=%0d)", exp_full , it.full , occ_post); end
      if (exp_pndng && it.Dout !== exp_dout) begin
        n_mismatch++; $error("[SCB] Dout exp=0x%0h got=0x%0h (op=%s)", exp_dout, it.Dout, it.op_name());
      end

      update_occ_bounds(occ_post);
    end
  endtask

  // Bounds de ocupación
  function void update_occ_bounds(int occ_now);
    if (occ_now < occ_min) occ_min = occ_now;
    if (occ_now > occ_max) occ_max = occ_now;
  endfunction

  // ---- Reporte completo ----
  function void print_report(string tag="REPORTE");
    int occ_final = ref_q.size();
    $display("\n==== %s ====", tag);
    $display("items=%0d  idle=%0d  push=%0d  pop=%0d  both=%0d",
              n_items, n_idle, n_push, n_pop, n_both);
    $display("mismatches=%0d  overflow=%0d  underflow=%0d",
              n_mismatch, n_overflow, n_underflw);
    $display("occ: min=%0d  max=%0d  final=%0d  depth=%0d",
              occ_min, occ_max, occ_final, DEPTH);
    $display("==============\n");
  endfunction
endclass

