// Copyright TU Wien
// Licensed under the ISC license, see LICENSE.txt for details
// SPDX-License-Identifier: ISC


module vproc_decoder #(
        parameter bit                   DONT_CARE_ZERO = 1'b0 // initialize don't care values to zero
    )(
        input  logic                    instr_valid_i,
        input  logic [31:0]             instr_i,

        input  logic [31:0]             x_rs1_i,
        input  logic [31:0]             x_rs2_i,

        input  vproc_pkg::cfg_vsew      vsew_i,       // current SEW (single element width)
        input  vproc_pkg::cfg_lmul      lmul_i,       // current register size multiplier
        input  vproc_pkg::cfg_vxrm      vxrm_i,       // current rounding mode

        output logic                    illegal_o,    // 1 if instr_i is illegal, 0 otherwise
        output logic                    valid_o,

        output vproc_pkg::op_unit       unit_o,       //
        output vproc_pkg::op_mode       mode_o,
        output vproc_pkg::op_widenarrow widenarrow_o,

        output vproc_pkg::op_regs       rs1_o,        // source register rs1/vs1
        output vproc_pkg::op_regs       rs2_o,        // source register rs2/vs2
        output vproc_pkg::op_regd       rd_o          // destination register rd/vd
    );

    import vproc_pkg::*;

    logic [4:0] instr_vs1;
    logic [4:0] instr_vs2;
    logic [4:0] instr_vd;
    assign instr_vs1 = instr_i[19:15]; // & vreg_mul_mask;
    assign instr_vs2 = instr_i[24:20]; // & vreg_mul_mask;
    assign instr_vd  = instr_i[11:7];  // & vreg_mul_mask;

    //op_widening_narrowing widenarrow;

    logic instr_masked;
    assign instr_masked = ~instr_i[25];

    logic instr_illegal;

    always_comb begin
        instr_illegal = 1'b0;

        unit_o        = DONT_CARE_ZERO ? op_unit'('0) : op_unit'('x);
        mode_o.unused = DONT_CARE_ZERO ? '0 : 'x;

        rs1_o.vreg    = DONT_CARE_ZERO ? 1'b0 : 1'bx;
        rs1_o.r.xval  = DONT_CARE_ZERO ? '0 : 'x;
        rs1_o.r.vaddr = DONT_CARE_ZERO ? '0 : 'x;

        rs2_o.vreg    = DONT_CARE_ZERO ? 1'b0 : 1'bx;
        rs2_o.r.xval  = DONT_CARE_ZERO ? '0 : 'x;
        rs2_o.r.vaddr = DONT_CARE_ZERO ? '0 : 'x;

        rd_o.vreg     = DONT_CARE_ZERO ? 1'b0 : 1'bx;
        rd_o.addr     = instr_vd;

        widenarrow_o  = OP_SINGLEWIDTH;

        unique case (instr_i[6:0])

            // OPCODE LOAD-FP:
            7'h07: begin
                unit_o            = UNIT_LSU;
                mode_o.lsu.store  = 1'b0;
                mode_o.lsu.masked = instr_masked;

                rs1_o.vreg    = 1'b0; // rs1 is an x register
                rs1_o.r.xval  = x_rs1_i;

                rd_o.vreg = 1'b1; // rd is a v register
                rd_o.addr = instr_vd;

                if (instr_i[31:29] != 3'b000) begin
                    instr_illegal = 1'b1; // Zvlsseg is not supported
                end

                unique case (instr_i[28:26])
                    3'b000: begin // zero-ext unit-stride load
                        mode_o.lsu.stride = LSU_UNITSTRIDE;
                        mode_o.lsu.sigext = 1'b0;
                        rs2_o.vreg        = 1'b0;
                    end
                    3'b010: begin // zero-ext strided load
                        mode_o.lsu.stride = LSU_STRIDED;
                        mode_o.lsu.sigext = 1'b0;
                        rs2_o.vreg        = 1'b0;
                        rs2_o.r.xval      = x_rs2_i;
                    end
                    3'b011: begin // zero-ext indexed load
                        mode_o.lsu.stride = LSU_INDEXED;
                        mode_o.lsu.sigext = 1'b0;
                        rs2_o.vreg        = 1'b1;
                        rs2_o.r.vaddr     = instr_vs2;
                    end
                    3'b100: begin // sign-ext unit-stride load
                        mode_o.lsu.stride = LSU_UNITSTRIDE;
                        mode_o.lsu.sigext = 1'b1;
                    end
                    3'b110: begin // sign-ext strided load
                        mode_o.lsu.stride = LSU_STRIDED;
                        mode_o.lsu.sigext = 1'b1;
                        rs2_o.vreg        = 1'b0;
                        rs2_o.r.xval      = x_rs2_i;
                    end
                    3'b111: begin // sign-ext indexed load
                        mode_o.lsu.stride = LSU_INDEXED;
                        mode_o.lsu.sigext = 1'b1;
                        rs2_o.vreg        = 1'b1;
                        rs2_o.r.vaddr     = instr_vs2;
                    end
                    default: ;
                endcase

                unique case (instr_i[14:12])
                    3'b000: begin
                        mode_o.lsu.eew = VSEW_8;
                    end
                    3'b101: begin
                        mode_o.lsu.eew = VSEW_16;
                    end
                    3'b110: begin
                        mode_o.lsu.eew = VSEW_32;
                    end
                    default: begin
                        instr_illegal = 1'b1;
                    end
                endcase
            end

            // OPCODE STORE-FP:
            7'h27: begin
                unit_o            = UNIT_LSU;
                mode_o.lsu.store  = 1'b1;
                mode_o.lsu.masked = instr_masked;

                rs1_o.vreg    = 1'b0; // rs1 is an x register
                rs1_o.r.xval  = x_rs1_i;

                rd_o.vreg = 1'b1; // rd (rs3) is a v register
                rd_o.addr = instr_vd;

                if (instr_i[31:29] != 3'b000) begin
                    instr_illegal = 1'b1; // Zvlsseg is not supported
                end

                unique case (instr_i[28:26])
                    3'b000: begin // unit-stride store
                        mode_o.lsu.stride = LSU_UNITSTRIDE;
                        mode_o.lsu.sigext = 1'b0;
                        rs2_o.vreg        = 1'b0;
                    end
                    3'b010: begin // strided store
                        mode_o.lsu.stride = LSU_STRIDED;
                        mode_o.lsu.sigext = 1'b0;
                        rs2_o.vreg        = 1'b0;
                        rs2_o.r.xval      = x_rs2_i;
                    end
                    3'b011: begin // indexed-ordered store
                        mode_o.lsu.stride = LSU_INDEXED;
                        mode_o.lsu.sigext = 1'b0;
                        rs2_o.vreg        = 1'b1;
                        rs2_o.r.vaddr     = instr_vs2;
                    end
                    3'b111: begin // indexed-unordered store
                        mode_o.lsu.stride = LSU_INDEXED;
                        mode_o.lsu.sigext = 1'b0;
                        rs2_o.vreg        = 1'b1;
                        rs2_o.r.vaddr     = instr_vs2;
                    end
                    default: ;
                endcase

                unique case (instr_i[14:12])
                    3'b000: begin
                        mode_o.lsu.eew = VSEW_8;
                    end
                    3'b101: begin
                        mode_o.lsu.eew = VSEW_16;
                    end
                    3'b110: begin
                        mode_o.lsu.eew = VSEW_32;
                    end
                    default: begin
                        instr_illegal = 1'b1;
                    end
                endcase
            end

            // OPCODE VECTOR:
            7'h57: begin

                // destination register is a vreg for most instructions:
                rd_o.vreg = 1'b1;
                rd_o.addr = instr_vd;

                // select source operands:
                unique case (instr_i[14:12])
                    3'b000,         // OPIVV
                    3'b001,         // OPFVV
                    3'b010: begin   // OPMVV
                        rs1_o.vreg    = 1'b1; // rs1 is a vector register
                        rs1_o.r.vaddr = instr_vs1;
                        rs2_o.vreg    = 1'b1; // rs2 is a vector register
                        rs2_o.r.vaddr = instr_vs2;
                    end
                    3'b011: begin   // OPIVI
                        rs1_o.vreg    = 1'b0; // rs1 field contains immediate (sign extend for all except slide instructions)
                        rs1_o.r.xval  = ((instr_i[31:26] == 6'b001110) | (instr_i[31:26] == 6'b001111)) ? {{27{1'b0}}, instr_vs1} : {{27{instr_vs1[4]}}, instr_vs1};
                        rs2_o.vreg    = 1'b1; // rs2 is a vector register
                        rs2_o.r.vaddr = instr_vs2;
                    end
                    3'b100,         // OPIVX
                    3'b110: begin   // OPMVX
                        rs1_o.vreg    = 1'b0; // rs1 is an x register
                        rs1_o.r.xval  = x_rs1_i;
                        rs2_o.vreg    = 1'b1; // rs2 is a vector register
                        rs2_o.r.vaddr = instr_vs2;
                    end
                    3'b111: begin   // OPCFG
                        rs1_o.vreg    = 1'b0; // rs1 is either x reg or immediate
                        rs1_o.r.xval  = (instr_i[31:30] != 2'b11) ? x_rs1_i : {{27{1'b0}}, instr_vs1};
                        rs2_o.vreg    = 1'b0; // rs2 is either x reg or immediate
                        rs2_o.r.xval  = (instr_i[31:30] == 2'b10) ? x_rs2_i : {{21{1'b0}}, instr_i[30] & ~instr_i[31], instr_i[29:20]};
                    end
                    default: ;
                endcase

                // configuration instructions:
                if (instr_i[14:12] == 3'b111) begin
                    unit_o = UNIT_CFG;
                    unique case (rs2_o.r.xval[5:3])
                        3'b000:  mode_o.cfg.vsew = VSEW_8;
                        3'b001:  mode_o.cfg.vsew = VSEW_16;
                        3'b010:  mode_o.cfg.vsew = VSEW_32;
                        default: mode_o.cfg.vsew = VSEW_INVALID;
                    endcase
                    if (rs2_o.r.xval[31:8] != '0) begin
                        mode_o.cfg.vsew = VSEW_INVALID;
                    end
                    mode_o.cfg.lmul     = cfg_lmul'(rs2_o.r.xval[2:0]);
                    mode_o.cfg.agnostic = rs2_o.r.xval[7:6];
                    mode_o.cfg.vlmax    = 1'b0;
                    mode_o.cfg.keep_vl  = 1'b0;
                    if (instr_vs1 == '0) begin
                        mode_o.cfg.vlmax   = instr_vd != '0; // set vl to VLMAX if rs1 is x0
                        mode_o.cfg.keep_vl = instr_vd == '0; // keep vl if rs1 and rd are x0
                    end
                    rd_o.vreg = 1'b0; // rd is an x register
                end

                // arithmetic instructions:
                else begin
                    unique case ({instr_i[31:26], instr_i[14:12]})

                        // ALU:
                        {6'b000000, 3'b000},        // vadd VV
                        {6'b000000, 3'b011},        // vadd VI
                        {6'b000000, 3'b100}: begin  // vadd VX
                            unit_o              = UNIT_ALU;
                            mode_o.alu.opx2.res = ALU_VADD;
                            mode_o.alu.opx1.sel = ALU_SEL_MASK;
                            mode_o.alu.inv_op1  = 1'b0;
                            mode_o.alu.inv_op2  = 1'b0;
                            mode_o.alu.op_mask  = ALU_MASK_NONE;
                            mode_o.alu.cmp      = 1'b0;
                            mode_o.alu.masked   = instr_masked;
                        end
                        {6'b000010, 3'b000},        // vsub VV
                        {6'b000010, 3'b100}: begin  // vsub VX
                            unit_o              = UNIT_ALU;
                            mode_o.alu.opx2.res = ALU_VADD;
                            mode_o.alu.opx1.sel = ALU_SEL_MASK;
                            mode_o.alu.inv_op1  = 1'b1;
                            mode_o.alu.inv_op2  = 1'b0;
                            mode_o.alu.op_mask  = ALU_MASK_NONE;
                            mode_o.alu.cmp      = 1'b0;
                            mode_o.alu.masked   = instr_masked;
                        end
                        {6'b000011, 3'b011},        // vrsub VI
                        {6'b000011, 3'b100}: begin  // vrsub VX
                            unit_o              = UNIT_ALU;
                            mode_o.alu.opx2.res = ALU_VADD;
                            mode_o.alu.opx1.sel = ALU_SEL_MASK;
                            mode_o.alu.inv_op1  = 1'b0;
                            mode_o.alu.inv_op2  = 1'b1;
                            mode_o.alu.op_mask  = ALU_MASK_NONE;
                            mode_o.alu.cmp      = 1'b0;
                            mode_o.alu.masked   = instr_masked;
                        end
                        {6'b000100, 3'b000},        // vminu VV
                        {6'b000100, 3'b100}: begin  // vminu VX
                            unit_o              = UNIT_ALU;
                            mode_o.alu.opx2.res = ALU_VSELN;
                            mode_o.alu.opx1.sel = ALU_SEL_CARRY;
                            mode_o.alu.inv_op1  = 1'b1;
                            mode_o.alu.inv_op2  = 1'b0;
                            mode_o.alu.op_mask  = ALU_MASK_SEL;
                            mode_o.alu.cmp      = 1'b0;
                            mode_o.alu.masked   = instr_masked;
                        end
                        {6'b000101, 3'b000},        // vmin VV
                        {6'b000101, 3'b100}: begin  // vmin VX
                            unit_o              = UNIT_ALU;
                            mode_o.alu.opx2.res = ALU_VSELN;
                            mode_o.alu.opx1.sel = ALU_SEL_LT;
                            mode_o.alu.inv_op1  = 1'b1;
                            mode_o.alu.inv_op2  = 1'b0;
                            mode_o.alu.op_mask  = ALU_MASK_SEL;
                            mode_o.alu.cmp      = 1'b0;
                            mode_o.alu.masked   = instr_masked;
                        end
                        {6'b000110, 3'b000},        // vmaxu VV
                        {6'b000110, 3'b100}: begin  // vmaxu VX
                            unit_o              = UNIT_ALU;
                            mode_o.alu.opx2.res = ALU_VSEL;
                            mode_o.alu.opx1.sel = ALU_SEL_CARRY;
                            mode_o.alu.inv_op1  = 1'b1;
                            mode_o.alu.inv_op2  = 1'b0;
                            mode_o.alu.op_mask  = ALU_MASK_SEL;
                            mode_o.alu.cmp      = 1'b0;
                            mode_o.alu.masked   = instr_masked;
                        end
                        {6'b000111, 3'b000},        // vmax VV
                        {6'b000111, 3'b100}: begin  // vmax VX
                            unit_o              = UNIT_ALU;
                            mode_o.alu.opx2.res = ALU_VSEL;
                            mode_o.alu.opx1.sel = ALU_SEL_LT;
                            mode_o.alu.inv_op1  = 1'b1;
                            mode_o.alu.inv_op2  = 1'b0;
                            mode_o.alu.op_mask  = ALU_MASK_SEL;
                            mode_o.alu.cmp      = 1'b0;
                            mode_o.alu.masked   = instr_masked;
                        end
                        {6'b001001, 3'b000},        // vand VV
                        {6'b001001, 3'b011},        // vand VI
                        {6'b001001, 3'b100}: begin  // vand VX
                            unit_o              = UNIT_ALU;
                            mode_o.alu.opx2.res = ALU_VAND;
                            mode_o.alu.inv_op1  = 1'b0;
                            mode_o.alu.inv_op2  = 1'b0;
                            mode_o.alu.op_mask  = ALU_MASK_NONE;
                            mode_o.alu.cmp      = 1'b0;
                            mode_o.alu.masked   = instr_masked;
                        end
                        {6'b001010, 3'b000},        // vor VV
                        {6'b001010, 3'b011},        // vor VI
                        {6'b001010, 3'b100}: begin  // vor VX
                            unit_o              = UNIT_ALU;
                            mode_o.alu.opx2.res = ALU_VOR;
                            mode_o.alu.inv_op1  = 1'b0;
                            mode_o.alu.inv_op2  = 1'b0;
                            mode_o.alu.op_mask  = ALU_MASK_NONE;
                            mode_o.alu.cmp      = 1'b0;
                            mode_o.alu.masked   = instr_masked;
                        end
                        {6'b001011, 3'b000},        // vxor VV
                        {6'b001011, 3'b011},        // vxor VI
                        {6'b001011, 3'b100}: begin  // vxor VX
                            unit_o              = UNIT_ALU;
                            mode_o.alu.opx2.res = ALU_VXOR;
                            mode_o.alu.inv_op1  = 1'b0;
                            mode_o.alu.inv_op2  = 1'b0;
                            mode_o.alu.op_mask  = ALU_MASK_NONE;
                            mode_o.alu.cmp      = 1'b0;
                            mode_o.alu.masked   = instr_masked;
                        end
                        {6'b100101, 3'b000},        // vsll VV
                        {6'b100101, 3'b011},        // vsll VI
                        {6'b100101, 3'b100}: begin  // vsll VX
                            unit_o                = UNIT_ALU;
                            mode_o.alu.opx2.res   = ALU_VSHIFT;
                            mode_o.alu.opx1.shift = ALU_SHIFT_VSLL;
                            mode_o.alu.inv_op1    = 1'b0;
                            mode_o.alu.inv_op2    = 1'b0;
                            mode_o.alu.op_mask    = ALU_MASK_NONE;
                            mode_o.alu.cmp        = 1'b0;
                            mode_o.alu.masked     = instr_masked;
                        end
                        {6'b101000, 3'b000},        // vsrl VV
                        {6'b101000, 3'b011},        // vsrl VI
                        {6'b101000, 3'b100}: begin  // vsrl VX
                            unit_o                = UNIT_ALU;
                            mode_o.alu.opx2.res   = ALU_VSHIFT;
                            mode_o.alu.opx1.shift = ALU_SHIFT_VSRL;
                            mode_o.alu.inv_op1    = 1'b0;
                            mode_o.alu.inv_op2    = 1'b0;
                            mode_o.alu.op_mask    = ALU_MASK_NONE;
                            mode_o.alu.cmp        = 1'b0;
                            mode_o.alu.masked     = instr_masked;
                        end
                        {6'b101001, 3'b000},        // vsra VV
                        {6'b101001, 3'b011},        // vsra VI
                        {6'b101001, 3'b100}: begin  // vsra VX
                            unit_o                = UNIT_ALU;
                            mode_o.alu.opx2.res   = ALU_VSHIFT;
                            mode_o.alu.opx1.shift = ALU_SHIFT_VSRA;
                            mode_o.alu.inv_op1    = 1'b0;
                            mode_o.alu.inv_op2    = 1'b0;
                            mode_o.alu.op_mask    = ALU_MASK_NONE;
                            mode_o.alu.cmp        = 1'b0;
                            mode_o.alu.masked     = instr_masked;
                        end
                        {6'b101100, 3'b000},        // vnsrl VV
                        {6'b101100, 3'b011},        // vnsrl VI
                        {6'b101100, 3'b100}: begin  // vnsrl VX
                            unit_o                = UNIT_ALU;
                            mode_o.alu.opx2.res   = ALU_VSHIFT;
                            mode_o.alu.opx1.shift = ALU_SHIFT_VSRL;
                            mode_o.alu.inv_op1    = 1'b0;
                            mode_o.alu.inv_op2    = 1'b0;
                            mode_o.alu.op_mask    = ALU_MASK_NONE;
                            mode_o.alu.cmp        = 1'b0;
                            mode_o.alu.masked     = instr_masked;
                            widenarrow_o          = OP_NARROWING;
                        end
                        {6'b101101, 3'b000},        // vnsra VV
                        {6'b101101, 3'b011},        // vnsra VI
                        {6'b101101, 3'b100}: begin  // vnsra VX
                            unit_o                = UNIT_ALU;
                            mode_o.alu.opx2.res   = ALU_VSHIFT;
                            mode_o.alu.opx1.shift = ALU_SHIFT_VSRA;
                            mode_o.alu.inv_op1    = 1'b0;
                            mode_o.alu.inv_op2    = 1'b0;
                            mode_o.alu.op_mask    = ALU_MASK_NONE;
                            mode_o.alu.cmp        = 1'b0;
                            mode_o.alu.masked     = instr_masked;
                            widenarrow_o          = OP_NARROWING;
                        end
                        {6'b110000, 3'b010},        // vwaddu VV
                        {6'b110000, 3'b110}: begin  // vwaddu VX
                            unit_o              = UNIT_ALU;
                            mode_o.alu.opx2.res = ALU_VADD;
                            mode_o.alu.opx1.sel = ALU_SEL_MASK;
                            mode_o.alu.inv_op1  = 1'b0;
                            mode_o.alu.inv_op2  = 1'b0;
                            mode_o.alu.op_mask  = ALU_MASK_NONE;
                            mode_o.alu.cmp      = 1'b0;
                            mode_o.alu.masked   = instr_masked;
                            mode_o.alu.sigext   = 1'b0;
                            widenarrow_o        = OP_WIDENING;
                        end
                        {6'b110001, 3'b010},        // vwadd VV
                        {6'b110001, 3'b110}: begin  // vwadd VX
                            unit_o              = UNIT_ALU;
                            mode_o.alu.opx2.res = ALU_VADD;
                            mode_o.alu.opx1.sel = ALU_SEL_MASK;
                            mode_o.alu.inv_op1  = 1'b0;
                            mode_o.alu.inv_op2  = 1'b0;
                            mode_o.alu.op_mask  = ALU_MASK_NONE;
                            mode_o.alu.cmp      = 1'b0;
                            mode_o.alu.masked   = instr_masked;
                            mode_o.alu.sigext   = 1'b1;
                            widenarrow_o        = OP_WIDENING;
                        end
                        {6'b110010, 3'b010},        // vwsubu VV
                        {6'b110010, 3'b110}: begin  // vwsubu VX
                            unit_o              = UNIT_ALU;
                            mode_o.alu.opx2.res = ALU_VADD;
                            mode_o.alu.opx1.sel = ALU_SEL_MASK;
                            mode_o.alu.inv_op1  = 1'b1;
                            mode_o.alu.inv_op2  = 1'b0;
                            mode_o.alu.op_mask  = ALU_MASK_NONE;
                            mode_o.alu.cmp      = 1'b0;
                            mode_o.alu.masked   = instr_masked;
                            mode_o.alu.sigext   = 1'b0;
                            widenarrow_o        = OP_WIDENING;
                        end
                        {6'b110011, 3'b010},        // vwsub VV
                        {6'b110011, 3'b110}: begin  // vwsub VX
                            unit_o              = UNIT_ALU;
                            mode_o.alu.opx2.res = ALU_VADD;
                            mode_o.alu.opx1.sel = ALU_SEL_MASK;
                            mode_o.alu.inv_op1  = 1'b1;
                            mode_o.alu.inv_op2  = 1'b0;
                            mode_o.alu.op_mask  = ALU_MASK_NONE;
                            mode_o.alu.cmp      = 1'b0;
                            mode_o.alu.masked   = instr_masked;
                            mode_o.alu.sigext   = 1'b1;
                            widenarrow_o        = OP_WIDENING;
                        end
                        {6'b110100, 3'b010},        // vwaddu.w VV
                        {6'b110100, 3'b110}: begin  // vwaddu.w VX
                            unit_o              = UNIT_ALU;
                            mode_o.alu.opx2.res = ALU_VADD;
                            mode_o.alu.opx1.sel = ALU_SEL_MASK;
                            mode_o.alu.inv_op1  = 1'b0;
                            mode_o.alu.inv_op2  = 1'b0;
                            mode_o.alu.op_mask  = ALU_MASK_NONE;
                            mode_o.alu.cmp      = 1'b0;
                            mode_o.alu.masked   = instr_masked;
                            mode_o.alu.sigext   = 1'b0;
                            widenarrow_o        = OP_WIDENING_VS2;
                        end
                        {6'b110101, 3'b010},        // vwadd.w VV
                        {6'b110101, 3'b110}: begin  // vwadd.w VX
                            unit_o              = UNIT_ALU;
                            mode_o.alu.opx2.res = ALU_VADD;
                            mode_o.alu.opx1.sel = ALU_SEL_MASK;
                            mode_o.alu.inv_op1  = 1'b0;
                            mode_o.alu.inv_op2  = 1'b0;
                            mode_o.alu.op_mask  = ALU_MASK_NONE;
                            mode_o.alu.cmp      = 1'b0;
                            mode_o.alu.masked   = instr_masked;
                            mode_o.alu.sigext   = 1'b1;
                            widenarrow_o        = OP_WIDENING_VS2;
                        end
                        {6'b110110, 3'b010},        // vwsubu.w VV
                        {6'b110110, 3'b110}: begin  // vwsubu.w VX
                            unit_o              = UNIT_ALU;
                            mode_o.alu.opx2.res = ALU_VADD;
                            mode_o.alu.opx1.sel = ALU_SEL_MASK;
                            mode_o.alu.inv_op1  = 1'b1;
                            mode_o.alu.inv_op2  = 1'b0;
                            mode_o.alu.op_mask  = ALU_MASK_NONE;
                            mode_o.alu.cmp      = 1'b0;
                            mode_o.alu.masked   = instr_masked;
                            mode_o.alu.sigext   = 1'b0;
                            widenarrow_o        = OP_WIDENING_VS2;
                        end
                        {6'b110111, 3'b010},        // vwsub.w VV
                        {6'b110111, 3'b110}: begin  // vwsub.w VX
                            unit_o              = UNIT_ALU;
                            mode_o.alu.opx2.res = ALU_VADD;
                            mode_o.alu.opx1.sel = ALU_SEL_MASK;
                            mode_o.alu.inv_op1  = 1'b1;
                            mode_o.alu.inv_op2  = 1'b0;
                            mode_o.alu.op_mask  = ALU_MASK_NONE;
                            mode_o.alu.cmp      = 1'b0;
                            mode_o.alu.masked   = instr_masked;
                            mode_o.alu.sigext   = 1'b1;
                            widenarrow_o        = OP_WIDENING_VS2;
                        end
                        {6'b010000, 3'b000},        // vadc VV
                        {6'b010000, 3'b011},        // vadc VI
                        {6'b010000, 3'b100}: begin  // vadc VX
                            unit_o              = UNIT_ALU;
                            mode_o.alu.opx2.res = ALU_VADD;
                            mode_o.alu.opx1.sel = ALU_SEL_MASK;
                            mode_o.alu.inv_op1  = 1'b0;
                            mode_o.alu.inv_op2  = 1'b0;
                            mode_o.alu.op_mask  = ALU_MASK_CARRY;
                            mode_o.alu.cmp      = 1'b0;
                            mode_o.alu.masked   = 1'b0;
                        end
                        {6'b010010, 3'b000},        // vsbc VV
                        {6'b010010, 3'b011},        // vsbc VI
                        {6'b010010, 3'b100}: begin  // vsbc VX
                            unit_o              = UNIT_ALU;
                            mode_o.alu.opx2.res = ALU_VADD;
                            mode_o.alu.opx1.sel = ALU_SEL_MASK;
                            mode_o.alu.inv_op1  = 1'b1;
                            mode_o.alu.inv_op2  = 1'b0;
                            mode_o.alu.op_mask  = ALU_MASK_CARRY;
                            mode_o.alu.cmp      = 1'b0;
                            mode_o.alu.masked   = 1'b0;
                        end
                        {6'b010010, 3'b010}: begin  // v[z|s]ext.vf2 VV
                            unit_o              = UNIT_ALU;
                            mode_o.alu.opx2.res = ALU_VSEL;
                            mode_o.alu.opx1.sel = ALU_SEL_MASK;
                            mode_o.alu.inv_op1  = 1'b0;
                            mode_o.alu.inv_op2  = 1'b0;
                            mode_o.alu.op_mask  = ALU_MASK_NONE;
                            mode_o.alu.cmp      = 1'b0;
                            mode_o.alu.masked   = instr_masked;
                            mode_o.alu.sigext   = instr_vs1[0];
                            rs1_o.vreg          = 1'b0;
                            instr_illegal       = (instr_vs1[4:1] != 4'b0011);
                            widenarrow_o        = OP_WIDENING;
                        end
                        {6'b011000, 3'b010}: begin  // vmandnot VV
                            unit_o              = UNIT_ALU;
                            mode_o.alu.opx2.res = ALU_VAND;
                            mode_o.alu.inv_op1  = 1'b1;
                            mode_o.alu.inv_op2  = 1'b0;
                            mode_o.alu.op_mask  = ALU_MASK_ARIT;
                            mode_o.alu.cmp      = 1'b0;
                            mode_o.alu.masked   = 1'b0;
                        end
                        {6'b011001, 3'b010}: begin  // vmand VV
                            unit_o              = UNIT_ALU;
                            mode_o.alu.opx2.res = ALU_VAND;
                            mode_o.alu.inv_op1  = 1'b0;
                            mode_o.alu.inv_op2  = 1'b0;
                            mode_o.alu.op_mask  = ALU_MASK_ARIT;
                            mode_o.alu.cmp      = 1'b0;
                            mode_o.alu.masked   = 1'b0;
                        end
                        {6'b011010, 3'b010}: begin  // vmor VV
                            unit_o              = UNIT_ALU;
                            mode_o.alu.opx2.res = ALU_VOR;
                            mode_o.alu.inv_op1  = 1'b0;
                            mode_o.alu.inv_op2  = 1'b0;
                            mode_o.alu.op_mask  = ALU_MASK_ARIT;
                            mode_o.alu.cmp      = 1'b0;
                            mode_o.alu.masked   = 1'b0;
                        end
                        {6'b011011, 3'b010}: begin  // vmxor VV
                            unit_o              = UNIT_ALU;
                            mode_o.alu.opx2.res = ALU_VXOR;
                            mode_o.alu.inv_op1  = 1'b0;
                            mode_o.alu.inv_op2  = 1'b0;
                            mode_o.alu.op_mask  = ALU_MASK_ARIT;
                            mode_o.alu.cmp      = 1'b0;
                            mode_o.alu.masked   = 1'b0;
                        end
                        {6'b011100, 3'b010}: begin  // vmornot VV
                            unit_o              = UNIT_ALU;
                            mode_o.alu.opx2.res = ALU_VOR;
                            mode_o.alu.inv_op1  = 1'b1;
                            mode_o.alu.inv_op2  = 1'b0;
                            mode_o.alu.op_mask  = ALU_MASK_ARIT;
                            mode_o.alu.cmp      = 1'b0;
                            mode_o.alu.masked   = 1'b0;
                        end
                        {6'b011101, 3'b010}: begin  // vmnand VV
                            unit_o              = UNIT_ALU;
                            mode_o.alu.opx2.res = ALU_VOR;
                            mode_o.alu.inv_op1  = 1'b1;
                            mode_o.alu.inv_op2  = 1'b1;
                            mode_o.alu.op_mask  = ALU_MASK_ARIT;
                            mode_o.alu.cmp      = 1'b0;
                            mode_o.alu.masked   = 1'b0;
                        end
                        {6'b011110, 3'b010}: begin  // vmnor VV
                            unit_o              = UNIT_ALU;
                            mode_o.alu.opx2.res = ALU_VAND;
                            mode_o.alu.inv_op1  = 1'b1;
                            mode_o.alu.inv_op2  = 1'b1;
                            mode_o.alu.op_mask  = ALU_MASK_ARIT;
                            mode_o.alu.cmp      = 1'b0;
                            mode_o.alu.masked   = 1'b0;
                        end
                        {6'b011111, 3'b010}: begin  // vmxnor VV
                            unit_o              = UNIT_ALU;
                            mode_o.alu.opx2.res = ALU_VXOR;
                            mode_o.alu.inv_op1  = 1'b1;
                            mode_o.alu.inv_op2  = 1'b0;
                            mode_o.alu.op_mask  = ALU_MASK_ARIT;
                            mode_o.alu.cmp      = 1'b0;
                            mode_o.alu.masked   = 1'b0;
                        end
                        {6'b010111, 3'b000},        // vmv/vmerge VV
                        {6'b010111, 3'b011},        // vmv/vmerge VI
                        {6'b010111, 3'b100}: begin  // vmv/vmerge VX
                            unit_o              = UNIT_ALU;
                            mode_o.alu.opx2.res = instr_masked ? ALU_VSEL : ALU_VSELN;
                            mode_o.alu.opx1.sel = ALU_SEL_MASK;
                            mode_o.alu.inv_op1  = 1'b1;
                            mode_o.alu.inv_op2  = 1'b0;
                            mode_o.alu.op_mask  = instr_masked ? ALU_MASK_SEL : ALU_MASK_NONE;
                            mode_o.alu.cmp      = 1'b0;
                            mode_o.alu.masked   = 1'b0;
                            if (~instr_masked) begin
                                rs2_o.vreg      = 1'b0;
                            end
                        end
                        {6'b011000, 3'b000},        // vmseq VV
                        {6'b011000, 3'b011},        // vmseq VI
                        {6'b011000, 3'b100}: begin  // vmseq VX
                            unit_o              = UNIT_ALU;
                            mode_o.alu.opx2.cmp = ALU_CMP_EQ;
                            mode_o.alu.inv_op1  = 1'b1;
                            mode_o.alu.inv_op2  = 1'b0;
                            mode_o.alu.op_mask  = ALU_MASK_NONE;
                            mode_o.alu.cmp      = 1'b1;
                            mode_o.alu.masked   = instr_masked;
                        end
                        {6'b011001, 3'b000},        // vmsne VV
                        {6'b011001, 3'b011},        // vmsne VI
                        {6'b011001, 3'b100}: begin  // vmsne VX
                            unit_o              = UNIT_ALU;
                            mode_o.alu.opx2.cmp = ALU_CMP_NE;
                            mode_o.alu.inv_op1  = 1'b1;
                            mode_o.alu.inv_op2  = 1'b0;
                            mode_o.alu.op_mask  = ALU_MASK_NONE;
                            mode_o.alu.cmp      = 1'b1;
                            mode_o.alu.masked   = instr_masked;
                        end
                        {6'b011010, 3'b000},        // vmsltu VV
                        {6'b011010, 3'b100}: begin  // vmsltu VX
                            unit_o              = UNIT_ALU;
                            mode_o.alu.opx2.cmp = ALU_CMP_CMP;
                            mode_o.alu.opx1.sel = ALU_SEL_CARRY;
                            mode_o.alu.inv_op1  = 1'b1;
                            mode_o.alu.inv_op2  = 1'b0;
                            mode_o.alu.op_mask  = ALU_MASK_NONE;
                            mode_o.alu.cmp      = 1'b1;
                            mode_o.alu.masked   = instr_masked;
                        end
                        {6'b011011, 3'b000},        // vmslt VV
                        {6'b011011, 3'b100}: begin  // vmslt VX
                            unit_o              = UNIT_ALU;
                            mode_o.alu.opx2.cmp = ALU_CMP_CMP;
                            mode_o.alu.opx1.sel = ALU_SEL_LT;
                            mode_o.alu.inv_op1  = 1'b1;
                            mode_o.alu.inv_op2  = 1'b0;
                            mode_o.alu.op_mask  = ALU_MASK_NONE;
                            mode_o.alu.cmp      = 1'b1;
                            mode_o.alu.masked   = instr_masked;
                        end
                        {6'b011100, 3'b000},        // vmsleu VV
                        {6'b011100, 3'b011},        // vmsleu VI
                        {6'b011100, 3'b100}: begin  // vmsleu VX
                            unit_o              = UNIT_ALU;
                            mode_o.alu.opx2.cmp = ALU_CMP_CMPN;
                            mode_o.alu.opx1.sel = ALU_SEL_CARRY;
                            mode_o.alu.inv_op1  = 1'b0;
                            mode_o.alu.inv_op2  = 1'b1;
                            mode_o.alu.op_mask  = ALU_MASK_NONE;
                            mode_o.alu.cmp      = 1'b1;
                            mode_o.alu.masked   = instr_masked;
                        end
                        {6'b011101, 3'b000},        // vmsle VV
                        {6'b011101, 3'b011},        // vmsle VI
                        {6'b011101, 3'b100}: begin  // vmsle VX
                            unit_o              = UNIT_ALU;
                            mode_o.alu.opx2.cmp = ALU_CMP_CMPN;
                            mode_o.alu.opx1.sel = ALU_SEL_LT;
                            mode_o.alu.inv_op1  = 1'b0;
                            mode_o.alu.inv_op2  = 1'b1;
                            mode_o.alu.op_mask  = ALU_MASK_NONE;
                            mode_o.alu.cmp      = 1'b1;
                            mode_o.alu.masked   = instr_masked;
                        end
                        {6'b011110, 3'b011},        // vmsgtu VI
                        {6'b011110, 3'b100}: begin  // vmsgtu VX
                            unit_o              = UNIT_ALU;
                            mode_o.alu.opx2.cmp = ALU_CMP_CMP;
                            mode_o.alu.opx1.sel = ALU_SEL_CARRY;
                            mode_o.alu.inv_op1  = 1'b0;
                            mode_o.alu.inv_op2  = 1'b1;
                            mode_o.alu.op_mask  = ALU_MASK_NONE;
                            mode_o.alu.cmp      = 1'b1;
                            mode_o.alu.masked   = instr_masked;
                        end
                        {6'b011111, 3'b011},        // vmsgt VI
                        {6'b011111, 3'b100}: begin  // vmsgt VX
                            unit_o              = UNIT_ALU;
                            mode_o.alu.opx2.cmp = ALU_CMP_CMP;
                            mode_o.alu.opx1.sel = ALU_SEL_LT;
                            mode_o.alu.inv_op1  = 1'b0;
                            mode_o.alu.inv_op2  = 1'b1;
                            mode_o.alu.op_mask  = ALU_MASK_NONE;
                            mode_o.alu.cmp      = 1'b1;
                            mode_o.alu.masked   = instr_masked;
                        end
                        {6'b010001, 3'b000},        // vmadc VV
                        {6'b010001, 3'b011},        // vmadc VI
                        {6'b010001, 3'b100}: begin  // vmadc VX
                            unit_o              = UNIT_ALU;
                            mode_o.alu.opx2.cmp = ALU_CMP_CMP;
                            mode_o.alu.opx1.sel = ALU_SEL_CARRY;
                            mode_o.alu.inv_op1  = 1'b0;
                            mode_o.alu.inv_op2  = 1'b0;
                            mode_o.alu.op_mask  = instr_masked ? ALU_MASK_CARRY : ALU_MASK_NONE;
                            mode_o.alu.cmp      = 1'b1;
                            mode_o.alu.masked   = 1'b0;
                        end
                        {6'b010011, 3'b000},        // vmsbc VV
                        {6'b010011, 3'b011},        // vmsbc VI
                        {6'b010011, 3'b100}: begin  // vmsbc VX
                            unit_o              = UNIT_ALU;
                            mode_o.alu.opx2.cmp = ALU_CMP_CMP;
                            mode_o.alu.opx1.sel = ALU_SEL_CARRY;
                            mode_o.alu.inv_op1  = 1'b1;
                            mode_o.alu.inv_op2  = 1'b0;
                            mode_o.alu.op_mask  = instr_masked ? ALU_MASK_CARRY : ALU_MASK_NONE;
                            mode_o.alu.cmp      = 1'b1;
                            mode_o.alu.masked   = 1'b0;
                        end
                        {6'b100000, 3'b000},        // vsaddu VV
                        {6'b100000, 3'b011},        // vsaddu VI
                        {6'b100000, 3'b100}: begin  // vsaddu VX
                            unit_o              = UNIT_ALU;
                            mode_o.alu.opx2.res = ALU_VADD;
                            mode_o.alu.opx1.sel = ALU_SEL_CARRY;
                            mode_o.alu.inv_op1  = 1'b0;
                            mode_o.alu.inv_op2  = 1'b0;
                            mode_o.alu.op_mask  = ALU_MASK_NONE;
                            mode_o.alu.cmp      = 1'b0;
                            mode_o.alu.masked   = instr_masked;
                        end
                        {6'b100001, 3'b000},        // vsadd VV
                        {6'b100001, 3'b011},        // vsadd VI
                        {6'b100001, 3'b100}: begin  // vsadd VX
                            unit_o              = UNIT_ALU;
                            mode_o.alu.opx2.res = ALU_VADD;
                            mode_o.alu.opx1.sel = ALU_SEL_OVFLW;
                            mode_o.alu.inv_op1  = 1'b0;
                            mode_o.alu.inv_op2  = 1'b0;
                            mode_o.alu.op_mask  = ALU_MASK_NONE;
                            mode_o.alu.cmp      = 1'b0;
                            mode_o.alu.masked   = instr_masked;
                        end
                        {6'b100010, 3'b000},        // vssubu VV
                        {6'b100010, 3'b100}: begin  // vssubu VX
                            unit_o              = UNIT_ALU;
                            mode_o.alu.opx2.res = ALU_VADD;
                            mode_o.alu.opx1.sel = ALU_SEL_CARRY;
                            mode_o.alu.inv_op1  = 1'b1;
                            mode_o.alu.inv_op2  = 1'b0;
                            mode_o.alu.op_mask  = ALU_MASK_NONE;
                            mode_o.alu.cmp      = 1'b0;
                            mode_o.alu.masked   = instr_masked;
                        end
                        {6'b100011, 3'b000},        // vssub VV
                        {6'b100011, 3'b100}: begin  // vssub VX
                            unit_o              = UNIT_ALU;
                            mode_o.alu.opx2.res = ALU_VADD;
                            mode_o.alu.opx1.sel = ALU_SEL_OVFLW;
                            mode_o.alu.inv_op1  = 1'b1;
                            mode_o.alu.inv_op2  = 1'b0;
                            mode_o.alu.op_mask  = ALU_MASK_NONE;
                            mode_o.alu.cmp      = 1'b0;
                            mode_o.alu.masked   = instr_masked;
                        end
                        {6'b001000, 3'b010},        // vaaddu VV
                        {6'b001000, 3'b110}: begin  // vaaddu VX
                            unit_o              = UNIT_ALU;
                            mode_o.alu.opx2.res = ALU_VAADD;
                            mode_o.alu.opx1.sel = ALU_SEL_MASK;
                            mode_o.alu.inv_op1  = 1'b0;
                            mode_o.alu.inv_op2  = 1'b0;
                            mode_o.alu.op_mask  = ALU_MASK_NONE;
                            mode_o.alu.cmp      = 1'b0;
                            mode_o.alu.masked   = instr_masked;
                        end
                        {6'b001001, 3'b010},        // vaadd VV
                        {6'b001001, 3'b110}: begin  // vaadd VX
                            unit_o              = UNIT_ALU;
                            mode_o.alu.opx2.res = ALU_VAADD;
                            mode_o.alu.opx1.sel = ALU_SEL_MASK;
                            mode_o.alu.inv_op1  = 1'b0;
                            mode_o.alu.inv_op2  = 1'b0;
                            mode_o.alu.op_mask  = ALU_MASK_NONE;
                            mode_o.alu.cmp      = 1'b0;
                            mode_o.alu.masked   = instr_masked;
                        end
                        {6'b001010, 3'b010},        // vasubu VV
                        {6'b001010, 3'b110}: begin  // vasubu VX
                            unit_o              = UNIT_ALU;
                            mode_o.alu.opx2.res = ALU_VAADD;
                            mode_o.alu.opx1.sel = ALU_SEL_MASK;
                            mode_o.alu.inv_op1  = 1'b1;
                            mode_o.alu.inv_op2  = 1'b0;
                            mode_o.alu.op_mask  = ALU_MASK_NONE;
                            mode_o.alu.cmp      = 1'b0;
                            mode_o.alu.masked   = instr_masked;
                        end
                        {6'b001011, 3'b010},        // vasub VV
                        {6'b001011, 3'b110}: begin  // vasub VX
                            unit_o              = UNIT_ALU;
                            mode_o.alu.opx2.res = ALU_VAADD;
                            mode_o.alu.opx1.sel = ALU_SEL_MASK;
                            mode_o.alu.inv_op1  = 1'b1;
                            mode_o.alu.inv_op2  = 1'b0;
                            mode_o.alu.op_mask  = ALU_MASK_NONE;
                            mode_o.alu.cmp      = 1'b0;
                            mode_o.alu.masked   = instr_masked;
                        end


                        // MUL unit:
                        {6'b100100, 3'b010},        // vmulhu VV
                        {6'b100100, 3'b110}: begin  // vmulhu VX
                            unit_o                = UNIT_MUL;
                            mode_o.mul.op         = MUL_VMULH;
                            mode_o.mul.rounding   = VXRM_RDN;
                            mode_o.mul.accsub     = 1'b0;
                            mode_o.mul.op1_signed = 1'b0;
                            mode_o.mul.op2_signed = 1'b0;
                            mode_o.mul.op2_is_vd  = 1'b0;
                            mode_o.mul.masked     = instr_masked;
                        end
                        {6'b100101, 3'b010},        // vmul VV
                        {6'b100101, 3'b110}: begin  // vmul VX
                            unit_o                = UNIT_MUL;
                            mode_o.mul.op         = MUL_VMUL;
                            mode_o.mul.rounding   = VXRM_RDN;
                            mode_o.mul.accsub     = 1'b0;
                            mode_o.mul.op1_signed = 1'b0; // irrelevant
                            mode_o.mul.op2_signed = 1'b0; // irrelevant
                            mode_o.mul.op2_is_vd  = 1'b0;
                            mode_o.mul.masked     = instr_masked;
                        end
                        {6'b100110, 3'b010},        // vmulhsu VV
                        {6'b100110, 3'b110}: begin  // vmulhsu VX
                            unit_o                = UNIT_MUL;
                            mode_o.mul.op         = MUL_VMULH;
                            mode_o.mul.rounding   = VXRM_RDN;
                            mode_o.mul.accsub     = 1'b0;
                            mode_o.mul.op1_signed = 1'b0;
                            mode_o.mul.op2_signed = 1'b1;
                            mode_o.mul.op2_is_vd  = 1'b0;
                            mode_o.mul.masked     = instr_masked;
                        end
                        {6'b100111, 3'b010},        // vmulh VV
                        {6'b100111, 3'b110}: begin  // vmulh VX
                            unit_o                = UNIT_MUL;
                            mode_o.mul.op         = MUL_VMULH;
                            mode_o.mul.rounding   = VXRM_RDN;
                            mode_o.mul.accsub     = 1'b0;
                            mode_o.mul.op1_signed = 1'b1;
                            mode_o.mul.op2_signed = 1'b1;
                            mode_o.mul.op2_is_vd  = 1'b0;
                            mode_o.mul.masked     = instr_masked;
                        end
                        {6'b101001, 3'b010},        // vmadd VV
                        {6'b101001, 3'b110}: begin  // vmadd VX
                            unit_o                = UNIT_MUL;
                            mode_o.mul.op         = MUL_VMACC;
                            mode_o.mul.rounding   = VXRM_RDN;
                            mode_o.mul.accsub     = 1'b0;
                            mode_o.mul.op1_signed = 1'b0; // irrelevant
                            mode_o.mul.op2_signed = 1'b0; // irrelevant
                            mode_o.mul.op2_is_vd  = 1'b1;
                            mode_o.mul.masked     = instr_masked;
                        end
                        {6'b101011, 3'b010},        // vnmsub VV
                        {6'b101011, 3'b110}: begin  // vnmsub VX
                            unit_o                = UNIT_MUL;
                            mode_o.mul.op         = MUL_VMACC;
                            mode_o.mul.rounding   = VXRM_RDN;
                            mode_o.mul.accsub     = 1'b1;
                            mode_o.mul.op1_signed = 1'b0; // irrelevant
                            mode_o.mul.op2_signed = 1'b0; // irrelevant
                            mode_o.mul.op2_is_vd  = 1'b1;
                            mode_o.mul.masked     = instr_masked;
                        end
                        {6'b101101, 3'b010},        // vmacc VV
                        {6'b101101, 3'b110}: begin  // vmacc VX
                            unit_o                = UNIT_MUL;
                            mode_o.mul.op         = MUL_VMACC;
                            mode_o.mul.rounding   = VXRM_RDN;
                            mode_o.mul.accsub     = 1'b0;
                            mode_o.mul.op1_signed = 1'b0; // irrelevant
                            mode_o.mul.op2_signed = 1'b0; // irrelevant
                            mode_o.mul.op2_is_vd  = 1'b0;
                            mode_o.mul.masked     = instr_masked;
                        end
                        {6'b101111, 3'b010},        // vnmsac VV
                        {6'b101111, 3'b110}: begin  // vnmsac VX
                            unit_o                = UNIT_MUL;
                            mode_o.mul.op         = MUL_VMACC;
                            mode_o.mul.rounding   = VXRM_RDN;
                            mode_o.mul.accsub     = 1'b1;
                            mode_o.mul.op1_signed = 1'b0; // irrelevant
                            mode_o.mul.op2_signed = 1'b0; // irrelevant
                            mode_o.mul.op2_is_vd  = 1'b0;
                            mode_o.mul.masked     = instr_masked;
                        end
                        {6'b111000, 3'b010},        // vwmulu VV
                        {6'b111000, 3'b110}: begin  // vwmulu VX
                            unit_o                = UNIT_MUL;
                            mode_o.mul.op         = MUL_VMUL;
                            mode_o.mul.rounding   = VXRM_RDN;
                            mode_o.mul.accsub     = 1'b0;
                            mode_o.mul.op1_signed = 1'b0;
                            mode_o.mul.op2_signed = 1'b0;
                            mode_o.mul.op2_is_vd  = 1'b0;
                            mode_o.mul.masked     = instr_masked;
                            widenarrow_o          = OP_WIDENING;
                        end
                        {6'b111010, 3'b010},        // vwmulsu VV
                        {6'b111010, 3'b110}: begin  // vwmulsu VX
                            unit_o                = UNIT_MUL;
                            mode_o.mul.op         = MUL_VMUL;
                            mode_o.mul.rounding   = VXRM_RDN;
                            mode_o.mul.accsub     = 1'b0;
                            mode_o.mul.op1_signed = 1'b0;
                            mode_o.mul.op2_signed = 1'b1;
                            mode_o.mul.op2_is_vd  = 1'b0;
                            mode_o.mul.masked     = instr_masked;
                            widenarrow_o          = OP_WIDENING;
                        end
                        {6'b111011, 3'b010},        // vwmul VV
                        {6'b111011, 3'b110}: begin  // vwmul VX
                            unit_o                = UNIT_MUL;
                            mode_o.mul.op         = MUL_VMUL;
                            mode_o.mul.rounding   = VXRM_RDN;
                            mode_o.mul.accsub     = 1'b0;
                            mode_o.mul.op1_signed = 1'b1;
                            mode_o.mul.op2_signed = 1'b1;
                            mode_o.mul.op2_is_vd  = 1'b0;
                            mode_o.mul.masked     = instr_masked;
                            widenarrow_o          = OP_WIDENING;
                        end
                        {6'b111100, 3'b010},        // vwmaccu VV
                        {6'b111100, 3'b110}: begin  // vwmaccu VX
                            unit_o                = UNIT_MUL;
                            mode_o.mul.op         = MUL_VMACC;
                            mode_o.mul.rounding   = VXRM_RDN;
                            mode_o.mul.accsub     = 1'b0;
                            mode_o.mul.op1_signed = 1'b0;
                            mode_o.mul.op2_signed = 1'b0;
                            mode_o.mul.op2_is_vd  = 1'b0;
                            mode_o.mul.masked     = instr_masked;
                            widenarrow_o          = OP_WIDENING;
                        end
                        {6'b111101, 3'b010},        // vwmacc VV
                        {6'b111101, 3'b110}: begin  // vwmacc VX
                            unit_o                = UNIT_MUL;
                            mode_o.mul.op         = MUL_VMACC;
                            mode_o.mul.rounding   = VXRM_RDN;
                            mode_o.mul.accsub     = 1'b0;
                            mode_o.mul.op1_signed = 1'b1;
                            mode_o.mul.op2_signed = 1'b1;
                            mode_o.mul.op2_is_vd  = 1'b0;
                            mode_o.mul.masked     = instr_masked;
                            widenarrow_o          = OP_WIDENING;
                        end
                        {6'b111110, 3'b010},        // vwmaccus VV
                        {6'b111110, 3'b110}: begin  // vwmaccus VX
                            unit_o                = UNIT_MUL;
                            mode_o.mul.op         = MUL_VMACC;
                            mode_o.mul.rounding   = VXRM_RDN;
                            mode_o.mul.accsub     = 1'b0;
                            mode_o.mul.op1_signed = 1'b0;
                            mode_o.mul.op2_signed = 1'b1;
                            mode_o.mul.op2_is_vd  = 1'b0;
                            mode_o.mul.masked     = instr_masked;
                            widenarrow_o          = OP_WIDENING;
                        end
                        {6'b111111, 3'b010},        // vwmaccsu VV
                        {6'b111111, 3'b110}: begin  // vwmaccsu VX
                            unit_o                = UNIT_MUL;
                            mode_o.mul.op         = MUL_VMACC;
                            mode_o.mul.rounding   = VXRM_RDN;
                            mode_o.mul.accsub     = 1'b0;
                            mode_o.mul.op1_signed = 1'b1;
                            mode_o.mul.op2_signed = 1'b0;
                            mode_o.mul.op2_is_vd  = 1'b0;
                            mode_o.mul.masked     = instr_masked;
                            widenarrow_o          = OP_WIDENING;
                        end
                        {6'b100111, 3'b000},        // vsmul VV
                        {6'b100111, 3'b100}: begin  // vsmul VX
                            unit_o                = UNIT_MUL;
                            mode_o.mul.op         = MUL_VSMUL;
                            mode_o.mul.rounding   = vxrm_i;
                            mode_o.mul.accsub     = 1'b0;
                            mode_o.mul.op1_signed = 1'b1;
                            mode_o.mul.op2_signed = 1'b1;
                            mode_o.mul.op2_is_vd  = 1'b0;
                            mode_o.mul.masked     = instr_masked;
                        end


                        // SLD unit:
                        {6'b001110, 3'b011},        // vslideup VI
                        {6'b001110, 3'b100}: begin  // vslideup VX
                            unit_o            = UNIT_SLD;
                            mode_o.sld.op     = SLD_UP;
                            mode_o.sld.masked = instr_masked;
                        end
                        {6'b001111, 3'b011},        // vslidedown VI
                        {6'b001111, 3'b100}: begin  // vslidedown VX
                            unit_o            = UNIT_SLD;
                            mode_o.sld.op     = SLD_DOWN;
                            mode_o.sld.masked = instr_masked;
                        end
                        {6'b001110, 3'b110}: begin  // vslide1up VX
                            unit_o            = UNIT_SLD;
                            mode_o.sld.op     = SLD_1UP;
                            mode_o.sld.masked = instr_masked;
                            rd_o.vreg         = 1'b1;
                        end
                        {6'b001111, 3'b110}: begin  // vslide1down VX
                            unit_o            = UNIT_SLD;
                            mode_o.sld.op     = SLD_1DOWN;
                            mode_o.sld.masked = instr_masked;
                        end


                        // ELEM unit:
                        {6'b001100, 3'b000},        // vrgather VV
                        {6'b001100, 3'b011},        // vrgather VI
                        {6'b001100, 3'b100}: begin  // vrgather VX
                            unit_o             = UNIT_ELEM;
                            mode_o.elem.op     = ELEM_VRGATHER;
                            mode_o.elem.xreg   = 1'b0;
                            mode_o.elem.masked = instr_masked;
                        end
                        {6'b010111, 3'b010}: begin  // vcompress VV
                            unit_o             = UNIT_ELEM;
                            mode_o.elem.op     = ELEM_VCOMPRESS;
                            mode_o.elem.xreg   = 1'b0;
                            mode_o.elem.masked = instr_masked;
                        end
                        {6'b000000, 3'b010}: begin  // vredsum VV
                            unit_o             = UNIT_ELEM;
                            mode_o.elem.op     = ELEM_VREDSUM;
                            mode_o.elem.xreg   = 1'b0;
                            mode_o.elem.masked = instr_masked;
                        end
                        {6'b000001, 3'b010}: begin  // vredand VV
                            unit_o             = UNIT_ELEM;
                            mode_o.elem.op     = ELEM_VREDAND;
                            mode_o.elem.xreg   = 1'b0;
                            mode_o.elem.masked = instr_masked;
                        end
                        {6'b000010, 3'b010}: begin  // vredor VV
                            unit_o             = UNIT_ELEM;
                            mode_o.elem.op     = ELEM_VREDOR;
                            mode_o.elem.xreg   = 1'b0;
                            mode_o.elem.masked = instr_masked;
                        end
                        {6'b000011, 3'b010}: begin  // vredxor VV
                            unit_o             = UNIT_ELEM;
                            mode_o.elem.op     = ELEM_VREDXOR;
                            mode_o.elem.xreg   = 1'b0;
                            mode_o.elem.masked = instr_masked;
                        end
                        {6'b000100, 3'b010}: begin  // vredminu VV
                            unit_o             = UNIT_ELEM;
                            mode_o.elem.op     = ELEM_VREDMINU;
                            mode_o.elem.xreg   = 1'b0;
                            mode_o.elem.masked = instr_masked;
                        end
                        {6'b000101, 3'b010}: begin  // vredmin VV
                            unit_o             = UNIT_ELEM;
                            mode_o.elem.op     = ELEM_VREDMIN;
                            mode_o.elem.xreg   = 1'b0;
                            mode_o.elem.masked = instr_masked;
                        end
                        {6'b000110, 3'b010}: begin  // vredmaxu VV
                            unit_o             = UNIT_ELEM;
                            mode_o.elem.op     = ELEM_VREDMAXU;
                            mode_o.elem.xreg   = 1'b0;
                            mode_o.elem.masked = instr_masked;
                        end
                        {6'b000111, 3'b010}: begin  // vredmax VV
                            unit_o             = UNIT_ELEM;
                            mode_o.elem.op     = ELEM_VREDMAX;
                            mode_o.elem.xreg   = 1'b0;
                            mode_o.elem.masked = instr_masked;
                        end


                        // Unary arithmetic:
                        {6'b010000, 3'b010}: begin  // VWXUNARY0
                            unit_o = UNIT_ELEM;
                            unique case (instr_i[19:15])
                                5'b00000: mode_o.elem.op = ELEM_XMV;    // vmv.x.s
                                5'b10000: mode_o.elem.op = ELEM_VPOPC;  // vpopc
                                5'b10001: mode_o.elem.op = ELEM_VFIRST; // vfirst
                                default:  instr_illegal  = 1'b1;
                            endcase
                            mode_o.elem.xreg   = 1'b1;
                            mode_o.elem.masked = instr_masked;
                            rs1_o.vreg         = 1'b0;
                            rd_o.vreg          = 1'b0;
                        end
                        {6'b010000, 3'b110}: begin  // VRXUNARY0
                            unique case (instr_i[24:20])
                                5'b00000: begin     // vmv.s.x
                                end
                                default: begin
                                    instr_illegal = 1'b1;
                                end
                            endcase
                        end
                        {6'b010100, 3'b010}: begin  // VMUNARY0
                            if (instr_vs1[4]) begin
                                unit_o             = UNIT_ELEM;
                                mode_o.elem.op     = instr_vs1[0] ? ELEM_VID : ELEM_VIOTA;
                                mode_o.elem.xreg   = 1'b0;
                                mode_o.elem.masked = instr_masked;
                                instr_illegal      = instr_vs1[3:1] != 3'b000;
                                rs1_o.vreg         = 1'b0;
                                rs2_o.vreg         = ~instr_vs1[0]; // vid has no source reg
                            end
                        end

                        default: begin
                            instr_illegal = 1'b1;
                        end
                    endcase
                end

            end

            default: begin
                instr_illegal = 1'b1;
            end

        endcase
    end


    // address masks (lower bits that must be 0) for registers based on EMUL:
    logic [2:0] regaddr_mask, regaddr_mask_w;
    always_comb begin
        regaddr_mask   = DONT_CARE_ZERO ? '0 : 'x;
        regaddr_mask_w = DONT_CARE_ZERO ? '0 : 'x;
        unique case (lmul_i)
            LMUL_F8,
            LMUL_F4,
            LMUL_F2,
            LMUL_1: begin
                regaddr_mask   = 3'b000;
                regaddr_mask_w = 3'b001;
            end
            LMUL_2: begin
                regaddr_mask   = 3'b001;
                regaddr_mask_w = 3'b011;
            end
            LMUL_4: begin
                regaddr_mask   = 3'b011;
                regaddr_mask_w = 3'b111;
            end
            LMUL_8: begin
                regaddr_mask   = 3'b111;
            end
            default: ;
        endcase
    end

    // check validity of register addresses:
    logic vs1_invalid, vs2_invalid, vd_invalid;
    always_comb begin
        vs1_invalid = DONT_CARE_ZERO ? 1'b0 : 1'bx;
        vs2_invalid = DONT_CARE_ZERO ? 1'b0 : 1'bx;
        vd_invalid  = DONT_CARE_ZERO ? 1'b0 : 1'bx;

        // regular operation:
        unique case (widenarrow_o)
            OP_SINGLEWIDTH: begin
                vs1_invalid = (instr_vs1 & {2'b00, regaddr_mask  }) != 5'b0;
                vs2_invalid = (instr_vs2 & {2'b00, regaddr_mask  }) != 5'b0;
                vd_invalid  = (instr_vd  & {2'b00, regaddr_mask  }) != 5'b0;
            end
            OP_WIDENING: begin
                vs1_invalid = (instr_vs1 & {2'b00, regaddr_mask  }) != 5'b0;
                vs2_invalid = (instr_vs2 & {2'b00, regaddr_mask  }) != 5'b0;
                vd_invalid  = (instr_vd  & {2'b00, regaddr_mask_w}) != 5'b0;
            end
            OP_WIDENING_VS2: begin
                vs1_invalid = (instr_vs1 & {2'b00, regaddr_mask  }) != 5'b0;
                vs2_invalid = (instr_vs2 & {2'b00, regaddr_mask_w}) != 5'b0;
                vd_invalid  = (instr_vd  & {2'b00, regaddr_mask_w}) != 5'b0;
            end
            OP_NARROWING: begin
                vs1_invalid = (instr_vs1 & {2'b00, regaddr_mask_w}) != 5'b0;
                vs2_invalid = (instr_vs2 & {2'b00, regaddr_mask_w}) != 5'b0;
                vd_invalid  = (instr_vd  & {2'b00, regaddr_mask  }) != 5'b0;
            end
            default: ;
        endcase

        // special cases (e.g. mask operations):
        if ((unit_o == UNIT_ALU) & (mode_o.alu.op_mask == ALU_MASK_ARIT)) begin
            vs1_invalid = 1'b0;
            vs2_invalid = 1'b0;
            vd_invalid  = 1'b0;
        end

        // register addresses are always valid if it is not a vector register:
        if (~rs1_o.vreg) begin
            vs1_invalid = 1'b0;
        end
        if (~rs2_o.vreg) begin
            vs2_invalid = 1'b0;
        end
        if (~rd_o.vreg ) begin
            vd_invalid  = 1'b0;
        end
    end


    logic emul_invalid;
    assign emul_invalid = (lmul_i == LMUL_8) & (widenarrow_o != OP_SINGLEWIDTH);

    logic op_illegal;   // operation illegal (invalid EMUL or register addresses for the current configuration):
    assign op_illegal = vs1_invalid | vs2_invalid | vd_invalid | emul_invalid;

    assign illegal_o = instr_valid_i & (instr_illegal | op_illegal);
    assign valid_o   = instr_valid_i & (~instr_illegal) & (~op_illegal);

endmodule
