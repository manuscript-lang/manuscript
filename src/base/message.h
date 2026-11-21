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

/* The decimal text of `value`, copied into the arena. */
MsSpan ms_message_number(MsArena *arena, uint64_t value);

/* The one byte `byte`, copied into the arena. */
MsSpan ms_message_byte(MsArena *arena, uint8_t byte);

/* The text of the builder, copied into the arena. */
MsSpan ms_message_from_builder(MsArena *arena, const MsStrBuild *builder);

/* The text of `format` with each conversion replaced by its argument, copied into the arena. Conversions:
 * %s a C string, %S an MsSpan, %z a size_t, %u an unsigned int, %c a char, %% a percent sign. */
MsSpan ms_message_format(MsArena *arena, const char *format, ...);
MsSpan ms_message_vformat(MsArena *arena, const char *format, va_list arguments);

#endif
