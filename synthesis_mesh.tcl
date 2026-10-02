# Run: vivado -mode batch -source synthesis_mesh.tcl -tclargs 5.0 xc7k480tffg1156-2
# This is a core/interface timing run; board pin and host timing constraints
# must be supplied by the board project before producing a deployment bitstream.
set root [file dirname [file normalize [info script]]]
set period 5.0
set part xc7k480tffg1156-2
set top rigel_mesh_top
if {[llength $argv] > 0} { set period [lindex $argv 0] }
if {[llength $argv] > 1} { set part [lindex $argv 1] }
if {[llength $argv] > 2} { set top [lindex $argv 2] }
if {$top ni {rigel_mesh_top rigel_axi_scheduled_top rigel_axi_managed_top}} { error "Unsupported synthesis top" }
if {![string is double -strict $period] || $period <= 0} { error "Clock period must be positive" }
set fd [open [file join $root src system files.f] r]
set files {}
foreach line [split [read $fd] "\n"] {
    if {[string trim $line] ne ""} { lappend files [file join $root [string trim $line]] }
}
close $fd
read_verilog -sv $files
synth_design -top $top -part $part -flatten_hierarchy rebuilt
create_clock -name sys_clk -period $period [get_ports clk]
# External interfaces meet a registered integration boundary. A 20% period
# budget models host-side timing for comparison; replace with actual board IO.
set host_inputs [get_ports -filter {DIRECTION == IN && NAME != clk && NAME != rst_n}]
set host_outputs [get_ports -filter {DIRECTION == OUT}]
set_input_delay -clock sys_clk -max [expr {$period*0.2}] $host_inputs
set_input_delay -clock sys_clk -min 0.0 $host_inputs
set_output_delay -clock sys_clk -max [expr {$period*0.2}] $host_outputs
set_output_delay -clock sys_clk -min 0.0 $host_outputs
# Synchronous reset is timed; no blanket false-path exceptions.
set_input_delay -clock sys_clk -max [expr {$period*0.2}] [get_ports rst_n]
set_input_delay -clock sys_clk -min 0.0 [get_ports rst_n]
set report_dir [file join $root reports mesh]
if {$top ne "rigel_mesh_top"} { set report_dir [file join $report_dir $top] }
file mkdir $report_dir
report_utilization -hierarchical -file [file join $report_dir post_synth_utilization.rpt]
opt_design
place_design
phys_opt_design
route_design
report_utilization -hierarchical -file [file join $report_dir post_route_utilization.rpt]
report_timing_summary -delay_type min_max -max_paths 30 -report_unconstrained \
    -file [file join $report_dir post_route_timing_summary.rpt]
report_timing -delay_type max -max_paths 30 -nworst 1 \
    -file [file join $report_dir post_route_timing.rpt]
report_timing -from [all_registers -clock sys_clk] -to [all_registers -clock sys_clk] \
    -delay_type max -max_paths 30 -nworst 1 \
    -file [file join $report_dir post_route_internal_timing.rpt]
report_drc -file [file join $report_dir post_route_drc.rpt]
write_checkpoint -force [file join $report_dir rigel_mesh_post_route.dcp]
