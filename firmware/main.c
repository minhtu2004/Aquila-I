// =============================================================================
// main.c — Final SoC regression firmware
// Target: PicoRV32 SoC + APB peripherals + DMA + CRC + AES
//
// Philosophy:
//   - Minimal UART log to avoid simulation timeout.
//   - Main pass/fail is exported through global variables in RAM.
//   - Use `riscv64-unknown-elf-nm -n firmware/firmware.elf` to locate globals
//     and let tb_soc.v read them directly.
//
// Final PASS:
//   global_zero = 0x0000AAAA
// =============================================================================

#define UART_DATA     (*((volatile unsigned int *)0x40000000))
#define UART_STATUS   (*((volatile unsigned int *)0x40000004))
#define UART_PRESCALE (*((volatile unsigned int *)0x4000000C))

#define TIMER_VAL     (*((volatile unsigned int *)0x40001000))
#define TIMER_LOAD    (*((volatile unsigned int *)0x40001004))
#define TIMER_CTRL    (*((volatile unsigned int *)0x4000100C))
#define TIMER_IRQSTS  (*((volatile unsigned int *)0x40001010))
#define TIMER_INTCLR  (*((volatile unsigned int *)0x40001014))

#define SPI_TX        (*((volatile unsigned int *)0x40002000))
#define SPI_RX        (*((volatile unsigned int *)0x40002004))
#define SPI_CFG       (*((volatile unsigned int *)0x40002008))
#define SPI_STS       (*((volatile unsigned int *)0x4000200C))
#define SPI_INTEN     (*((volatile unsigned int *)0x40002010))
#define SPI_INTSTS    (*((volatile unsigned int *)0x40002014))

#define I2C_CTRL      (*((volatile unsigned int *)0x40003000))
#define I2C_ADDR      (*((volatile unsigned int *)0x40003004))
#define I2C_PRESCALE  (*((volatile unsigned int *)0x40003008))
#define I2C_TX_DATA   (*((volatile unsigned int *)0x4000300C))
#define I2C_RX_DATA   (*((volatile unsigned int *)0x40003010))
#define I2C_STATUS    (*((volatile unsigned int *)0x40003014))
#define I2C_INT_EN    (*((volatile unsigned int *)0x40003018))
#define I2C_INT_STS   (*((volatile unsigned int *)0x4000301C))

#define IRQ_PENDING   (*((volatile unsigned int *)0x40004000))
#define IRQ_MASK      (*((volatile unsigned int *)0x40004004))
#define IRQ_RAW       (*((volatile unsigned int *)0x40004008))
#define IRQ_FORCE     (*((volatile unsigned int *)0x4000400C))
#define IRQ_STATUS    (*((volatile unsigned int *)0x40004010))

#define DMA_SRC       (*((volatile unsigned int *)0x40005000))
#define DMA_DST       (*((volatile unsigned int *)0x40005004))
#define DMA_LEN       (*((volatile unsigned int *)0x40005008))
#define DMA_MODE      (*((volatile unsigned int *)0x4000500C))
#define DMA_CTRL      (*((volatile unsigned int *)0x40005010))
#define DMA_STATUS    (*((volatile unsigned int *)0x40005014))
#define DMA_ERROR     (*((volatile unsigned int *)0x40005018))

#define CRC_STATUS    (*((volatile unsigned int *)0x40006000))
#define CRC_RESULT    (*((volatile unsigned int *)0x40006004))
#define CRC_ACK       (*((volatile unsigned int *)0x40006008))

#define AES_KEY0      (*((volatile unsigned int *)0x40007000))
#define AES_KEY1      (*((volatile unsigned int *)0x40007004))
#define AES_KEY2      (*((volatile unsigned int *)0x40007008))
#define AES_KEY3      (*((volatile unsigned int *)0x4000700C))
#define AES_STATUS    (*((volatile unsigned int *)0x40007010))
#define AES_CTRL      (*((volatile unsigned int *)0x40007014))

#define ENABLE_UART_LOG 1

#define DMA_MODE_MEM_MEM   0u
#define DMA_MODE_MEM_CRC   1u
#define DMA_MODE_CRC_MEM   2u
#define DMA_MODE_AES_ENC   3u

#define DMA_CTRL_START     1u
#define DMA_CTRL_CLEAR     (1u << 1)

#define DMA_STATUS_BUSY    (1u << 0)
#define DMA_STATUS_DONE    (1u << 1)
#define DMA_STATUS_ERROR   (1u << 2)

#define IRQ_BIT_UART       (1u << 0)
#define IRQ_BIT_TIMER      (1u << 1)
#define IRQ_BIT_SPI        (1u << 2)
#define IRQ_BIT_I2C        (1u << 3)
#define IRQ_BIT_DMA        (1u << 4)

// RAM test regions. Keep inside 0x00010000..0x00011FFF.
#define DMA_SRC_ADDR       0x00010100u
#define DMA_DST_ADDR       0x00010200u
#define CRC_SRC_ADDR       0x00010300u
#define CRC_RES_ADDR       0x00010400u
#define DMA_IRQ_DST_ADDR   0x00010500u
#define AES_SRC_ADDR       0x00010600u
#define AES_DST_ADDR       0x00010700u
#define AES_DEC_ADDR       0x00010680u

#define AES_CTRL_ENC       0u
#define AES_CTRL_DEC       1u

#define CRC_EXPECTED       0xAF05D4EFu
#define PASS_ALL           0x0000AAAAu

#define STAGE_BOOT         0x00000001u
#define STAGE_TIMER        0x00000010u
#define STAGE_SPI          0x00000020u
#define STAGE_I2C          0x00000030u
#define STAGE_TIMER_IRQ    0x00000040u
#define STAGE_DMA_MEM      0x00000050u
#define STAGE_DMA_CRC      0x00000060u
#define STAGE_DMA_AES      0x00000070u
#define STAGE_DMA_IRQ      0x00000080u
#define STAGE_DMA_ERR      0x00000090u
#define STAGE_DONE         0x000000FFu

// Globals exported for tb_soc.v / nm
volatile unsigned int global_zero       = 3;
volatile unsigned int global_init       = 42;
volatile unsigned int test_stage        = 0;
volatile unsigned int fail_code         = 0;
volatile unsigned int irq_flag          = 0;
volatile unsigned int irq_seen_count    = 0;
volatile unsigned int timer_result      = 0;
volatile unsigned int spi_result        = 0;
volatile unsigned int i2c_result        = 0;
volatile unsigned int timer_irq_result  = 0;
volatile unsigned int dma_result        = 0;
volatile unsigned int crc_test_result   = 0;
volatile unsigned int aes_test_result   = 0;
volatile unsigned int irq_test_result   = 0;
volatile unsigned int err_test_result   = 0;
volatile unsigned int dbg_dma_status    = 0;
volatile unsigned int dbg_dma_error     = 0;
volatile unsigned int dbg_crc_apb       = 0;
volatile unsigned int dbg_crc_ram       = 0;
volatile unsigned int dbg_aes_status    = 0;
volatile unsigned int dbg_irq_pending   = 0;
volatile unsigned int dbg_irq_mask      = 0;
volatile unsigned int dbg_spi_rx        = 0;
volatile unsigned int dbg_i2c_sts       = 0;
volatile unsigned int aes_ct0           = 0;
volatile unsigned int aes_ct1           = 0;
volatile unsigned int aes_ct2           = 0;
volatile unsigned int aes_ct3           = 0;
volatile unsigned int aes_ct4           = 0;
volatile unsigned int aes_ct5           = 0;
volatile unsigned int aes_ct6           = 0;
volatile unsigned int aes_ct7           = 0;

void uart_putchar(char c) {
#if ENABLE_UART_LOG
    while (!(UART_STATUS & 0x2));
    UART_DATA = (unsigned int)c;
#else
    (void)c;
#endif
}

void print(const char *s) {
#if ENABLE_UART_LOG
    while (*s) uart_putchar(*s++);
#else
    (void)s;
#endif
}

static void print_hex32(unsigned int val) {
#if ENABLE_UART_LOG
    uart_putchar('0'); uart_putchar('x');
    for (int i = 28; i >= 0; i -= 4) {
        unsigned int n = (val >> i) & 0xF;
        uart_putchar(n < 10 ? '0' + n : 'A' + n - 10);
    }
    uart_putchar('\r'); uart_putchar('\n');
#else
    (void)val;
#endif
}

static inline void cpu_irq_enable(void) {
    __asm__ volatile (".word 0x0600000B\n");
}

static void fail(unsigned int code) {
    fail_code   = code;
    global_zero = code;
}

void irq_dispatch(void) {
    unsigned int pending = IRQ_PENDING;
    unsigned int mask    = IRQ_MASK;
    unsigned int active  = pending & mask;

    dbg_irq_pending = pending;
    dbg_irq_mask    = mask;

    if (!active) return;

    irq_flag = active;
    irq_seen_count++;
    IRQ_PENDING = active;
    IRQ_MASK    = 0x0;
}

static int wait_dma_done_or_error(unsigned int timeout) {
    while (timeout > 0) {
        unsigned int st = DMA_STATUS;
        if (st & (DMA_STATUS_DONE | DMA_STATUS_ERROR)) {
            dbg_dma_status = st;
            dbg_dma_error  = DMA_ERROR;
            return 1;
        }
        timeout--;
    }
    dbg_dma_status = DMA_STATUS;
    dbg_dma_error  = DMA_ERROR;
    return 0;
}

static void dma_clear(void) {
    DMA_CTRL = DMA_CTRL_CLEAR;
    for (volatile int i = 0; i < 16; i++);
}
///*
void test_timer(void) {
    test_stage = STAGE_TIMER;
    TIMER_CTRL   = 0x0;
    TIMER_INTCLR = 0x1;
    TIMER_LOAD   = 1000;
    TIMER_CTRL   = 0x7;

    unsigned int timeout = 200000;
    while (!(TIMER_IRQSTS & 0x1) && --timeout);
    if (!timeout) { timer_result = 2; fail(0x1001); return; }
    TIMER_INTCLR = 0x1;

    timeout = 200000;
    while (!(TIMER_IRQSTS & 0x1) && --timeout);
    if (!timeout) { timer_result = 2; fail(0x1002); return; }
    TIMER_INTCLR = 0x1;

    TIMER_CTRL = 0x0;
    timer_result = 1;
    print("TIMER PASS\r\n");
}

void test_spi(void) {
    test_stage = STAGE_SPI;
    SPI_CFG   = 0x00000400;
    SPI_INTEN = 0x2;
    SPI_TX    = 0xA5;

    unsigned int timeout = 200000;
    while (!(SPI_INTSTS & 0x2) && --timeout);
    if (!timeout) { spi_result = 2; fail(0x2001); return; }

    unsigned int rx = SPI_RX;
    dbg_spi_rx = rx;

    SPI_INTSTS = 0x3;
    SPI_INTEN  = 0x0;
    SPI_CFG    = 0x00010400;

    if ((rx & 0xFF) != 0xA5) { spi_result = 2; fail(0x2002); return; }

    spi_result = 1;
    print("SPI PASS\r\n");
}

void test_i2c(void) {
    test_stage = STAGE_I2C;
    I2C_PRESCALE = 20;
    I2C_ADDR     = 0x50;
    I2C_INT_EN   = 0x7;
    I2C_TX_DATA  = 0xAA;
    I2C_CTRL     = 0x29;

    unsigned int timeout = 300000;
    while (!(I2C_INT_STS & 0x5) && --timeout);
    if (!timeout) { i2c_result = 2; fail(0x3001); return; }

    unsigned int sts = I2C_INT_STS;
    dbg_i2c_sts = sts;

    I2C_INT_STS = 0x7;
    I2C_INT_EN  = 0x0;

    if (sts & 0x4) { i2c_result = 1; print("I2C NACK\r\n"); return; }
    if (sts & 0x1) { i2c_result = 1; print("I2C PASS\r\n"); return; }

    i2c_result = 2;
    fail(0x3002);
}

void test_timer_irq(void) {
    test_stage = STAGE_TIMER_IRQ;
    IRQ_MASK     = 0x0;
    IRQ_PENDING  = 0xFFFFFFFF;
    irq_flag     = 0;

    TIMER_CTRL   = 0x0;
    TIMER_INTCLR = 0x1;
    TIMER_LOAD   = 500;
    TIMER_INTCLR = 0x1;
    TIMER_CTRL   = 0x5;

    unsigned int timeout = 300000;
    while (!(IRQ_PENDING & IRQ_BIT_TIMER) && --timeout);
    if (!timeout) { timer_irq_result = 2; fail(0x4001); return; }

    TIMER_CTRL   = 0x0;
    TIMER_INTCLR = 0x1;
    IRQ_MASK = IRQ_BIT_TIMER;

    timeout = 300000;
    while (!irq_flag && --timeout);
    if (!timeout) { timer_irq_result = 2; fail(0x4002); return; }

    if (!(irq_flag & IRQ_BIT_TIMER)) { timer_irq_result = 2; fail(0x4003); return; }

    IRQ_MASK    = 0x0;
    IRQ_PENDING = IRQ_BIT_TIMER;
    irq_flag    = 0;
    timer_irq_result = 1;
    print("TIRQ PASS\r\n");
}//*/
///*
void test_dma_memcpy(void) {
    test_stage = STAGE_DMA_MEM;
    volatile unsigned int *src = (volatile unsigned int *)DMA_SRC_ADDR;
    volatile unsigned int *dst = (volatile unsigned int *)DMA_DST_ADDR;

    for (unsigned int i = 0; i < 8; i++) src[i] = 0xA0000000u | i;
    for (unsigned int i = 0; i < 8; i++) dst[i] = 0xDEADDEADu;

    dma_clear();
    DMA_SRC  = DMA_SRC_ADDR;
    DMA_DST  = DMA_DST_ADDR;
    DMA_LEN  = 8;
    DMA_MODE = DMA_MODE_MEM_MEM;
    DMA_CTRL = DMA_CTRL_START;

    if (!wait_dma_done_or_error(500000)) { dma_result = 2; fail(0x5001); return; }
    if (DMA_STATUS & DMA_STATUS_ERROR)   { dma_result = 2; fail(0x5002); return; }

    for (unsigned int i = 0; i < 8; i++) {
        if (dst[i] != (0xA0000000u | i)) { dma_result = 2; fail(0x5010u + i); return; }
    }

    dma_result = 1;
    print("DMA MEM PASS\r\n");
}//*/
///*
void test_dma_crc(void) {
    test_stage = STAGE_DMA_CRC;
    volatile unsigned int *src = (volatile unsigned int *)CRC_SRC_ADDR;
    volatile unsigned int *res = (volatile unsigned int *)CRC_RES_ADDR;

    for (unsigned int i = 0; i < 4; i++) src[i] = i + 1;
    res[0] = 0xDEADDEADu;

    dma_clear();
    DMA_SRC  = CRC_SRC_ADDR;
    DMA_DST  = 0;
    DMA_LEN  = 4;
    DMA_MODE = DMA_MODE_MEM_CRC;
    DMA_CTRL = DMA_CTRL_START;

    if (!wait_dma_done_or_error(500000)) { crc_test_result = 2; fail(0x6001); return; }
    if (DMA_STATUS & DMA_STATUS_ERROR)   { crc_test_result = 2; fail(0x6002); return; }

    unsigned int timeout = 500000;
    while (!(CRC_STATUS & 0x1) && --timeout);
    if (!timeout) { crc_test_result = 2; fail(0x6003); return; }

    dbg_crc_apb = CRC_RESULT;

    dma_clear();
    DMA_DST  = CRC_RES_ADDR;
    DMA_LEN  = 1;
    DMA_MODE = DMA_MODE_CRC_MEM;
    DMA_CTRL = DMA_CTRL_START;

    if (!wait_dma_done_or_error(500000)) { crc_test_result = 2; fail(0x6004); return; }
    if (DMA_STATUS & DMA_STATUS_ERROR)   { crc_test_result = 2; fail(0x6005); return; }

    dbg_crc_ram = res[0];
    CRC_ACK = 1u;

    if (dbg_crc_apb != CRC_EXPECTED || dbg_crc_ram != CRC_EXPECTED) {
        crc_test_result = 2; fail(0x6006); return;
    }

    crc_test_result = 1;
    print("CRC PASS\r\n");
}//*/
///*
void test_dma_aes_2blocks(void) {
    test_stage = STAGE_DMA_AES;
    volatile unsigned int *src = (volatile unsigned int *)AES_SRC_ADDR;
    volatile unsigned int *dst = (volatile unsigned int *)AES_DST_ADDR;

    // NIST SP 800-38A ECB-AES128 test vector
    // Key = 2B7E151628AED2A6ABF7158809CF4F3C

    // Plaintext block 1:
    // 6BC1BEE22E409F96E93D7E117393172A
    src[0] = 0x6BC1BEE2;
    src[1] = 0x2E409F96;
    src[2] = 0xE93D7E11;
    src[3] = 0x7393172A;

    // Plaintext block 2:
    // AE2D8A571E03AC9C9EB76FAC45AF8E51
    src[4] = 0xAE2D8A57;
    src[5] = 0x1E03AC9C;
    src[6] = 0x9EB76FAC;
    src[7] = 0x45AF8E51;

    for (unsigned int i = 0; i < 8; i++) dst[i] = 0xDEADDEADu;

    AES_KEY0 = 0x2B7E1516;
    AES_KEY1 = 0x28AED2A6;
    AES_KEY2 = 0xABF71588;
    AES_KEY3 = 0x09CF4F3C;
    dbg_aes_status = AES_STATUS;

    dma_clear();
    DMA_SRC  = AES_SRC_ADDR;
    DMA_DST  = AES_DST_ADDR;
    DMA_LEN  = 8;
    DMA_MODE = DMA_MODE_AES_ENC;
    DMA_CTRL = DMA_CTRL_START;

    if (!wait_dma_done_or_error(800000)) { aes_test_result = 2; fail(0x7001); return; }
    if (DMA_STATUS & DMA_STATUS_ERROR)   { aes_test_result = 2; fail(0x7002); return; }

    dbg_aes_status = AES_STATUS;
    aes_ct0 = dst[0]; aes_ct1 = dst[1]; aes_ct2 = dst[2]; aes_ct3 = dst[3];
    aes_ct4 = dst[4]; aes_ct5 = dst[5]; aes_ct6 = dst[6]; aes_ct7 = dst[7];

    // Expected ciphertext block 1:
    // 3AD77BB40D7A3660A89ECAF32466EF97
    if (dst[0] != 0x3AD77BB4u) { aes_test_result = 2; fail(0x7010); return; }
    if (dst[1] != 0x0D7A3660u) { aes_test_result = 2; fail(0x7011); return; }
    if (dst[2] != 0xA89ECAF3u) { aes_test_result = 2; fail(0x7012); return; }
    if (dst[3] != 0x2466EF97u) { aes_test_result = 2; fail(0x7013); return; }

    // Expected ciphertext block 2:
    // F5D3D58503B9699DE785895A96FDBAAF
    if (dst[4] != 0xF5D3D585u) { aes_test_result = 2; fail(0x7014); return; }
    if (dst[5] != 0x03B9699Du) { aes_test_result = 2; fail(0x7015); return; }
    if (dst[6] != 0xE785895Au) { aes_test_result = 2; fail(0x7016); return; }
    if (dst[7] != 0x96FDBAAFu) { aes_test_result = 2; fail(0x7017); return; }

    aes_test_result = 1;
    //print("AES PASS\r\n");
}//*/

///*
void test_dma_irq(void) {
    test_stage = STAGE_DMA_IRQ;
    volatile unsigned int *src = (volatile unsigned int *)DMA_SRC_ADDR;
    volatile unsigned int *dst = (volatile unsigned int *)DMA_IRQ_DST_ADDR;

    for (unsigned int i = 0; i < 4; i++) src[i] = 0xB0000000u | i;
    for (unsigned int i = 0; i < 4; i++) dst[i] = 0xDEADDEADu;

    IRQ_MASK    = 0x0;
    IRQ_PENDING = 0xFFFFFFFF;
    irq_flag    = 0;

    dma_clear();
    DMA_SRC  = DMA_SRC_ADDR;
    DMA_DST  = DMA_IRQ_DST_ADDR;
    DMA_LEN  = 4;
    DMA_MODE = DMA_MODE_MEM_MEM;

    IRQ_PENDING = 0xFFFFFFFF;
    IRQ_MASK    = IRQ_BIT_DMA;
    DMA_CTRL    = DMA_CTRL_START;

    unsigned int timeout = 800000;
    while (!irq_flag && --timeout);
    if (!timeout) { irq_test_result = 2; fail(0x8001); return; }

    IRQ_MASK    = 0x0;
    IRQ_PENDING = IRQ_BIT_DMA;

    if (!(irq_flag & IRQ_BIT_DMA)) { irq_test_result = 2; fail(0x8002); return; }
    if (!(DMA_STATUS & DMA_STATUS_DONE) || (DMA_STATUS & DMA_STATUS_ERROR)) {
        irq_test_result = 2; fail(0x8003); return;
    }

    for (unsigned int i = 0; i < 4; i++) {
        if (dst[i] != (0xB0000000u | i)) { irq_test_result = 2; fail(0x8010u + i); return; }
    }

    irq_test_result = 1;
    print("DIRQ PASS\r\n");
}

void test_dma_error_paths(void) {
    test_stage = STAGE_DMA_ERR;

    dma_clear();
    DMA_SRC  = DMA_SRC_ADDR;
    DMA_DST  = DMA_DST_ADDR;
    DMA_LEN  = 0;
    DMA_MODE = DMA_MODE_MEM_CRC;
    DMA_CTRL = DMA_CTRL_START;

    if (!wait_dma_done_or_error(500000)) { err_test_result = 2; fail(0x9001); return; }
    if (!(DMA_STATUS & DMA_STATUS_ERROR)) { err_test_result = 2; fail(0x9002); return; }
    if (DMA_ERROR != 0x31u) { err_test_result = 2; fail(0x9003); return; }

    dma_clear();
    DMA_SRC  = DMA_SRC_ADDR;
    DMA_DST  = DMA_DST_ADDR;
    DMA_LEN  = 3;
    DMA_MODE = DMA_MODE_AES_ENC;
    DMA_CTRL = DMA_CTRL_START;

    if (!wait_dma_done_or_error(500000)) { err_test_result = 2; fail(0x9011); return; }
    if (!(DMA_STATUS & DMA_STATUS_ERROR)) { err_test_result = 2; fail(0x9012); return; }
    if (DMA_ERROR != 0x32u) { err_test_result = 2; fail(0x9013); return; }

    err_test_result = 1;
    print("DERR PASS\r\n");
}//*/
///*
void test_dma_aes_dec_2blocks(void) {
    test_stage = STAGE_DMA_AES;

    volatile unsigned int *src = (volatile unsigned int *)AES_SRC_ADDR; // ciphertext input
    volatile unsigned int *dst = (volatile unsigned int *)AES_DST_ADDR; // plaintext output

    // NIST SP 800-38A ECB-AES128 test vector
    // Key = 2B7E151628AED2A6ABF7158809CF4F3C

    // Ciphertext block 1:
    // 3AD77BB40D7A3660A89ECAF32466EF97
    src[0] = 0x3AD77BB4u;
    src[1] = 0x0D7A3660u;
    src[2] = 0xA89ECAF3u;
    src[3] = 0x2466EF97u;

    // Ciphertext block 2:
    // F5D3D58503B9699DE785895A96FDBAAF
    src[4] = 0xF5D3D585u;
    src[5] = 0x03B9699Du;
    src[6] = 0xE785895Au;
    src[7] = 0x96FDBAAFu;

    for (unsigned int i = 0; i < 8; i++) dst[i] = 0xDEADDEADu;

    AES_KEY0 = 0x2B7E1516u;
    AES_KEY1 = 0x28AED2A6u;
    AES_KEY2 = 0xABF71588u;
    AES_KEY3 = 0x09CF4F3Cu;

    // chọn decrypt
    AES_CTRL = AES_CTRL_DEC;
    dbg_aes_status = AES_STATUS;

    dma_clear();
    DMA_SRC  = AES_SRC_ADDR;
    DMA_DST  = AES_DST_ADDR;
    DMA_LEN  = 8;
    DMA_MODE = DMA_MODE_AES_ENC;   // DMA mode cũ vẫn dùng cho AES process
    DMA_CTRL = DMA_CTRL_START;

    if (!wait_dma_done_or_error(1000000)) { aes_test_result = 2; fail(0x7101); return; }
    if (DMA_STATUS & DMA_STATUS_ERROR)    { aes_test_result = 2; fail(0x7102); return; }

    dbg_aes_status = AES_STATUS;

    // Lưu output plaintext vào biến debug cũ để testbench đọc được
    aes_ct0 = dst[0]; aes_ct1 = dst[1]; aes_ct2 = dst[2]; aes_ct3 = dst[3];
    aes_ct4 = dst[4]; aes_ct5 = dst[5]; aes_ct6 = dst[6]; aes_ct7 = dst[7];

    // Expected plaintext block 1:
    // 6BC1BEE22E409F96E93D7E117393172A
    if (dst[0] != 0x6BC1BEE2u) { aes_test_result = 2; fail(0x7110); return; }
    if (dst[1] != 0x2E409F96u) { aes_test_result = 2; fail(0x7111); return; }
    if (dst[2] != 0xE93D7E11u) { aes_test_result = 2; fail(0x7112); return; }
    if (dst[3] != 0x7393172Au) { aes_test_result = 2; fail(0x7113); return; }

    // Expected plaintext block 2:
    // AE2D8A571E03AC9C9EB76FAC45AF8E51
    if (dst[4] != 0xAE2D8A57u) { aes_test_result = 2; fail(0x7114); return; }
    if (dst[5] != 0x1E03AC9Cu) { aes_test_result = 2; fail(0x7115); return; }
    if (dst[6] != 0x9EB76FACu) { aes_test_result = 2; fail(0x7116); return; }
    if (dst[7] != 0x45AF8E51u) { aes_test_result = 2; fail(0x7117); return; }

    aes_test_result = 1;
    print("AES DEC PASS\r\n");
}//*/

int main(void) {
    global_zero = 3;
    fail_code   = 0;
    test_stage  = STAGE_BOOT;
    UART_PRESCALE = 108;
    cpu_irq_enable();

    print("SoC\n");

    test_timer();               if (timer_result     != 1) while (1);
    test_spi();                 if (spi_result       != 1) while (1);
    test_i2c();                 if (i2c_result       != 1) while (1);
    test_timer_irq();           if (timer_irq_result != 1) while (1);
    test_dma_memcpy();          if (dma_result       != 1) while (1);
    test_dma_crc();             if (crc_test_result  != 1) while (1);
    test_dma_aes_2blocks();     if (aes_test_result  != 1) while (1);
    test_dma_irq();             if (irq_test_result  != 1) while (1);
    test_dma_error_paths();     if (err_test_result  != 1) while (1);
    test_dma_aes_dec_2blocks(); if (aes_test_result  != 1) while (1);

    test_stage  = STAGE_DONE;
    fail_code   = 0;
    global_zero = PASS_ALL;

    //print("SoC ALL PASS\r\n");
    while (1);
}
