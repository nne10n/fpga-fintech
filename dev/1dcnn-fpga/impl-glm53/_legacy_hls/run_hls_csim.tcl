# Vitis HLS csim script (requires Vitis HLS installed)
open_project cnn_1d_hls -reset
set_top cnn_engine
add_files cnn_engine.cpp
add_files -tb cnn_engine_tb.cpp
open_solution sol1 -reset
set_part {xc7z020clg400-1}
create_clock -period 10 -name default
csim_design -argv {..}
# Uncomment when running on a machine with Vitis HLS:
# csynth_design
# cosim_design
exit
