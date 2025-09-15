// ==================== SUPPORT MODULES ====================
module dff_async_rst (
    input data,
    input clk,
    input reset,
    output reg q
);
  always @(posedge clk or posedge reset)
    if (reset) begin
      q <= 1'b0;
    end else begin
      q <= data;
    end
endmodule

module prll_d_reg #(
    parameter bits = 32
) (
    input clk,
    input reset,
    input [bits-1:0] D_in,
    output [bits-1:0] D_out
);
  genvar i;
  generate
    for (i = 0; i < bits; i = i + 1) begin : bit_
      dff_async_rst prll_regstr_ (
          .data(D_in[i]),
          .clk(clk),
          .reset(reset),
          .q(D_out[i])
      );
    end
  endgenerate
endmodule

// ==================== DUT MODULE ====================
module fifo_flops #(
    parameter depth = 16,
    parameter bits  = 32
) (
    input [bits-1:0] Din,
    output reg [bits-1:0] Dout,
    input push,
    input pop,
    input clk,
    output reg full,
    output reg pndng,
    input rst
);
  wire [bits-1:0] q[depth-1:0];
  reg [$clog2(depth):0] count;
  reg [bits-1:0] aux_mux[depth-1:0];
  reg [bits-1:0] aux_mux_or[depth-2:0];

  genvar i;
  generate
    for (i = 0; i < depth; i = i + 1) begin : _dp_
      if (i == 0) begin : _dp2_
        prll_d_reg #(bits) D_reg (
            .clk  (push),
            .reset(rst),
            .D_in (Din),
            .D_out(q[i])
        );
        always @(*) begin
          aux_mux[i] = (count == i + 1) ? q[i] : {bits{1'b0}};
        end
      end else begin : _dp3_
        prll_d_reg #(bits) D_reg (
            .clk  (push),
            .reset(rst),
            .D_in (q[i-1]),
            .D_out(q[i])
        );
        always @(*) begin
          aux_mux[i] = (count == i + 1) ? q[i] : {bits{1'b0}};
        end
      end
    end
  endgenerate

  generate
    for (i = 0; i < depth - 2; i = i + 1) begin : _nu_
      always @(*) begin
        aux_mux_or[i] = aux_mux[i] | aux_mux_or[i+1];
      end
    end
  endgenerate

  always @(*) begin
    aux_mux_or[depth-2] = aux_mux[depth-1] | aux_mux[depth-2];
    Dout = aux_mux_or[0];
  end

  always @(posedge clk) begin
    if (rst) begin
      count <= 0;
    end else begin
      case ({push, pop})
        2'b00: count <= count;
        2'b01: begin
          if (count == 0) begin
            count <= 0;
          end else begin
            count <= count - 1;
          end
        end
        2'b10: begin
          if (count == depth) begin
            count <= count;
          end else begin
            count <= count + 1;
          end
        end
        2'b11: count <= count;
      endcase
    end
  end
  
  // Fix: Move flag updates to separate always block to avoid race conditions
  always @(posedge clk) begin
    if (rst) begin
      pndng <= 1'b0;
      full  <= 1'b0;
    end else begin
      pndng <= (count != 0);
      full  <= (count == depth);
    end
  end
endmodule

// ==================== INTERFACE ====================
interface IF_dut #(parameter DataWidth = 32) (input bit clk);
    logic                 push;      
    logic [DataWidth-1:0] Din;      
    logic                 pop;      
    logic [DataWidth-1:0] Dout;     
    logic                 pndng;     
    logic                 full;      
    logic                 rst;       
endinterface

// ==================== PACKET CLASSES ====================
class pkt2 #(parameter bits = 32);
    rand bit [bits-1:0] Din;
    bit [bits-1:0] Dout;
    rand bit push;
    rand bit pop;
    bit full;
    bit pndng;

    function string op_name();
        if (push && pop) return "BOTH";
        if (push)        return "PUSH";
        if (pop)         return "POP";
        return "NONE";
    endfunction

    function void print(string tag="");
        $display("T=%0t %s | op=%s | Din=0x%0h Dout=0x%0h | pndng=%0b full=%0b | push=%0b pop=%0b", 
        $time, tag, op_name(), Din, Dout, pndng, full, push, pop);
    endfunction
endclass

class pkt1;
    // FIXED: Use enum instead of rand string
    typedef enum {
        WRITE_UNTIL_FULL,
        READ_UNTIL_EMPTY, 
        WR_AT_THE_SAME_TIME,
        WR_RANDOM_VALUES,
        WRITE_RANDOM,
        READ_RANDOM
    } mode_e;
    
    rand mode_e mode;
    rand int num_transactions;
    rand int min_delay;
    rand int max_delay;
    rand bit enable_back_pressure;
    int fifo_depth;  
    
    constraint c_mode {
        mode inside {WRITE_UNTIL_FULL, READ_UNTIL_EMPTY, WR_AT_THE_SAME_TIME, 
                    WR_RANDOM_VALUES, WRITE_RANDOM, READ_RANDOM};
    }
    
    constraint c_transactions {
        num_transactions inside {[10:50]};
    }
    
    constraint c_delays {
        min_delay inside {[0:2]};
        max_delay inside {[1:5]};
        max_delay > min_delay;
    }
    
    constraint c_back_pressure {
        enable_back_pressure dist {0 := 30, 1 := 70}; 
    }
    
    function new();
        fifo_depth = 16;  
    endfunction
    
    // Helper function to convert enum to string
    function string get_mode_string();
        case(mode)
            WRITE_UNTIL_FULL:    return "WRITE_UNTIL_FULL";
            READ_UNTIL_EMPTY:    return "READ_UNTIL_EMPTY";
            WR_AT_THE_SAME_TIME: return "WR_AT_THE_SAME_TIME";
            WR_RANDOM_VALUES:    return "WR_RANDOM_VALUES";
            WRITE_RANDOM:        return "WRITE_RANDOM";
            READ_RANDOM:         return "READ_RANDOM";
            default:             return "UNKNOWN";
        endcase
    endfunction
    
    function void print(string tag = "pkt1");
        $display("T=%0t [%s] mode=%s, num_trans=%0d, delay=[%0d:%0d], back_pressure=%0b", 
                $time, tag, get_mode_string(), num_transactions, min_delay, max_delay, enable_back_pressure);
    endfunction
endclass


class pkt3;
    bit reporte_completo;

    function new(bit rc = 1);
        reporte_completo = rc; 
    endfunction

    function void print(string tag="pkt3");
        $display("[%s] reporte_completo=%0b", tag, reporte_completo);
    endfunction
endclass

// ==================== VERIFICATION COMPONENTS ====================
class Driver;
    virtual IF_dut vif;
    event drv_done;
    mailbox drv_mbx;

    task run();
        $display("T=%0t [Driver] starting ...", $time);
        
        // Initialize interface signals
        vif.push <= 0;
        vif.pop <= 0;
        vif.Din <= 0;
        
        @(posedge vif.clk);

        forever begin
            pkt2 pkt;
            $display("T=%0t [Driver] waiting for item ...",$time);
            drv_mbx.get(pkt);
            pkt.print("Driver");

            vif.push <= pkt.push;        
            vif.Din <= pkt.Din;          
            vif.pop <= pkt.pop;          

            @(posedge vif.clk);

            vif.Din <= 0;                
            vif.push <= 0;               
            vif.pop <= 0;                

            ->drv_done;  
        end
    endtask
endclass

class monitor;
    virtual IF_dut vif;    
    mailbox scb_mbx;

    function new(virtual IF_dut vif_i=null, mailbox mbx_i=null);
        vif = vif_i; 
        scb_mbx = mbx_i; 
    endfunction

    task run();
        $display("T=%0t [Monitor] starting ...", $time);
        sample_port();
    endtask

    task sample_port();
        forever begin
            @(posedge vif.clk);
            if(!vif.rst) begin
                pkt2 item = new;
                
                // Capture inputs at current time
                item.Din  = vif.Din;
                item.push = vif.push;
                item.pop  = vif.pop;

                // Wait for next clock to capture outputs
                @(posedge vif.clk);
                
                // Capture outputs
                item.full  = vif.full;
                item.pndng = vif.pndng;
                item.Dout  = vif.Dout;

                scb_mbx.put(item);
                item.print("Monitor");
            end
        end
    endtask
endclass

class checker_scoreboard #(parameter int bits=32, parameter int DEPTH=16);
    mailbox mon2scb;
    mailbox cmd2scb;
    bit [bits-1:0] ref_q[$];
    longint n_items=0, n_idle=0, n_push=0, n_pop=0, n_both=0;
    longint n_mismatch=0, n_overflow=0, n_underflw=0;
    int occ_min=0, occ_max=0;

    function new(mailbox mon2scb_i, mailbox cmd2scb_i);
        mon2scb = mon2scb_i;
        cmd2scb = cmd2scb_i;
    endfunction

    task run();
        $display("T=%0t [Scoreboard] starting ...", $time);
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
            // Declare all variables at the beginning of the task
            int occ_pre, occ_post;
            bit [bits-1:0] head_pre;
            bit do_push, do_pop, idle;
            bit exp_pndng, exp_full;
            bit [bits-1:0] exp_dout;
            
            mon2scb.get(it);
            n_items++;

            occ_pre = ref_q.size();
            head_pre = (occ_pre>0) ? ref_q[0] : '0;

            do_push = it.push;
            do_pop  = it.pop;
            idle    = !(do_push || do_pop);

            if (idle) begin
                n_idle++;
                exp_pndng = (occ_pre > 0);
                exp_full  = (occ_pre == DEPTH);

                if (it.pndng !== exp_pndng) begin 
                    n_mismatch++; 
                    $error("[SCB][IDLE] pndng exp=%0b got=%0b (occ=%0d)", exp_pndng, it.pndng, occ_pre); 
                end
                if (it.full !== exp_full) begin 
                    n_mismatch++; 
                    $error("[SCB][IDLE] full exp=%0b got=%0b (occ=%0d)", exp_full, it.full, occ_pre); 
                end
                if (occ_pre > 0 && it.Dout !== head_pre) begin
                    n_mismatch++; 
                    $error("[SCB][IDLE] Dout stable exp=0x%0h got=0x%0h", head_pre, it.Dout);
                end

                update_occ_bounds(occ_pre);
                continue;
            end

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
                    void'(ref_q.pop_front());
                    ref_q.push_back(it.Din);
                    n_overflow++;
                end
            end

            occ_post = ref_q.size();
            exp_pndng = (occ_post > 0);
            exp_full  = (occ_post == DEPTH);
            exp_dout = (occ_post > 0) ? ref_q[0] : '0;

            if (do_push && do_pop) n_both++;
            else if (do_push)      n_push++;
            else                   n_pop++;

            if (it.pndng !== exp_pndng) begin 
                n_mismatch++; 
                $error("[SCB] pndng exp=%0b got=%0b (occ=%0d)", exp_pndng, it.pndng, occ_post); 
            end
            if (it.full !== exp_full) begin 
                n_mismatch++; 
                $error("[SCB] full exp=%0b got=%0b (occ=%0d)", exp_full, it.full, occ_post); 
            end
            if (exp_pndng && it.Dout !== exp_dout) begin
                n_mismatch++; 
                $error("[SCB] Dout exp=0x%0h got=0x%0h (op=%s)", exp_dout, it.Dout, it.op_name());
            end

            update_occ_bounds(occ_post);
        end
    endtask

    function void update_occ_bounds(int occ_now);
        if (occ_now < occ_min) occ_min = occ_now;
        if (occ_now > occ_max) occ_max = occ_now;
    endfunction

    function void print_report(string tag="REPORTE");
        int occ_final;
        occ_final = ref_q.size();
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

class Generator;
    mailbox drv_mbx;
    event drv_done;
    pkt1 pkt_in;
    int trans_count;

    task run();
          // Wait until the test assigns pkt_in
        if (pkt_in == null) begin
            $display("T=%0t [Generator] waiting for configuration...", $time);
            wait (pkt_in != null);
        end

        trans_count = 0;
        $display("T=%0t [Generator] Starting with mode: %s", $time, pkt_in.get_mode_string());
        
        case (pkt_in.mode)
            pkt1::WRITE_UNTIL_FULL:     gen_write_until_full();
            pkt1::READ_UNTIL_EMPTY:     gen_read_until_empty();
            pkt1::WR_AT_THE_SAME_TIME:  gen_wr_at_the_same_time();
            pkt1::WR_RANDOM_VALUES:     gen_wr_random_order();
            pkt1::WRITE_RANDOM:         gen_write_random(); 
            pkt1::READ_RANDOM:          gen_read_random();
            default: $display("T=%0t [Generator] ERROR: Unknown mode %s", $time, pkt_in.get_mode_string());
        endcase
        
        $display("T=%0t [Generator] Completed %0d transactions", $time, trans_count);
    endtask

    // Rest of Generator tasks remain the same...
    task gen_write_until_full();
        pkt2 pkt_out;
        for (int i = 0; i < pkt_in.fifo_depth + 2; i++) begin
            pkt_out = new();
            write_once(pkt_out);
            drv_mbx.put(pkt_out);
            trans_count++;
            @drv_done;
            add_random_delay();
        end
    endtask

    task gen_read_until_empty();
        pkt2 pkt_out;
        for (int i = 0; i < pkt_in.fifo_depth + 2; i++) begin
            pkt_out = new();
            read_once(pkt_out);
            drv_mbx.put(pkt_out);
            trans_count++;
            @drv_done;
            add_random_delay();
        end
    endtask

    task gen_wr_at_the_same_time();
        pkt2 pkt_out;
        for (int i = 0; i < pkt_in.num_transactions; i++) begin
            pkt_out = new();
            pkt_out.randomize();
            pkt_out.push = 1;
            pkt_out.pop = 1;
            drv_mbx.put(pkt_out);
            trans_count++;
            @drv_done;
            add_random_delay();
        end
    endtask

    task gen_wr_random_order();
        pkt2 pkt_out;
        for (int i = 0; i < pkt_in.num_transactions; i++) begin
            pkt_out = new();
            if ($urandom_range(0, 1)) begin
                write_once(pkt_out);
            end else begin
                read_once(pkt_out);
            end
            drv_mbx.put(pkt_out);
            trans_count++;
            @drv_done;
            add_random_delay();
        end
    endtask

    task gen_write_random();
        pkt2 pkt_out;
        for (int i = 0; i < pkt_in.num_transactions; i++) begin
            pkt_out = new();
            write_once(pkt_out);
            if (pkt_in.enable_back_pressure && ($urandom_range(0, 9) < 3)) begin
                add_idle_cycle();
            end
            drv_mbx.put(pkt_out);
            trans_count++;
            @drv_done;
            add_random_delay();
        end
    endtask

    task gen_read_random();
        pkt2 pkt_out;
        for (int i = 0; i < pkt_in.num_transactions; i++) begin
            pkt_out = new();
            read_once(pkt_out);
            if (pkt_in.enable_back_pressure && ($urandom_range(0, 9) < 3)) begin
                add_idle_cycle();
            end
            drv_mbx.put(pkt_out);
            trans_count++;
            @drv_done;
            add_random_delay();
        end
    endtask

    task write_once(pkt2 pkt_out);
        pkt_out.randomize();
        pkt_out.push = 1;
        pkt_out.pop = 0;
    endtask

    task read_once(pkt2 pkt_out);
        pkt_out.randomize();
        pkt_out.push = 0;
        pkt_out.pop = 1;
    endtask
    
    task add_idle_cycle();
        pkt2 pkt_out;
        pkt_out = new();
        pkt_out.push = 0;
        pkt_out.pop = 0;
        pkt_out.Din = 0;
        drv_mbx.put(pkt_out);
        @drv_done;
    endtask
    
    task add_random_delay();
        int delay;
        delay = $urandom_range(pkt_in.min_delay, pkt_in.max_delay);
        for (int i = 0; i < delay; i++) begin
            add_idle_cycle();
        end
    endtask
endclass
// ==================== ENVIRONMENT ====================
class env;
    Driver d0;
    monitor m0;
    Generator g0;
    checker_scoreboard #(.bits(32), .DEPTH(16)) s0;
    
    mailbox drv_mbx;
    mailbox mon2scb_mbx;
    mailbox cmd2scb_mbx;
    
    event drv_done;
    virtual IF_dut vif;
    
    function new();
        drv_mbx = new();
        mon2scb_mbx = new();
        cmd2scb_mbx = new();
        
        d0 = new();
        m0 = new(null, mon2scb_mbx);
        g0 = new();
        s0 = new(mon2scb_mbx, cmd2scb_mbx);
        
        g0.drv_mbx = drv_mbx;
        g0.drv_done = drv_done;
        d0.drv_mbx = drv_mbx;
        d0.drv_done = drv_done;
    endfunction
    
    virtual task run();
        d0.vif = vif;
        m0.vif = vif;
        
        fork
            d0.run();
            m0.run();
            g0.run();
            s0.run();
        join_any
    endtask
endclass

// ==================== UPDATED TEST CLASS ====================
class test;
    Generator g0;
    mailbox gen_mbx;
    mailbox scb_mbx;
    event gen_done;
    
    function new();
        g0 = new();
        gen_mbx = new();
        scb_mbx = new();
    endfunction
    
    task run();
        $display("T=%0t [Test] Starting FIFO test", $time);
        
        fork
            configure_and_run_generator();
            configure_scoreboard();
        join
        
        $display("T=%0t [Test] Test completed", $time);
    endtask
    
    task configure_and_run_generator();
        pkt1 gen_config;
        gen_config = new();
        
        if (!gen_config.randomize()) 
            $fatal("Failed to randomize generator config");
        
        gen_config.print("Test->Gen");
        
        g0.pkt_in = gen_config;
        g0.drv_mbx = gen_mbx;
        g0.drv_done = gen_done;
        
        $display("T=%0t [Test] Starting generator with mode: %s", $time, gen_config.get_mode_string());
        g0.run();
    endtask
    
    task configure_scoreboard();
        pkt3 scb_config;
        scb_config = new(1);
        $display("T=%0t [Test] Sending config to scoreboard", $time);
        scb_config.print("Test->SCB");
        scb_mbx.put(scb_config);
    endtask
endclass

// ==================== FIXED TESTBENCH TOP MODULE ====================
program automatic test_program;
    // FIXED: Move class instantiation to program block
    env e0;
    test t0;
    
    initial begin
        e0 = new();
        t0 = new();
        
        // Connect interfaces
        e0.vif = tb_fifo.dut_if;
        
        // Connect mailboxes and events
        t0.gen_mbx = e0.drv_mbx;
        t0.scb_mbx = e0.cmd2scb_mbx;
        t0.gen_done = e0.drv_done;
        
        fork
            e0.run();
            begin
                wait(!tb_fifo.rst);
                repeat(2) @(posedge tb_fifo.clk);
                t0.run();
            end
        join_any
    end
endprogram

module tb_fifo;
    bit clk;
    bit rst;
    
    always #5 clk = ~clk;
    
    IF_dut #(.DataWidth(32)) dut_if(clk);
    assign dut_if.rst = rst;
    
    fifo_flops #(
        .depth(16),
        .bits(32)
    ) dut (
        .Din(dut_if.Din),
        .Dout(dut_if.Dout),
        .push(dut_if.push),
        .pop(dut_if.pop),
        .clk(clk),
        .full(dut_if.full),
        .pndng(dut_if.pndng),
        .rst(rst)
    );
    
    // FIXED: Moved class instantiation to program block
    initial begin        
        {clk, rst} <= 0;
        
        rst <= 1;
        repeat(5) @(posedge clk);
        rst <= 0;
        $display("T=%0t [TB] Reset released", $time);
        
        // Wait for test program to complete
        repeat(100) @(posedge clk);
        $display("T=%0t [TB] Simulation ending", $time);
        $finish;
    end
    
    // Instantiate test program
    test_program tp();
    
    initial begin
        $dumpfile("fifo_test.vcd");
        $dumpvars(0, tb_fifo);
    end
    
    initial begin
        #100000;
        $display("T=%0t [TB] ERROR: Simulation timeout!", $time);
        $finish;
    end
endmodule