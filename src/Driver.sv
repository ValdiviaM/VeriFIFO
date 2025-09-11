`include "./src/IF_dut.sv"

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

            vif.writeEn <= pkt.writeEn;
            vif.writeData <= pkt.writeData;
            vif.readEn <= pkt.readEn;

            @(posedge vif.clk);

            vif.writeData <= 0;
            vif.writeEn <= 0;
            vif.readEn <= 0;

            ->drv_done;  
        end
    endtask
endclass //Driver