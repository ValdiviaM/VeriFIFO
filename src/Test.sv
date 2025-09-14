class test;
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