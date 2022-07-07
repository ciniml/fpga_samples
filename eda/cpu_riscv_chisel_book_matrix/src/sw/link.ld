OUTPUT_ARCH( "riscv" )
ENTRY(_start)

MEMORY
{
    imem(rx)  : ORIGIN = 0x08000000, LENGTH = 2048
    dmem(rwx) : ORIGIN = 0x20000000, LENGTH = 512 
}

SECTIONS
{
  .isr_vector : {
      . = ALIGN(4);
      KEEP(*(.isr_vector))
      . = ALIGN(4);
  } >imem
  .text : { 
      . = ALIGN(4);
      *(.text) 
      . = ALIGN(4);
  } >imem
  .rodata : { 
      . = ALIGN(4);
      *(.rodata) 
      . = ALIGN(4);
  } >imem
  .data : {
      PROVIDE(_data_start = .);
      PROVIDE(_data_rom_start = LOADADDR(.data));
      . = ALIGN(4);
      *(.sdata .sdata.* .data .data.*)
      . = ALIGN(4);
      PROVIDE(_data_end = .);
  } >dmem AT>imem
  .bss : { 
      PROVIDE(_bss_start = .);
      *(.sbss .sbss.* .bss .bss.*) 
      . = ALIGN(4);
      PROVIDE(_bss_end = .);
  } >dmem
  PROVIDE(stack_bottom = .);
  PROVIDE(_end = .);
  PROVIDE(end = .);
  PROVIDE(ramend = ORIGIN(dmem) + LENGTH(dmem));
}
