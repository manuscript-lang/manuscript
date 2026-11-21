/* runtime/core/unicode_tables.h: the generated Unicode 17.0.0 tables behind case mapping and normalization
 * (unicode_norm_*.c, unicode_case_tables.c). The readers are in ucd.h. */
#ifndef MS_RUNTIME_CORE_UNICODE_TABLES_H
#define MS_RUNTIME_CORE_UNICODE_TABLES_H

#include <stdint.h>

#define MS_UCD_VERSION "17.0.0"
#define MS_UCD_MID_BITS 9
#define MS_UCD_LEAF_BITS 4
#define MS_UCD_COMP_COUNT 961

extern const uint8_t ms_ucd_norm_top[2176];
extern const uint16_t ms_ucd_norm_mid[2400];
extern const uint16_t ms_ucd_norm_leaf[10224];
extern const uint16_t ms_ucd_norm_record[11679];
extern const uint16_t ms_ucd_pool[6992];
extern const uint64_t ms_ucd_comp_key[961];
extern const uint32_t ms_ucd_comp_value[961];
extern const uint8_t ms_ucd_case_top[2176];
extern const uint16_t ms_ucd_case_mid[2080];
extern const uint16_t ms_ucd_case_leaf[5264];
extern const int32_t ms_ucd_case_record[855];
extern const uint16_t ms_ucd_case_pool[160];

#endif
