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

set sv_files [find_files ./src {*.sv}]

read_verilog -sv $sv_files

synth_design -top arbitation -part xc7k480tffg1156-2
report_utilization
report_timing -max_paths 1