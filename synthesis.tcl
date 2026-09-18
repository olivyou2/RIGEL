proc find_files {base_dir patterns} {
    set files {}
    foreach f [glob -nocomplain -directory $base_dir *] {
        if {[file isdirectory $f]} {
            set files [concat $files [find_files $f $patterns]]
        } else {
            foreach p $patterns {
                if {[string match $p [file tail $f]]} {
                    lappend files $f
                    break
                }
            }
        }
    }
    return $files
}

set interface_file ./src/interfaces/rv_if.sv
set sv_files [list $interface_file]
foreach f [find_files ./src {*.sv}] {
    if {$f ne $interface_file} { lappend sv_files $f }
}

read_verilog -sv $sv_files

synth_design -top compute -part xc7k480tffg1156-2

# 200 MHz system clock (5.000 ns period).
create_clock -name sys_clk -period 5.000 [get_ports clk]

file mkdir reports

# Optimize and place the synthesized netlist. phys_opt_design is still a
# post-place step; routing delay in these reports is estimated, not final.
opt_design
place_design
phys_opt_design

report_utilization -file reports/post_place_utilization.rpt
report_utilization \
    -hierarchical \
    -hierarchical_depth 10 \
    -file reports/post_place_hierarchical_utilization.rpt
report_timing_summary \
    -delay_type min_max \
    -max_paths 20 \
    -report_unconstrained \
    -file reports/post_place_timing_summary.rpt
report_timing \
    -delay_type max \
    -sort_by slack \
    -max_paths 20 \
    -nworst 1 \
    -file reports/post_place_timing.rpt

write_checkpoint -force reports/compute_post_place.dcp
