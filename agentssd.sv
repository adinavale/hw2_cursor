// Provides the sequence, sequencer and driver for a test

`include "seqr1.sv"
`include "drv2.sv"

class agentssd extends uvm_agent;
`uvm_component_utils(agentssd)
    seqr1 sqr1;
    drv2 d2;
    CLKMON cm1;
    WDT wdt1;

    function new(string name,uvm_component par=null);
        super.new(name,par);
    endfunction : new

    function void build_phase(uvm_phase phase);
        d2=drv2::type_id::create("d2",this);
        sqr1=seqr1::type_id::create("seqr1",this);
        cm1=CLKMON::type_id::create("clkmon1",this);
        wdt1=WDT::type_id::create("wdt1",this);
    endfunction : build_phase

    function void connect_phase(uvm_phase phase);
        d2.seq_item_port.connect(sqr1.seq_item_export);
        d2.wdt.connect(wdt1.wtmsg);
        cm1.clkevent.connect(wdt1.clkevent.analysis_export);
    endfunction : connect_phase


endclass : agentssd
