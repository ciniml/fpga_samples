.PHONY: all clean ip

MODULES :=  ../mii_mac/append_crc.sv \
			../mii_mac/remove_crc.sv \
			../mii_mac/crc_mac.sv \
			../mii_mac/mii_mac_rx.sv \
			../mii_mac/mii_mac_tx.sv \
			./rmii_mac.sv \
			../mii_axis/prepend_preamble.sv \
			../mii_axis/axis_to_rmii.sv \
			../mii_axis/rmii_to_axis.sv \
			../util/simple_fifo.v

all: ip

clean: 
	-@$(RM) component.xml
	-@$(RM) -rf xgui

ip: component.xml

component.xml xgui: $(MODULES) package_ip.tcl
	vivado -mode batch -source package_ip.tcl
