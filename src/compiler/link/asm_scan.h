/* compiler/link/asm_scan.h: the first half of the asm tables step (asm_tables.h): read the assembly `llc` wrote
 * for the program, find each function and the source places `.loc` marks inside it, and write the assembly back
 * with a label at every place and at the end of every function. */
#ifndef MS_COMPILER_LINK_ASM_SCAN_H
#define MS_COMPILER_LINK_ASM_SCAN_H

#include "base/intern.h"
#include "base/strbuild.h"
#include "compiler/emit/emit_tables.h"
#include "compiler/mir/mir_tables.h"

typedef enum AsmFormat { ASM_ELF, ASM_MACHO, ASM_COFF } AsmFormat;

/* What was found of one module function. */
typedef struct AsmFunc {
  bool found;
  bool ended;
  bool fresh;       /* no instruction since the last range's label */
  uint32_t first;   /* its ranges are ranges.ptr[first .. first + count) */
  uint32_t count;
  MsSpan label;     /* the function's symbol exactly as the assembly spells it */
} AsmFunc;

MS_LIST_DEFINE(AsmRangeList, asm_range_list, MirCodeRange)
MS_LIST_DEFINE(AsmOrderList, asm_order_list, uint32_t)

typedef struct AsmScan {
  AsmFormat format;
  const MirModule *module;
  const EmitTableInfo *info;
  MsArena *arena;
  MsNames symbols;     /* the module's function symbols; an id maps to a function through `by_symbol` */
  uint32_t *by_symbol; /* per symbol id: function index + 1 */
  AsmFunc *funcs;      /* per module function */
  AsmRangeList ranges; /* off is the number of the range's label */
  AsmOrderList order;  /* the functions found, in the order the assembly lists them */
  uint32_t next_label;
  uint32_t current;    /* function index, or UINT32_MAX outside functions */
  bool skipping;       /* inside a COFF `.def @feat.00` block, which llc writes again */
  MsStrBuild out;
} AsmScan;

/* The label prefix that keeps a label out of the object's symbol table. */
const char *asm_local_prefix(AsmFormat format);

/* Starts a scan of `module`, whose functions were already renamed by emit_name_symbols. */
void asm_scan_init(AsmScan *scan, MsArena *arena, AsmFormat format, const MirModule *module,
                   const EmitTableInfo *info);
void asm_scan_free(AsmScan *scan);

/* Rewrites `text` into scan->out. False, with `why`, when a function is left open. */
bool asm_scan(AsmScan *scan, MsSpan text, MsStrBuild *why);

#endif
