class pkt3;
  bit reporte_completo;

  function new(bit rc = 1);
    reporte_completo = rc; 
  endfunction

  function void print(string tag="pkt3");
    $display("[%s] reporte_completo=%0b", tag, reporte_completo);
  endfunction
endclass
