interface IF_dut #(parameter DataWidth = 32) (input bit clk);
    logic                 writeEn;
    logic [DataWidth-1:0] writeData;
    logic                 readEn;
    logic [DataWidth-1:0] readData;
    logic                 pndng;
    logic                 full;
endinterface //IF_dut    
    