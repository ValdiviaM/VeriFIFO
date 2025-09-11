class Generator;
    mailbox drv_mbx;
    event drv_done;
    pkt1 pkt_in;

    task run();
        case (pkt_in.mode)
            "WRITE_UNTIL_FULL":     gen_write_until_full();
            "READ_UNTIL_EMPTY":     gen_read_until_empty();
            "WR_AT_THE_SAME_TIME":  gen_wr_at_the_same_time();
            "WR_RANDOM_VALUES":      gen_wr_random_order();
            "WRITE_RANDOM":         gen_write_random(); 
            "READ_RANDOM":          gen_read_random();
        endcase
    endtask

    task write_once(pkt2 pkt_out);
        pkt_out.randomize();
        pkt_out.writeEn=1;
        pkt_out.readEn=0;
    endtask //automatic

    task automatic read_once(pkt_out);
        pkt_out.randomize();
        pkt_out.writeEn=0;
        pkt_out.readEn=1;
    endtask //automatic

endclass //Generator 