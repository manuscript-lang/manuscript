/* The operand and result type rules of each MIR instruction. Every op has one rule, in one of the three
 * mir_verify_types_*.c files; a rule returns NULL when the instruction is well formed and the reason otherwise. */
#include <stdarg.h>

#include "base/message.h"
#include "compiler/mir/mir_verify_types.h"

/* `format` (ms_message_format conversions) as a NUL-terminated C string in `arena`. */
const char *mvt_fmt_(MsArena *arena, const char *format, ...) {
  va_list arguments;
  va_start(arguments, format);
  MsSpan text = ms_message_vformat(arena, format, arguments);
  va_end(arguments);
  uint8_t *copy = ms_arena_alloc(arena, text.len + 1, 1);
  __builtin_memcpy(copy, text.ptr, text.len);
  copy[text.len] = 0;
  return (const char *)copy;
}


MsSpan mir_verify_inst_types(const MirVerifyCx *cx, const MirInst *in) {
  MvtCx c = {.v = cx,
             .m = cx->m,
             .f = cx->f,
             .in = in,
             .n = in->nargs,
             .has_res = in->res != MIR_NONE,
             .res = in->res != MIR_NONE ? cx->f->values.ptr[in->res] : 0};
  MvtRule rule = mvt_rules_core[in->op];
  rule = rule != NULL ? rule : mvt_rules_data[in->op];
  rule = rule != NULL ? rule : mvt_rules_ops[in->op];
  const char *why = rule(&c);
  return why == NULL ? ms_span_of(NULL, 0) : ms_span_of_text(why);
}
