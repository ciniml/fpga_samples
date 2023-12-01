.PHONY: all clean ip

MODULES :=  append_crc.sv \
			remove_crc.sv \
			crc_mac.sv \
			mii_mac_rx.sv \
			mii_mac_tx.sv \
			mii_mac.sv \
			../mii_axis/prepend_preamble.sv \
			../mii_axis/axis_to_mii.sv \
			../mii_axis/mii_to_axis.sv \
			../util/simple_fifo.v

all: ip

clean: 
	-@$(RM) component.xml
	-@$(RM) -rf xgui

ip: component.xml

component.xml xgui: $(MODULES) package_ip.tcl
	vivado -mode batch -source package_ip.tcl
