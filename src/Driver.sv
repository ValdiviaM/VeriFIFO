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