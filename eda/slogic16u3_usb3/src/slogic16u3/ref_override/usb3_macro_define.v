// slogic16u3_usb3 REF=1: copy of the reference usb3_macro_define.v with EP1 IN/OUT at 4 KiB (BSRAM of the GW5AT-15)
`define SIM
`define getname(oriName,tmodule_name) \~oriName.tmodule_name
`define module_name USB30_Device_Controller_Top  

`define ENDPT0_IN
`define ENDPT0_IN_TYPE 		         2'b00
`define ENDPT0_IN_BURST  	         5'd1
`define ENDPT0_IN_TRANSFER_MAX_SIZE 16'd1024 
`define ENDPT0_IN_MEM_PP_NUM        'd1

`define ENDPT0_OUT      
`define ENDPT0_OUT_TYPE 	          2'b00
`define ENDPT0_OUT_BURST  	          5'd1
`define ENDPT0_OUT_TRANSFER_MAX_SIZE 16'd1024
`define ENDPT0_OUT_MEM_PP_NUM        'd1

`define ENDPT1_IN
`define ENDPT1_IN_TYPE 		         2'b10
`define ENDPT1_IN_BURST  	         5'd16
`define ENDPT1_IN_TRANSFER_MAX_SIZE (4*1024)
`define ENDPT1_IN_MEM_PP_NUM        'd2

`define ENDPT1_OUT
`define ENDPT1_OUT_TYPE 		         2'b10
`define ENDPT1_OUT_BURST  	            5'd16
`define ENDPT1_OUT_TRANSFER_MAX_SIZE   (4*1024)
`define ENDPT1_OUT_MEM_PP_NUM          'd2

`define ENDPT2_IN
`define ENDPT2_IN_TYPE 		         2'b11
`define ENDPT2_IN_BURST  	         5'd1
`define ENDPT2_IN_TRANSFER_MAX_SIZE (1*1024)
`define ENDPT2_IN_MEM_PP_NUM        'd2