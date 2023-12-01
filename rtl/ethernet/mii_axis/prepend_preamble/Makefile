.PHONY: all clean ip

MODULES := ../mii_to_axis.sv

all: ip

clean: 
	-@$(RM) component.xml
	-@$(RM) -rf xgui

ip: component.xml

component.xml xgui: $(MODULES) package_ip.tcl
	vivado -mode batch -source package_ip.tcl
