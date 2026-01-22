`timescale 1ns / 1ps


class transaction;
  
  bit newd; 
  bit busy;
  bit ack_err;
  bit done;
  
  rand  bit op;
  rand bit [6:0] addr;
  rand bit [7:0] din; 
  
  bit [7:0] dout;
    
 
  
  function transaction copy();
    
    copy = new();   
    copy.newd = this.newd;
    copy.busy = this.busy;
    copy.ack_err = this.ack_err;
    copy.done = this.done;
    copy.op = this.op;
    copy.din = this.din;
    copy.addr = this.addr;  
    copy.dout = this.dout;
    
  endfunction
  
    constraint op_c {
    op dist {1 :/ 50 ,  0 :/ 50};
  }
  
  
  function void display(input string tag);
    
    $display("[%0t] [%s] \t | OP = %0d | ADDR: %0d \t | DIN: %0d | DOUT = %0d", $time, tag, op, addr, din, dout);
    
  endfunction
  
endclass



class generator;
  
  transaction tr;  
  
  mailbox #(transaction) mbx;    
  mailbox #(transaction) mbxref;
  
  event drvnext;
  event sconext;
  event done;
  
  int count = 0; 
  
 
  function new(mailbox #(transaction) mbx, mailbox #(transaction) mbxref);
    
    this.mbx = mbx;  
    this.mbxref = mbxref; 
    tr = new(); 
    
  endfunction
  
  task run();
    
    repeat(count) begin
      assert(tr.randomize()) else $error("[GEN] : RANDOMIZATION FAILED");
      mbx.put(tr.copy()); 
      mbxref.put(tr.copy());
      tr.display("GEN"); 
      @(drvnext); //BC GG SAID NO PREVIOUSLY
      @(sconext); 
      
    end
    
    ->done; 
    
  endtask
  
endclass







class driver;
  
  transaction tr; 
  mailbox #(transaction) mbx; 
  virtual i2c_if vif; 
  event drvnext; 
  
  bit [7:0] din;
  
  function new(mailbox #(transaction) mbx);
    
    this.mbx = mbx; 
    
  endfunction
  
  task reset();
    
    vif.rst <= 1'b1;
    vif.op <= 1'b0;
    vif.newd <= 1'b0;
    vif.addr <= 1'b1; 
    vif.din <= 1'b0;
    
    repeat(200) @(posedge vif.clk); 
    vif.rst <= 1'b0; 
    
    repeat(5)@(posedge vif.clk); 
    $display("[DRV] : RESET DONE"); 
    
  endtask
  
  task write();
    
    vif.rst <= 1'b0;
    vif.op <= 1'b0;
    vif.newd <= 1'b1;
    vif.addr <= tr.addr; 
    vif.din <= tr.din;    
    
    repeat(5) @(posedge vif.clk)
    vif.newd <= 1'b0;
    
    @(posedge vif.done)
    tr.display("DRV");
    vif.newd <= 1'b0;
    
    
  endtask 
  
  
  task read();
    vif.rst <= 1'b0;
    vif.op <= 1'b1;
    vif.newd <= 1'b1;
    vif.addr <= tr.addr; 
    vif.din <= 0; 
    
    repeat(5) @(posedge vif.clk)
    vif.newd <= 1'b0;
    
    @(posedge vif.done)
    tr.display("DRV");    
      
  endtask 
  
  
  
  task run();
    
    forever begin
      
      tr = new(); 
      
      mbx.get(tr);
      
      if(tr.op == 1'b0)
        begin 
          write();
        end   
      else
        begin 
          read();
        end 
      
      ->drvnext;
      
    end
    
  endtask
  
endclass




class monitor;
  
  transaction tr; 
  mailbox #(transaction) mbx; 
  virtual i2c_if vif; 
  
  function new(mailbox #(transaction) mbx);
    
    this.mbx = mbx; 
    
  endfunction
  
  task run();
    
    forever begin
      
      tr = new();
      @(posedge vif.done); 
      tr.op   = vif.op;
      tr.addr = vif.addr; 
      tr.din = vif.din;   
      tr.dout = vif.dout;
      
      
      
      repeat(5) @(posedge vif.clk);
      mbx.put(tr); 
      
      tr.display("MON"); 
      
    end
    
  endtask
  
endclass







class scoreboard;

  transaction tr;
  transaction trref;
  mailbox #(transaction) mbx;    
  mailbox #(transaction) mbxref;  
  event sconext;

  
  bit [7:0] sc_mem [128]; 
  
  
  bit [7:0] expected_data;

  function new(mailbox #(transaction) mbx, mailbox #(transaction) mbxref);
    this.mbx = mbx;  
    this.mbxref = mbxref; 
    
    
    for(int i = 0; i < 128; i++) begin
      sc_mem[i] = i;
    end
  endfunction  
  
  task run();
    forever begin 
      
      mbx.get(tr);    
      mbxref.get(trref);
      
      tr.display("SCO");
      trref.display("REF");



      // CASE 1: WRITE OPERATION (op == 0)
      if (trref.op == 1'b0) begin
        // Update Shadow Memory
        sc_mem[trref.addr] = trref.din;
        $display("[SCO] : DATA WRITE UPDATE | Addr: %0d | Data: %0d", trref.addr, trref.din);
        
        // Optional: Check if the Write failed (ack_err)
        if (tr.ack_err) 
          $display("[SCO] : ERROR! Write Acknowledge Error Received");
        else
          $display("[SCO] : Write Successful");
      end
      
      // CASE 2: READ OPERATION (op == 1)
      else begin
        // Fetch what we expect from our Shadow Memory
        expected_data = sc_mem[trref.addr];
        
        // Compare Expected (Shadow Mem) vs Actual (Monitor/DUT)
        if (tr.dout == expected_data) begin
          $display("[SCO] : DATA MATCHED   | Addr: %0d | Expected: %0d | Actual: %0d", trref.addr, expected_data, tr.dout);
        end
        else begin
          $display("[SCO] : DATA MISMATCH! | Addr: %0d | Expected: %0d | Actual: %0d", trref.addr, expected_data, tr.dout);
          $error("[SCO] : TEST FAILED");
        end
      end

      $display("--------------------------------------------------");
      ->sconext;
    end 
  endtask 

endclass


 
  
  
class environment;

  generator gen;
  driver drv;
  monitor mon;
  scoreboard sco;
  
  event nextgd;
  event nextgs;
  
  virtual i2c_if vif;
  
  mailbox #(transaction) gdmbx;
  mailbox #(transaction) msmbx;
  mailbox #(transaction) mbxref;
  
  
  function new(virtual i2c_if vif);
    
    gdmbx = new();
    msmbx = new();
    mbxref = new();
    
    gen = new(gdmbx, mbxref);
    drv = new(gdmbx);
    mon = new(msmbx);
    sco = new(msmbx, mbxref);

    this.vif = vif;
    
    drv.vif = this.vif;
    mon.vif = this.vif;
    
    gen.drvnext = nextgd;
    drv.drvnext = nextgd;
    
    gen.sconext = nextgs;
    sco.sconext = nextgs;
    
  endfunction 
  
  task pre_test();
    
    drv.reset();
    
  endtask 
  
  task test();
    
    fork 
      gen.run();
      drv.run();
      mon.run();
      sco.run();
    join_none 
    
  endtask 
  
task post_test();
   wait(gen.done.triggered);
   
  // repeat(20) @(posedge vif.clk); 
   
   $finish();
endtask
  
  task run();
    
    pre_test();
    test();
    post_test();
    
  endtask 
  
endclass
 






module tb();
  
environment env;
i2c_if vif();
  
  top dut(vif.clk, vif.rst, vif.newd, vif.op, vif.addr,vif.din, vif.dout, vif.busy, vif.ack_err, vif.done);
  
  
  initial begin 
    
    vif.clk = 0;
    
  end 
  
  always #10 vif.clk <= ~vif.clk;
  
  initial begin 
    
    env = new(vif);
    env.gen.count = 4;
    env.run();
    
  end 
  
  
  initial begin 
    
    $dumpfile("dump.vcd");
    $dumpvars;
    
  end 
  
endmodule 











