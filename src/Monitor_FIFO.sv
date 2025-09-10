class monitor;
  virtual FF_if vif;
  mailbox scb_mbx;
  semaphore sema1;
  
  function new();
    sema1 = new(1);
  endfunction
  
  task run();
    fork
      sample_port("Thread0");
      sample_port("Thread1");
    join
    
  endtask
  
  task sample_port(string tag="");
    forever begin
      @(posedge vif.clk);
      if(!vif.rst) begin
        pkt2 item = new;
        sema1.get();
        item.Din = vif.Din;
        item.push = vif.push;
        item.pop = vif.pop;
        
        @(posedge vif.clk);
        sema1.put();
        item.full = vif.full;
        item.pndng = vif.pndng;
        item.Dout = vif.Dout;
        
        scb_mbx.put(item);
      end
    end
  endtask
endclass