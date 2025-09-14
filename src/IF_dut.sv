interface IF_dut #(parameter DataWidth = 32) (input bit clk);
    logic                 push;     
    logic [DataWidth-1:0] Din;       
    logic                 pop;       
    logic [DataWidth-1:0] Dout;     
    logic                 pndng;     
    logic                 full;      
    logic                 rst;       
endinterface //IF_dut   
    