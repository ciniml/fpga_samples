//Copyright (C)2014-2021 GOWIN Semiconductor Corporation.
//All rights reserved.
//File Title: Timing Constraints file
//GOWIN Version: 1.9.8 
//Created Time: 2021-08-24 07:16:20
create_clock -name clock -period 83.333 -waveform {0 41.666} [get_ports {clock}]
