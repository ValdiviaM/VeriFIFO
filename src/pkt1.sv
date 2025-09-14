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