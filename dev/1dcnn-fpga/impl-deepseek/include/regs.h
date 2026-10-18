/**
 * regs.h — AXI-Lite register map for system_1dcnn_pl
 * Matches Phase1 arch §5.3 offsets/bitfields and microarch §8 ERR codes.
 * Doc mnemonic REG_ID=0x1DCN0101 encoded as 0x1DC00101 (N→0, valid hex).
 * rst_n active-low.
 */
#ifndef REGS_H_
#define REGS_H_

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/** Doc spells 0x1DCN0101; C/Verilog hex uses N→0 → 0x1DC00101 */
#define REG_ID_MAGIC            0x1DC00101u

#define REG_ID                  0x000u
#define REG_CTRL                0x004u
#define REG_STATUS              0x008u
#define REG_IER                 0x00Cu
#define REG_WIN_LEN             0x010u
#define REG_WIN_HOP             0x014u
#define REG_FS_SEL              0x018u
#define REG_CH_SEL              0x01Cu
#define REG_WEIGHT_BASE         0x020u
#define REG_WEIGHT_WORDS        0x024u
#define REG_WEIGHT_CTRL         0x028u
#define REG_WEIGHT_DATA         0x02Cu
#define REG_CYC_CNT             0x030u
#define REG_WIN_CNT             0x034u
#define REG_ERR_CODE            0x038u
#define REG_IRQ_STATUS          0x03Cu
#define REG_SCORE_BASE          0x040u
#define REG_WEIGHT_BASE_B       0x044u
#define REG_NET_PROFILE         0x048u
#define REG_ENGINE_MASK         0x04Cu
#define REG_RSVD_050            0x050u
#define REG_RSVD_054            0x054u
#define REG_RSVD_058            0x058u
#define REG_RSVD_05C            0x05Cu
#define REG_RSVD_060            0x060u
#define REG_RSVD_064            0x064u
#define REG_RSVD_068            0x068u
#define REG_RSVD_06C            0x06Cu
#define REG_RSVD_070            0x070u
#define REG_RSVD_074            0x074u
#define REG_RSVD_078            0x078u
#define REG_RSVD_07C            0x07Cu
#define REG_SCORE0              0x080u
#define REG_SCORE1              0x084u
#define REG_SCORE2              0x088u
#define REG_SCORE3              0x08Cu
#define REG_SCORE4              0x090u
#define REG_SCORE5              0x094u
#define REG_SCORE6              0x098u
#define REG_SCORE7              0x09Cu
#define REG_SCORE8              0x0A0u
#define REG_SCORE9              0x0A4u

#define REG_SCORE(i)            (REG_SCORE0 + ((uint32_t)(i) * 4u))

#define CTRL_ENG_EN             (1u << 0)
#define CTRL_CAPT_EN            (1u << 1)
#define CTRL_SOFT_RST           (1u << 2)
#define CTRL_FIR_BYPASS         (1u << 3)
#define CTRL_IRQ_EN             (1u << 4)
#define CTRL_WEIGHT_LOAD_KICK   (1u << 8)

#define STATUS_BUSY             (1u << 0)
#define STATUS_DONE_STICKY      (1u << 1)
#define STATUS_ERR_STICKY       (1u << 2)
#define STATUS_FIFO_OVFL        (1u << 3)
#define STATUS_WEIGHT_OK        (1u << 4)
#define STATUS_FEAT_HOTSWAP     (1u << 5)  /* RO, V1 = 0 */

#define WCTRL_LOAD_EN           (1u << 0)
#define WCTRL_BANK_SEL          (1u << 1)
#define WCTRL_BANK_ACTIVE       (1u << 2)

#define ERR_NONE                0x00u
#define ERR_WIN_PARAM           0x01u
#define ERR_WIN_OVFL            0x02u
#define ERR_WEIGHT_NOT_RDY      0x10u
#define ERR_COMPUTE_SAT         0x11u
#define ERR_HOTSWAP_UNIMPL      0x20u
#define ERR_ADC_FIFO_OVFL       0x30u

#define WIN_LEN_DEFAULT         2048u
#define WIN_HOP_DEFAULT         2048u
#define N_CLASS                 10
#define PACK_CH_DEFAULT         0

#ifdef __cplusplus
}
#endif

#endif /* REGS_H_ */
