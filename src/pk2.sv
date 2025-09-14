class pkt2 #(parameter bits =32);
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