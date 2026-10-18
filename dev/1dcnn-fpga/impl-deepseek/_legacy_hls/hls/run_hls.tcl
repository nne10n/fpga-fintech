# Vitis HLS project script (run when vitis_hls available)
#   vitis_hls -f run_hls.tcl
open_project cnn_1dcnn_hls -reset
set_top cnn_engine_infer
add_files cnn_engine.cpp
add_files cnn_engine.h
add_files cnn_params.h
add_files -tb ../tb/csim_main.cpp
open_solution sol_xc7z020 -reset
set_part {xc7z020clg400-1}
create_clock -period 6.67 -name default
# 150 MHz target; also try 10.0 for 100 MHz
csim_design -O
csynth_design
# cosim_design -O
export_design -format ip_catalog -description "1D-CNN INT16 V1"
exit
