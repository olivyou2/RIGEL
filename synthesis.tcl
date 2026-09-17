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

synth_design -top mesh_router -part xc7k480tffg1156-2
report_utilization
report_timing -from [all_registers] -to [all_registers] -max_paths 5