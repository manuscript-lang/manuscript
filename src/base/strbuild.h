/* base/strbuild.h: MsStrBuild, the one builder of text (diagnostics, IR dumps, JSON, paths).
 *
 * Ownership: the builder owns its buffer; ms_strbuild_finish moves the text out as an MsString, releases the
 * buffer and leaves the builder empty (it regrows if appended to again); ms_strbuild_free drops an unfinished one. The bytes are not NUL-terminated. */
#ifndef MS_BASE_STRBUILD_H
#define MS_BASE_STRBUILD_H

#include "base/list.h"
#include "base/string.h"

typedef struct MsStrBuild {
  MsList bytes; /* owned */
} MsStrBuild;

static inline MsStrBuild ms_strbuild_new(void) {
  return (MsStrBuild){0};
}

void ms_strbuild_append(MsStrBuild *builder, MsSpan text);
void ms_strbuild_append_text(MsStrBuild *builder, const char *text); /* a C string literal or OS string */
void ms_strbuild_append_byte(MsStrBuild *builder, uint8_t byte);
void ms_strbuild_append_string(MsStrBuild *builder, const MsString *string);
void ms_strbuild_append_u64(MsStrBuild *builder, uint64_t value);
void ms_strbuild_append_indent(MsStrBuild *builder, size_t depth); /* two spaces per level, for pretty-printed JSON */
void ms_strbuild_append_i64(MsStrBuild *builder, int64_t value);
void ms_strbuild_append_u64_radix(MsStrBuild *builder, uint64_t value,
                                  unsigned radix); /* radix 2..16, lower case */
void ms_strbuild_append_utf8(MsStrBuild *builder, uint32_t scalar);

/* Appends `format` with its arguments. Verbs: %u (unsigned), %d (int), %zu (size_t), %llu, %lld, %s (a C
 * string), %.*s (an int length then a pointer), %%. Nothing else is read; the compiler checks the types. */
void ms_strbuild_printf(MsStrBuild *builder, const char *format, ...) MS_PRINTF(2, 3);
static inline size_t ms_strbuild_length(const MsStrBuild *builder) {
  return builder->bytes.len;
}

/* The text so far; invalidated by the next append. */
static inline MsSpan ms_strbuild_span(const MsStrBuild *builder) {
  return ms_span_of(builder->bytes.ptr, builder->bytes.len);
}

/* Forgets the text and keeps the buffer. */
static inline void ms_strbuild_clear(MsStrBuild *builder) {
  builder->bytes.len = 0;
}

/* Moves the text into a string, frees the buffer and leaves the builder empty. */
MsString ms_strbuild_finish(MsStrBuild *builder);

void ms_strbuild_free(MsStrBuild *builder);

#endif
