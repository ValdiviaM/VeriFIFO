interface IF_dut #(parameter DataWidth = 32) (input bit clk);
    logic                 push;      
    logic [DataWidth-1:0] Din;      
    logic                 pop;      
    logic [DataWidth-1:0] Dout;     
    logic                 pndng;     
    logic                 full;      
    logic                 rst;       
endinterface //IF_dut   

class Driver;
    virtual IF_dut vif;
    event drv_done;
    mailbox drv_mbx;

    task automatic run();
        $display("T=%0t [Driver] starting ...", $time);
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
endclass //Driver

class pkt1;
    rand string mode;
    rand int num_transactions;
    rand int min_delay;
    rand int max_delay;
    rand bit enable_back_pressure;
    int fifo_depth;  
    
    string mode_list[] = {
        "WRITE_UNTIL_FULL",
        "READ_UNTIL_EMPTY", 
        "WR_AT_THE_SAME_TIME",
        "WR_RANDOM_VALUES",
        "WRITE_RANDOM",
        "READ_RANDOM"
    };
    
    // Simple constraints
    constraint c_mode {
        mode inside {mode_list};
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
    
    function void print(string tag = "pkt1");
        $display("T=%0t [%s] mode=%s, num_trans=%0d, delay=[%0d:%0d], back_pressure=%0b", 
                $time, tag, mode, num_transactions, min_delay, max_delay, enable_back_pressure);
    endfunction
endclass

class Generator;
    mailbox drv_mbx;
    event drv_done;
    pkt1 pkt_in;
    int trans_count;

    task run();
        trans_count = 0;
        $display("T=%0t [Generator] Starting with mode: %s", $time, pkt_in.mode);
        
        case (pkt_in.mode)
            "WRITE_UNTIL_FULL":     gen_write_until_full();
            "READ_UNTIL_EMPTY":     gen_read_until_empty();
            "WR_AT_THE_SAME_TIME":  gen_wr_at_the_same_time();
            "WR_RANDOM_VALUES":     gen_wr_random_order();
            "WRITE_RANDOM":         gen_write_random(); 
            "READ_RANDOM":          gen_read_random();
            default: $display("T=%0t [Generator] ERROR: Unknown mode %s", $time, pkt_in.mode);
        endcase
        
        $display("T=%0t [Generator] Completed %0d transactions", $time, trans_count);
    endtask

    // Generate continuous writes until FIFO is expected to be full
    task gen_write_until_full();
        pkt2 pkt_out;
        
        for (int i = 0; i < pkt_in.fifo_depth + 2; i++) begin  // +2 to test overflow
            pkt_out = new();
            write_once(pkt_out);
            drv_mbx.put(pkt_out);
            trans_count++;
            @drv_done;
            add_random_delay();
        end
    endtask

    // Generate continuous reads (assumes FIFO has data)
    task gen_read_until_empty();
        pkt2 pkt_out;
        
        for (int i = 0; i < pkt_in.fifo_depth + 2; i++) begin  // +2 to test underflow
            pkt_out = new();
            read_once(pkt_out);
            drv_mbx.put(pkt_out);
            trans_count++;
            @drv_done;
            add_random_delay();
        end
    endtask

    // Generate simultaneous write and read operations
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

    // Generate random sequence of writes and reads
    task gen_wr_random_order();
        pkt2 pkt_out;
        
        for (int i = 0; i < pkt_in.num_transactions; i++) begin
            pkt_out = new();
            
            // Randomly decide operation type
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

    // Generate only random write operations
    task gen_write_random();
        pkt2 pkt_out;
        
        for (int i = 0; i < pkt_in.num_transactions; i++) begin
            pkt_out = new();
            write_once(pkt_out);
            
            // Add some back pressure randomly
            if (pkt_in.enable_back_pressure && ($urandom_range(0, 9) < 3)) begin
                add_idle_cycle();
            end
            
            drv_mbx.put(pkt_out);
            trans_count++;
            @drv_done;
            add_random_delay();
        end
    endtask

    // Generate only random read operations
    task gen_read_random();
        pkt2 pkt_out;
        
        for (int i = 0; i < pkt_in.num_transactions; i++) begin
            pkt_out = new();
            read_once(pkt_out);
            
            // Add some back pressure randomly
            if (pkt_in.enable_back_pressure && ($urandom_range(0, 9) < 3)) begin
                add_idle_cycle();
            end
            
            drv_mbx.put(pkt_out);
            trans_count++;
            @drv_done;
            add_random_delay();
        end
    endtask

    // Helper task for write operations
    task write_once(pkt2 pkt_out);
        pkt_out.randomize();
        pkt_out.push = 1;
        pkt_out.pop = 0;
    endtask

    // Helper task for read operations
    task read_once(pkt2 pkt_out);
        pkt_out.randomize();
        pkt_out.push = 0;
        pkt_out.pop = 1;
    endtask
    
    // Add an idle cycle (no push or pop)
    task add_idle_cycle();
        pkt2 pkt_out = new();
        pkt_out.push = 0;
        pkt_out.pop = 0;
        pkt_out.Din = 0;
        
        drv_mbx.put(pkt_out);
        @drv_done;
    endtask
    
    // Add random delay between transactions
    task add_random_delay();
        int delay;
        delay = $urandom_range(pkt_in.min_delay, pkt_in.max_delay);
        
        for (int i = 0; i < delay; i++) begin
            add_idle_cycle();
        end
    endtask

endclass //Generator

// You'll also need to update your pkt2 class to match:

class test;
    // Environment components (would be instantiated in full testbench)
    Generator g0;
    mailbox gen_mbx;      // Generator -> Driver
    mailbox scb_mbx;      // Test -> Scoreboard  
    event gen_done;       // Driver done event
    
    function new();
        g0 = new();
        gen_mbx = new();
        scb_mbx = new();
    endfunction
    
    task run();
        $display("T=%0t [Test] Starting FIFO test", $time);
        
        // Configure and start generator
        fork
            configure_and_run_generator();
            configure_scoreboard();
        join
        
        $display("T=%0t [Test] Test completed", $time);
    endtask
    
    // Configure generator with pkt1 and start it
    task configure_and_run_generator();
        pkt1 gen_config = new();
        
        // Randomize test configuration
        if (!gen_config.randomize()) 
            $fatal("Failed to randomize generator config");
        
        gen_config.print("Test->Gen");
        
        // Connect and run generator
        g0.pkt_in = gen_config;
        g0.drv_mbx = gen_mbx;
        g0.drv_done = gen_done;
        
        $display("T=%0t [Test] Starting generator with mode: %s", $time, gen_config.mode);
        g0.run();
    endtask
    
    // Send configuration to scoreboard
    task configure_scoreboard();
        pkt3 scb_config = new();
        
        // Simple scoreboard configuration
        scb_config.report_type = "FULL";
        scb_config.enable_coverage = 1;
        scb_config.print_transactions = 1;
        
        $display("T=%0t [Test] Sending config to scoreboard", $time);
        scb_mbx.put(scb_config);
    endtask
    
endclass

// Sample testbench connection:
module tb_fifo;
    bit clk;
    
    // Clock generation
    always #5 clk = ~clk;
    
    // Interface instance
    IF_dut #(.DataWidth(32)) dut_if(clk);
    
    // DUT instance with updated port connections
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
        .rst(dut_if.rst)
    );
    
    initial begin
        // Your test here
    end
    
endmodule