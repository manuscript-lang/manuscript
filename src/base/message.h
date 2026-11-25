/* base/message.h: building diagnostic message texts in an arena from literal and computed parts.
 */
#ifndef MS_BASE_MESSAGE_H
#define MS_BASE_MESSAGE_H

#include <stdarg.h>

#include "base/arena.h"
#include "base/safe.h"
#include "base/strbuild.h"

/* The concatenation of `count` parts, copied into the arena. */
MsSpan ms_message_join(MsArena *arena, const MsSpan *parts, size_t count);

/* The text of the builder, copied into the arena. */
MsSpan ms_message_from_builder(MsArena *arena, const MsStrBuild *builder);

/* The same, then frees the builder. */
MsSpan ms_message_take_builder(MsArena *arena, MsStrBuild *builder);

/* `text` with its ASCII capitals lowered, copied into the arena. */
MsSpan ms_message_lowered(MsArena *arena, MsSpan text);

/* The text of `format` with each conversion replaced by its argument, copied into the arena. Conversions:
 * %s a C string, %S an MsSpan, %z a size_t, %u an unsigned int, %c a char, %% a percent sign.
 *
 * A %S argument reaches the formatter by address: a 16-byte struct passed through `...` is miscompiled by
 * clang on Windows arm64 when it straddles the last argument register and the stack (#6274). Every function
 * that formats this way is a macro over MS_FMT_ARGS, which passes each MsSpan argument as a pointer to a
 * copy; the callee reads `const MsSpan *`. */
MsSpan ms_message_format_(MsArena *arena, const char *format, ...);
MsSpan ms_message_vformat(MsArena *arena, const char *format, va_list arguments);

typedef struct MsFmtSpan {
  MsSpan span;
} MsFmtSpan;

/* One variadic argument: an MsSpan becomes a pointer to a copy that lives to the end of the enclosing block,
 * anything else passes as it is. The inner _Generic keeps the unselected branch well-typed. */
#define MS_FMT_ARG(x)                                                                                                  \
  _Generic((x), MsSpan: &(MsFmtSpan){_Generic((x), MsSpan: (x), default: (MsSpan){0})}.span, default: (x))

#define MS_FMT_PICK_(a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, name, ...) name
#define MS_FMT_MAP_1(a) MS_FMT_ARG(a)
#define MS_FMT_MAP_2(a, ...) MS_FMT_ARG(a), MS_FMT_MAP_1(__VA_ARGS__)
#define MS_FMT_MAP_3(a, ...) MS_FMT_ARG(a), MS_FMT_MAP_2(__VA_ARGS__)
#define MS_FMT_MAP_4(a, ...) MS_FMT_ARG(a), MS_FMT_MAP_3(__VA_ARGS__)
#define MS_FMT_MAP_5(a, ...) MS_FMT_ARG(a), MS_FMT_MAP_4(__VA_ARGS__)
#define MS_FMT_MAP_6(a, ...) MS_FMT_ARG(a), MS_FMT_MAP_5(__VA_ARGS__)
#define MS_FMT_MAP_7(a, ...) MS_FMT_ARG(a), MS_FMT_MAP_6(__VA_ARGS__)
#define MS_FMT_MAP_8(a, ...) MS_FMT_ARG(a), MS_FMT_MAP_7(__VA_ARGS__)
#define MS_FMT_MAP_9(a, ...) MS_FMT_ARG(a), MS_FMT_MAP_8(__VA_ARGS__)
#define MS_FMT_MAP_10(a, ...) MS_FMT_ARG(a), MS_FMT_MAP_9(__VA_ARGS__)
#define MS_FMT_MAP_11(a, ...) MS_FMT_ARG(a), MS_FMT_MAP_10(__VA_ARGS__)
#define MS_FMT_MAP_12(a, ...) MS_FMT_ARG(a), MS_FMT_MAP_11(__VA_ARGS__)
#define MS_FMT_MAP_13(a, ...) MS_FMT_ARG(a), MS_FMT_MAP_12(__VA_ARGS__)
#define MS_FMT_MAP_14(a, ...) MS_FMT_ARG(a), MS_FMT_MAP_13(__VA_ARGS__)
#define MS_FMT_MAP_15(a, ...) MS_FMT_ARG(a), MS_FMT_MAP_14(__VA_ARGS__)
#define MS_FMT_MAP_16(a, ...) MS_FMT_ARG(a), MS_FMT_MAP_15(__VA_ARGS__)

/* The format and its arguments (at most 16), each through MS_FMT_ARG. */
#define MS_FMT_ARGS(...)                                                                                               \
  MS_FMT_PICK_(__VA_ARGS__, MS_FMT_MAP_16, MS_FMT_MAP_15, MS_FMT_MAP_14, MS_FMT_MAP_13, MS_FMT_MAP_12, MS_FMT_MAP_11,  \
               MS_FMT_MAP_10, MS_FMT_MAP_9, MS_FMT_MAP_8, MS_FMT_MAP_7, MS_FMT_MAP_6, MS_FMT_MAP_5, MS_FMT_MAP_4,      \
               MS_FMT_MAP_3, MS_FMT_MAP_2, MS_FMT_MAP_1, ~)(__VA_ARGS__)

#define ms_message_format(arena, ...) ms_message_format_((arena), MS_FMT_ARGS(__VA_ARGS__))

#endif
