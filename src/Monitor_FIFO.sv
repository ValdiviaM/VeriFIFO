class monitor;
  virtual IF_dut vif;    // usa la misma interfaz del resto
  mailbox scb_mbx;
  semaphore sema1;

  function new(virtual IF_dut vif_i=null, mailbox mbx_i=null);
    vif = vif_i; scb_mbx = mbx_i; sema1 = new(1);
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
        // t: entradas
        item.Din  = vif.Din;
        item.push = vif.push;
        item.pop  = vif.pop;

        @(posedge vif.clk);
        sema1.put();
        // t+1: salidas
        item.full  = vif.full;
        item.pndng = vif.pndng;
        item.Dout  = vif.Dout;

        scb_mbx.put(item);
        item.print({"monitor ", tag});
      end
    end
  endtask
endclass
