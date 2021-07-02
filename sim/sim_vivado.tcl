# Copyright TU Wien
# Licensed under the ISC license, see LICENSE.txt for details
# SPDX-License-Identifier: ISC


################################################################################
# Create Project and Run Simulation
################################################################################

if {$argc < 5} {
    puts "usage: sim.tcl VPROC_DIR CORE_DIR PARAMS LOG_FILE PROG_PATHS_LIST \[SYMBOLS ...\]"
    exit 2
}

# get command line arguments
set vproc_dir [lindex $argv 0]
set core_dir  [lindex $argv 1]
set params_var "[lindex $argv 2]"
set log_file_path [lindex $argv 3]
set prog_paths_var "PROG_PATHS_LIST=\"[lindex $argv 4]\""

# create project
set _xil_proj_name_ "vproc_sim"
create_project -part xc7a200tfbg484-2 ${_xil_proj_name_} ${_xil_proj_name_}
set proj_dir [get_property directory [current_project]]

# set project properties
set obj [current_project]
set_property -name "default_lib" -value "xil_defaultlib" -objects $obj
set_property -name "dsa.accelerator_binary_content" -value "bitstream" -objects $obj
set_property -name "dsa.accelerator_binary_format" -value "xclbin2" -objects $obj
set_property -name "dsa.description" -value "Vivado generated DSA" -objects $obj
set_property -name "dsa.dr_bd_base_address" -value "0" -objects $obj
set_property -name "dsa.emu_dir" -value "emu" -objects $obj
set_property -name "dsa.flash_interface_type" -value "bpix16" -objects $obj
set_property -name "dsa.flash_offset_address" -value "0" -objects $obj
set_property -name "dsa.flash_size" -value "1024" -objects $obj
set_property -name "dsa.host_architecture" -value "x86_64" -objects $obj
set_property -name "dsa.host_interface" -value "pcie" -objects $obj
set_property -name "dsa.platform_state" -value "pre_synth" -objects $obj
set_property -name "dsa.uses_pr" -value "1" -objects $obj
set_property -name "dsa.vendor" -value "xilinx" -objects $obj
set_property -name "dsa.version" -value "0.0" -objects $obj
set_property -name "enable_vhdl_2008" -value "1" -objects $obj
set_property -name "ip_cache_permissions" -value "read write" -objects $obj
set_property -name "ip_output_repo" -value "$proj_dir/${_xil_proj_name_}.cache/ip" -objects $obj
set_property -name "mem.enable_memory_map_generation" -value "1" -objects $obj
set_property -name "part" -value "xc7a200tfbg484-2" -objects $obj
set_property -name "sim.central_dir" -value "$proj_dir/${_xil_proj_name_}.ip_user_files" -objects $obj
set_property -name "sim.ip.auto_export_scripts" -value "1" -objects $obj
set_property -name "simulator_language" -value "Mixed" -objects $obj

# add source files
set obj [get_filesets sources_1]
set src_list {}
lappend src_list "$vproc_dir/sim/vproc_tb.sv"
foreach file {
    vproc_top.sv vproc_pkg.sv vproc_core.sv vproc_decoder.sv vproc_lsu.sv vproc_alu.sv
    vproc_mul.sv vproc_mul_block.sv vproc_sld.sv vproc_elem.sv vproc_hazards.sv vproc_vregfile.sv
    vproc_vregpack.sv vproc_vregunpack.sv vproc_queue.sv vproc_cache.sv
} {
    lappend src_list "$vproc_dir/rtl/$file"
}
set main_core ""
if {[string first "ibex" $core_dir] != -1} {
    set main_core "ibex"
    foreach file {ibex_pkg.sv ibex_top.sv ibex_core.sv ibex_alu.sv ibex_branch_predict.sv
                  ibex_compressed_decoder.sv ibex_controller.sv ibex_counter.sv
                  ibex_cs_registers.sv ibex_csr.sv ibex_decoder.sv ibex_dummy_instr.sv
                  ibex_ex_block.sv ibex_fetch_fifo.sv ibex_icache.sv ibex_id_stage.sv
                  ibex_if_stage.sv ibex_load_store_unit.sv ibex_lockstep.sv
                  ibex_multdiv_fast.sv ibex_multdiv_slow.sv ibex_pmp.sv ibex_prefetch_buffer.sv
                  ibex_register_file_ff.sv ibex_register_file_fpga.sv ibex_wb_stage.sv
                  ibex_tracer_pkg.sv ibex_tracer.sv} {
        lappend src_list "$core_dir/rtl/$file"
    }
    lappend src_list "$core_dir/syn/rtl/prim_clock_gating.v"
    lappend src_list "$core_dir/vendor/lowrisc_ip/dv/sv/dv_utils/"
    lappend src_list "$core_dir/vendor/lowrisc_ip/ip/prim/rtl/"
}
add_files -fileset $obj -norecurse -scan_for_includes $src_list

# configure simulation
set_property top vproc_tb [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]
set_property generic "MAIN_CORE=\"$main_core\" $prog_paths_var $params_var" -objects [get_filesets sim_1]

launch_simulation

set log_signals [get_objects -r [lrange $argv 5 end]]
add_wave $log_signals

set complete_signal "done"
add_wave $complete_signal

set outf [open $log_file_path "w"]
puts "logging following signals to $log_file_path: $log_signals"

foreach sig $log_signals {
    set sig_name_start [string wordstart $sig end]
    puts -nonewline $outf "[string range $sig $sig_name_start end];"
}
puts $outf ""

# restart the simulation
restart

for {set step 0} 1 {incr step} {
    # log the value of each signal
    foreach sig $log_signals {
        puts -nonewline $outf "[get_value $sig];"
    }
    puts $outf ""

    # advance by 1 clock cycle
    run 10 ns

    # check if the abort condition has been met
    if {[get_value [lindex $complete_signal 0]] != 0} {
        puts "exit condition met after $step clock cycles"
        break
    }
}
close $outf
close_sim -force