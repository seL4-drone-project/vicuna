// Copyright TU Wien
// Licensed under the ISC license, see LICENSE.txt for details
// SPDX-License-Identifier: ISC


module vproc_top #(
        parameter              MAIN_CORE       = "",
        parameter int unsigned VREG_W          = 128,
        parameter int unsigned VMEM_W          = 32,
        parameter int unsigned VMUL_W          = 64,
        parameter vproc_pkg::ram_type RAM_TYPE = vproc_pkg::RAM_GENERIC,
        parameter vproc_pkg::mul_type MUL_TYPE = vproc_pkg::MUL_GENERIC,
        parameter int unsigned ICACHE_SZ       = 0,   // instruction cache size in bytes
        parameter int unsigned ICACHE_LINE_W   = 128, // instruction cache line width in bits
        parameter int unsigned DCACHE_SZ       = 0,   // data cache size in bytes
        parameter int unsigned DCACHE_LINE_W   = 512  // data cache line width in bits
    )(
        input  logic        clk_i,
        input  logic        rst_ni,

        output logic        mem_req_o,
        output logic [31:0] mem_addr_o,
        output logic        mem_we_o,
        output logic [3:0]  mem_be_o,
        output logic [31:0] mem_wdata_o,
        input  logic        mem_rvalid_i,
        input  logic        mem_err_i,
        input  logic [31:0] mem_rdata_i
    );

    // Instruction fetch interface
    logic        instr_req;
    logic [31:0] instr_addr;
    logic        instr_gnt;
    logic        instr_rvalid;
    logic        instr_err;
    logic [31:0] instr_rdata;

    // Data load & store interface
    logic        sdata_req;
    logic [31:0] sdata_addr;
    logic        sdata_we;
    logic  [3:0] sdata_be;
    logic [31:0] sdata_wdata;
    logic        sdata_gnt;
    logic        sdata_rvalid;
    logic        sdata_err;
    logic [31:0] sdata_rdata;

    // Vector Unit Interface
    logic        vect_instr_valid;
    logic [31:0] vect_instr;
    logic [31:0] vect_x_rs1;
    logic [31:0] vect_x_rs2;
    logic        vect_instr_gnt;
    logic        vect_instr_illegal;
    logic        vect_misaligned_ls;
    logic        vect_xreg_wait;
    logic        vect_xreg_valid;
    logic [31:0] vect_xreg;
    logic        vect_pending_load;
    logic        vect_pending_store;

    // CSR register interface for Vector Unit
    localparam int unsigned VectCSRs = 7;
    logic [11:0] vect_csr_addr [VectCSRs];
    logic [31:0] vect_csr_rdata[VectCSRs];
    logic        vect_csr_we   [VectCSRs];
    logic [31:0] vect_csr_wdata[VectCSRs];
    assign vect_csr_addr = '{
        12'h008, // vstart
        12'h009, // vxsat
        12'h00A, // vxrm
        12'h00F, // vcsr
        12'hC20, // vl
        12'hC21, // vtype
        12'hC22  // vlenb
    };

    ibex_top #(
        .DmHaltAddr             ( 32'h00000000                       ),
        .DmExceptionAddr        ( 32'h00000000                       ),
        .RV32M                  ( ibex_pkg::RV32MNone                ),
        .ExternalCSRs           ( VectCSRs                           ),
        // LOAD-FP, STORE-FP and VECTOR opcodes
        .CoprocOpcodes          ( 32'h00200202                       )
    ) u_core (
        .clk_i                  ( clk_i                              ),
        .rst_ni                 ( rst_ni                             ),

        .test_en_i              ( 1'b0                               ),
        .ram_cfg_i              ( prim_ram_1p_pkg::ram_1p_cfg_t'('0) ),

        .hart_id_i              ( 32'b0                              ),
        .boot_addr_i            ( 32'h00000000                       ),

        .instr_req_o            ( instr_req                          ),
        .instr_gnt_i            ( instr_gnt                          ),
        .instr_rvalid_i         ( instr_rvalid                       ),
        .instr_addr_o           ( instr_addr                         ),
        .instr_rdata_i          ( instr_rdata                        ),
        .instr_err_i            ( instr_err                          ),

        .data_req_o             ( sdata_req                          ),
        .data_gnt_i             ( sdata_gnt                          ),
        .data_rvalid_i          ( sdata_rvalid                       ),
        .data_we_o              ( sdata_we                           ),
        .data_be_o              ( sdata_be                           ),
        .data_addr_o            ( sdata_addr                         ),
        .data_wdata_o           ( sdata_wdata                        ),
        .data_rdata_i           ( sdata_rdata                        ),
        .data_err_i             ( sdata_err                          ),

        .cpi_req_o              ( vect_instr_valid                   ),
        .cpi_instr_o            ( vect_instr                         ),
        .cpi_rs1_o              ( vect_x_rs1                         ),
        .cpi_rs2_o              ( vect_x_rs2                         ),
        .cpi_gnt_i              ( vect_instr_gnt                     ),
        .cpi_instr_illegal_i    ( vect_instr_illegal                 ),
        .cpi_wait_i             ( vect_xreg_wait                     ),
        .cpi_res_valid_i        ( vect_xreg_valid                    ),
        .cpi_res_i              ( vect_xreg                          ),

        .irq_software_i         ( 1'b0                               ),
        .irq_timer_i            ( 1'b0                               ),
        .irq_external_i         ( 1'b0                               ),
        .irq_fast_i             ( 15'b0                              ),
        .irq_nm_i               ( 1'b0                               ),

        .ecsr_addr_i            ( vect_csr_addr                      ),
        .ecsr_rdata_i           ( vect_csr_rdata                     ),
        .ecsr_we_o              ( vect_csr_we                        ),
        .ecsr_wdata_o           ( vect_csr_wdata                     ),

        .debug_req_i            ( 1'b0                               ),
        .crash_dump_o           (                                    ),

        .fetch_enable_i         ( 1'b1                               ),
        .alert_minor_o          (                                    ),
        .alert_major_o          (                                    ),
        .core_sleep_o           (                                    ),

        .scan_rst_ni            ( 1'b1                               )
    );

    // Vector CSR read/write conversion
    logic [31:0] csr_vtype;
    logic [31:0] csr_vl;
    logic [31:0] csr_vlenb;
    logic [31:0] csr_vstart_rd;
    logic [31:0] csr_vstart_wr;
    logic        csr_vstart_wren;
    logic        csr_vxsat_rd;
    logic        csr_vxsat_wr;
    logic        csr_vxsat_wren;
    logic [1:0]  csr_vxrm_rd;
    logic [1:0]  csr_vxrm_wr;
    logic        csr_vxrm_wren;
    assign vect_csr_rdata[0] = csr_vstart_rd;
    assign vect_csr_rdata[1] = {31'b0, csr_vxsat_rd};
    assign vect_csr_rdata[2] = {30'b0, csr_vxrm_rd};
    assign vect_csr_rdata[3] = {29'b0, csr_vxrm_rd, csr_vxsat_rd};
    assign vect_csr_rdata[4] = csr_vl;
    assign vect_csr_rdata[5] = csr_vtype;
    assign vect_csr_rdata[6] = VREG_W / 8;
    assign csr_vstart_wr     = vect_csr_wdata[0];
    assign csr_vstart_wren   = vect_csr_we[0];
    assign csr_vxsat_wr      = vect_csr_we[1] ? vect_csr_wdata[1][0]   : vect_csr_wdata[3][0];
    assign csr_vxsat_wren    = vect_csr_we[1] | vect_csr_we[3];
    assign csr_vxrm_wr       = vect_csr_we[2] ? vect_csr_wdata[2][1:0] : vect_csr_wdata[3][2:1];
    assign csr_vxrm_wren     = vect_csr_we[2] | vect_csr_we[3];

    // Data read/write for Vector Unit
    logic                vdata_gnt;
    logic                vdata_rvalid;
    logic                vdata_err;
    logic [VMEM_W-1:0]   vdata_rdata;
    logic                vdata_req;
    logic [31:0]         vdata_addr;
    logic                vdata_we;
    logic [VMEM_W/8-1:0] vdata_be;
    logic [VMEM_W-1:0]   vdata_wdata;

    vproc_core #(
        .VREG_W           (  VREG_W                     ),
        .VMEM_W           (  VMEM_W                     ),
        .MUL_OP_W         (  VMUL_W                     ),
        .ALU_OP_W         (  64                         ),
        .SLD_OP_W         ( (VMUL_W > 64) ? VMUL_W : 64 ),
        .RAM_TYPE         ( RAM_TYPE                    ),
        .MUL_TYPE         ( MUL_TYPE                    )
    ) v_core (
        .clk_i            ( clk_i              ),
        .rst_ni           ( rst_ni             ),

        .instr_valid_i    ( vect_instr_valid   ),
        .instr_i          ( vect_instr         ),
        .x_rs1_i          ( vect_x_rs1         ),
        .x_rs2_i          ( vect_x_rs2         ),
        .instr_gnt_o      ( vect_instr_gnt     ),
        .instr_illegal_o  ( vect_instr_illegal ),
        .misaligned_ls_o  ( vect_misaligned_ls ),
        .xreg_wait_o      ( vect_xreg_wait     ),
        .xreg_valid_o     ( vect_xreg_valid    ),
        .xreg_o           ( vect_xreg          ),

        .pending_load_o   ( vect_pending_load  ),
        .pending_store_o  ( vect_pending_store ),

        .csr_vtype_o      ( csr_vtype          ),
        .csr_vl_o         ( csr_vl             ),
        .csr_vlenb_o      ( csr_vlenb          ),
        .csr_vstart_o     ( csr_vstart_rd      ),
        .csr_vstart_i     ( csr_vstart_wr      ),
        .csr_vstart_set_i ( csr_vstart_wren    ),
        .csr_vxrm_o       ( csr_vxrm_rd        ),
        .csr_vxrm_i       ( csr_vxrm_wr        ),
        .csr_vxrm_set_i   ( csr_vxrm_wren      ),
        .csr_vxsat_o      ( csr_vxsat_rd       ),
        .csr_vxsat_i      ( csr_vxsat_wr       ),
        .csr_vxsat_set_i  ( csr_vxsat_wren     ),

        .data_req_o       ( vdata_req          ),
        .data_gnt_i       ( vdata_gnt          ),
        .data_rvalid_i    ( vdata_rvalid       ),
        .data_err_i       ( vdata_err          ),
        .data_rdata_i     ( vdata_rdata        ),
        .data_addr_o      ( vdata_addr         ),
        .data_we_o        ( vdata_we           ),
        .data_be_o        ( vdata_be           ),
        .data_wdata_o     ( vdata_wdata        )
    );

    // Data arbiter for main core and vector unit
    logic              sdata_hold;
    logic              data_req;
    logic [31:0]       data_addr;
    logic              data_we;
    logic [VMEM_W/8:0] data_be;
    logic [VMEM_W  :0] data_wdata;
    logic              data_gnt;
    logic              data_rvalid;
    logic              data_err;
    logic [VMEM_W  :0] data_rdata;
    logic              sdata_waiting, vdata_waiting;
    logic [31:0]       sdata_wait_addr;
    assign sdata_hold = vdata_req | vect_pending_store | (vect_pending_load & sdata_we);
    always_comb begin
        data_req   = vdata_req | (sdata_req & ~sdata_hold);
        data_addr  = sdata_addr;
        data_we    = sdata_we;
        data_be    = {{(VMEM_W-32){1'b0}}, sdata_be} << (sdata_addr[$clog2(VMEM_W/8)-1:0] & {{$clog2(VMEM_W/32){1'b1}}, 2'b00});
        data_wdata = '0;
        for (int i = 0; i < VMEM_W / 32; i++) begin
            data_wdata[32*i +: 32] = sdata_wdata;
        end
        if (vdata_req) begin
            data_addr  = vdata_addr;
            data_we    = vdata_we;
            data_be    = vdata_be;
            data_wdata = vdata_wdata;
        end
    end
    assign sdata_gnt = data_gnt & sdata_req & ~sdata_hold;
    assign vdata_gnt = data_gnt & vdata_req;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (~rst_ni) begin
            sdata_waiting   <= 1'b0;
            vdata_waiting   <= 1'b0;
            sdata_wait_addr <= '0;
        end else begin
            if (sdata_gnt) begin
                sdata_waiting   <= 1'b1;
                sdata_wait_addr <= sdata_addr;
            end
            else if (sdata_rvalid) begin
                sdata_waiting <= 1'b0;
            end
            if (vdata_gnt) begin
                vdata_waiting <= ~vdata_we; // vector processor expects rvalid only for reads
            end
            else if (vdata_rvalid) begin
                vdata_waiting <= 1'b0;
            end
        end
    end
    assign sdata_rvalid = sdata_waiting & data_rvalid;
    assign vdata_rvalid = vdata_waiting & data_rvalid;
    assign sdata_err    = data_err;
    assign vdata_err    = data_err;
    assign sdata_rdata  = data_rdata[(sdata_wait_addr[$clog2(VMEM_W/8)-1:0] & {{$clog2(VMEM_W/32){1'b1}}, 2'b00})*8 +: 32];
    assign vdata_rdata  = data_rdata;


    ///////////////////////////////////////////////////////////////////////////
    // Caches

    // instruction cache
    logic        imem_req;
    logic        imem_gnt;
    logic [31:0] imem_addr;
    logic        imem_rvalid;
    logic [31:0] imem_rdata;
    logic        imem_err;
    generate
        if (ICACHE_SZ != 0) begin
            localparam ICACHE_WAY_LEN = ICACHE_SZ / (ICACHE_LINE_W / 8) / 2;
            vproc_cache #(
                .ADDR_BIT_W   ( 32                ),
                .CPU_BYTE_W   ( 4                 ),
                .MEM_BYTE_W   ( 4                 ),
                .LINE_BYTE_W  ( ICACHE_LINE_W / 8 ),
                .WAY_LEN      ( ICACHE_WAY_LEN    )
            ) icache (
                .clk_i        ( clk_i             ),
                .rst_ni       ( rst_ni            ),
                .hold_mem_i   ( 1'b0              ),
                .cpu_req_i    ( instr_req         ),
                .cpu_addr_i   ( instr_addr        ),
                .cpu_we_i     ( '0                ),
                .cpu_be_i     ( '0                ),
                .cpu_wdata_i  ( '0                ),
                .cpu_gnt_o    ( instr_gnt         ),
                .cpu_rvalid_o ( instr_rvalid      ),
                .cpu_rdata_o  ( instr_rdata       ),
                .cpu_err_o    ( instr_err         ),
                .mem_req_o    ( imem_req          ),
                .mem_addr_o   ( imem_addr         ),
                .mem_we_o     (                   ),
                .mem_wdata_o  (                   ),
                .mem_gnt_i    ( imem_gnt          ),
                .mem_rvalid_i ( imem_rvalid       ),
                .mem_rdata_i  ( imem_rdata        ),
                .mem_err_i    ( imem_err          )
            );
        end else begin
            assign imem_req     = instr_req;
            assign imem_addr    = instr_addr;
            assign instr_gnt    = imem_gnt;
            assign instr_rvalid = imem_rvalid;
            assign instr_rdata  = imem_rdata;
            assign instr_err    = imem_err;
        end
    endgenerate

    // data cache
    logic        dmem_req;
    logic        dmem_gnt;
    logic [31:0] dmem_addr;
    logic        dmem_we;
    logic [4:0]  dmem_be;
    logic [31:0] dmem_wdata;
    logic        dmem_rvalid;
    logic [31:0] dmem_rdata;
    logic        dmem_err;
    generate
        if (DCACHE_SZ != 0) begin
            localparam DCACHE_WAY_LEN = DCACHE_SZ / (DCACHE_LINE_W / 8) / 2;
            // hold memory access (allows lookup only) for main core requests
            // in case of pending vector loads / stores
            logic hold_mem;
            always_ff @(posedge clk_i) begin
                hold_mem <= ~vdata_req & vect_pending_store & vect_pending_load;
            end
            vproc_cache #(
                .ADDR_BIT_W   ( 32                ),
                .CPU_BYTE_W   ( VMEM_W / 8        ),
                .MEM_BYTE_W   ( 4                 ),
                .LINE_BYTE_W  ( DCACHE_LINE_W / 8 ),
                .WAY_LEN      ( DCACHE_WAY_LEN    )
            ) vcache (
                .clk_i        ( clk_i             ),
                .rst_ni       ( rst_ni            ),
                .hold_mem_i   ( hold_mem          ),
                .cpu_req_i    ( data_req          ),
                .cpu_addr_i   ( data_addr         ),
                .cpu_we_i     ( data_we           ),
                .cpu_be_i     ( data_be           ),
                .cpu_wdata_i  ( data_wdata        ),
                .cpu_gnt_o    ( data_gnt          ),
                .cpu_rvalid_o ( data_rvalid       ),
                .cpu_rdata_o  ( data_rdata        ),
                .cpu_err_o    ( data_err          ),
                .mem_req_o    ( dmem_req          ),
                .mem_we_o     ( dmem_we           ),
                .mem_addr_o   ( dmem_addr         ),
                .mem_wdata_o  ( dmem_wdata        ),
                .mem_gnt_i    ( dmem_gnt          ),
                .mem_rvalid_i ( dmem_rvalid       ),
                .mem_rdata_i  ( dmem_rdata        ),
                .mem_err_i    ( dmem_err          )
            );
            assign dmem_be = '1;
        end else begin
            assign dmem_req    = data_req;
            assign dmem_addr   = data_addr;
            assign dmem_we     = data_we;
            assign dmem_be     = data_be;
            assign dmem_wdata  = data_wdata;
            assign data_gnt    = dmem_gnt;
            assign data_rvalid = dmem_rvalid;
            assign data_rdata  = dmem_rdata;
            assign data_err    = dmem_err;
        end
    endgenerate



    ///////////////////////////////////////////////////////////////////////////
    // Memory arbiter

    always_comb begin
        mem_req_o   = imem_req | dmem_req;
        mem_addr_o  = imem_addr;
        mem_we_o    = 1'b0;
        mem_be_o    = dmem_be;
        mem_wdata_o = dmem_wdata;
        if (dmem_req) begin
            mem_we_o   = dmem_we;
            mem_addr_o = dmem_addr;
        end
    end
    assign imem_gnt = imem_req & ~dmem_req;
    assign dmem_gnt =             dmem_req;

    // shift register keeping track of the source of mem requests for up to 32 cycles
    logic [31:0] req_sources;
    logic [4:0]  req_count;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (~rst_ni) begin
            req_count <= '0;
        end else begin
            if (mem_rvalid_i) begin
                req_sources[30:0] <= req_sources[31:1];
                if (~imem_gnt & ~dmem_gnt) begin
                    req_count <= req_count - 1;
                end else begin
                    req_sources[req_count-1] <= dmem_gnt;
                end
            end
            else if (imem_gnt | dmem_gnt) begin
                req_sources[req_count] <= dmem_gnt;
                req_count              <= req_count + 1;
            end
        end
    end
    assign imem_rvalid = mem_rvalid_i & ~req_sources[0];
    assign dmem_rvalid = mem_rvalid_i &  req_sources[0];
    assign imem_err    = mem_err_i;
    assign dmem_err    = mem_err_i;
    assign imem_rdata  = mem_rdata_i;
    assign dmem_rdata  = mem_rdata_i;

endmodule