/* =============================================================================
   sections.lds — Linker Script cho picorv32 SoC
   -----------------------------------------------------------------------------
   ROM : 0x0000_0000 - 0x0000_1FFF (8KB) — code + rodata + data init values
   RAM : 0x0001_0000 - 0x0001_0FFF (4KB) — data + bss + stack
   ============================================================================= */

MEMORY
{
    ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 8K
    RAM (rwx) : ORIGIN = 0x00010000, LENGTH = 4K
}

/* Stack top = cuối RAM */
_stack_top = ORIGIN(RAM) + LENGTH(RAM);  /* = 0x00011000 */

SECTIONS
{
    /* -------------------------------------------------------------------------
       .vectors — Fix cứng tại 0x0
       KEEP để linker không optimize bỏ dù không có reference trực tiếp
       ------------------------------------------------------------------------- */
    .vectors 0x00000000 :
    {
        KEEP(*(.vectors))
    } > ROM

    /* -------------------------------------------------------------------------
       .text — Code
       ------------------------------------------------------------------------- */
    .text :
    {
        *(.text*)
    } > ROM

    /* -------------------------------------------------------------------------
       .rodata — Hằng số, string literal
       ------------------------------------------------------------------------- */
    .rodata :
    {
        *(.rodata*)
        . = ALIGN(4); 
    } > ROM

    /* -------------------------------------------------------------------------
       .data — Initialized global variables
       VMA: RAM (địa chỉ runtime)
       LMA: ROM (giá trị khởi tạo lưu trong ROM, copy sang RAM lúc boot)
       ------------------------------------------------------------------------- */
    .data :
    {
        _data_start = .;
        *(.data*)
        *(.sdata*)
        _data_end = .;
    } > RAM AT > ROM

    /* LMA của .data trong ROM — dùng trong start.s để copy */
    _data_lma = LOADADDR(.data);

    /* -------------------------------------------------------------------------
       .bss — Uninitialized global variables
       Không chiếm space trong ROM, start.s sẽ zero out vùng này
       ------------------------------------------------------------------------- */
    .bss :
    {
        _bss_start = .;
        *(.bss*)
        *(.sbss*)
        *(COMMON)
        _bss_end = .;
    } > RAM

    /* -------------------------------------------------------------------------
       Kiểm tra overflow
       ------------------------------------------------------------------------- */
    ASSERT(SIZEOF(.vectors) + SIZEOF(.text) + SIZEOF(.rodata) + SIZEOF(.data) <= LENGTH(ROM),
           "ERROR: ROM overflow — firmware vượt quá 8KB")

    ASSERT(_bss_end <= _stack_top,
           "ERROR: RAM overflow — data+bss chạm stack")
}
