/* Owns cutting the functions of a module into several LLVM modules (see emit_units.h). */
#include "compiler/emit/emit_units.h"

#include "base/alloc.h"

uint32_t emit_unit_count(const EmitOptions *options, size_t bytes) {
  uint32_t count = options->units < 1 ? 1 : options->units > EMIT_MAX_UNITS ? EMIT_MAX_UNITS : options->units;
  if (options->unit_bytes != 0 && bytes / options->unit_bytes < count) {
    count = bytes / options->unit_bytes < 1 ? 1 : (uint32_t)(bytes / options->unit_bytes);
  }
  return count;
}

static const char define_prefix[] = "define ";
static const char internal_prefix[] = "internal ";

/* The first line of a function's text: its `define` header. */
static MsSpan header_of(MsSpan text) {
  size_t end = 0;
  while (end < text.len && text.ptr[end] != '\n') {
    end++;
  }
  return ms_span_of(text.ptr, end);
}

/* Appends `define` of `header`, with `internal` made `hidden` so another module may call it. */
static void append_definition(MsStrBuild *out, MsSpan header, MsSpan rest) {
  const MsSpan keyword = ms_span_of_text(define_prefix);
  const MsSpan internal = ms_span_of_text(internal_prefix);
  MsSpan after = ms_span_of(header.ptr + keyword.len, header.len - keyword.len);
  ms_strbuild_append(out, keyword);
  if (ms_span_starts_with(after, internal)) {
    ms_strbuild_append_text(out, "hidden ");
    after = ms_span_of(after.ptr + internal.len, after.len - internal.len);
  }
  ms_strbuild_append(out, after);
  ms_strbuild_append(out, rest);
}

/* Appends the declaration of the function whose header is `header`: the same line without the debug location and the
 * brace, and hidden where the definition is. */
static void append_declaration(MsStrBuild *out, MsSpan header) {
  const MsSpan keyword = ms_span_of_text(define_prefix);
  const MsSpan internal = ms_span_of_text(internal_prefix);
  MsSpan after = ms_span_of(header.ptr + keyword.len, header.len - keyword.len);
  ms_strbuild_append_text(out, "declare ");
  if (ms_span_starts_with(after, internal)) {
    ms_strbuild_append_text(out, "hidden ");
    after = ms_span_of(after.ptr + internal.len, after.len - internal.len);
  }
  size_t end = after.len;
  size_t at = 0;
  if (ms_span_find(after, ms_span_of_text(" !dbg !"), &at)) {
    end = at;
  } else if (end >= 2 && after.ptr[end - 2] == ' ' && after.ptr[end - 1] == '{') {
    end -= 2;
  }
  ms_strbuild_append(out, ms_span_of(after.ptr, end));
  ms_strbuild_append_byte(out, '\n');
}

uint32_t emit_split_functions(MsSpan whole, size_t first, const EmitFuncSpan *spans, uint32_t nfuncs, uint32_t wanted,
                              MsStrBuild *outs) {
  size_t total = 0;
  for (uint32_t index = 0; index < nfuncs; index++) {
    total += spans[index].to - spans[index].from;
  }
  /* A function goes to the module its middle falls in, so the modules hold runs of about equal size. */
  uint32_t *unit_of = ms_alloc(sizeof(uint32_t) * (nfuncs + 1));
  uint32_t *dense = ms_alloc(sizeof(uint32_t) * (wanted + 1));
  for (uint32_t unit = 0; unit < wanted; unit++) {
    dense[unit] = UINT32_MAX;
  }
  uint32_t count = 0;
  size_t before = 0;
  for (uint32_t index = 0; index < nfuncs; index++) {
    const size_t size = spans[index].to - spans[index].from;
    uint32_t unit = total == 0 ? 0 : (uint32_t)(((before + size / 2) * wanted) / total);
    unit = unit >= wanted ? wanted - 1 : unit;
    if (dense[unit] == UINT32_MAX) {
      dense[unit] = count++;
    }
    unit_of[index] = dense[unit];
    before += size;
  }
  if (count == 0) {
    count = 1; /* a program without functions is one module */
  }
  for (uint32_t unit = 0; unit < count; unit++) {
    ms_strbuild_append(&outs[unit], ms_span_of(whole.ptr, first));
  }
  for (uint32_t index = 0; index < nfuncs; index++) {
    const MsSpan text = ms_span_of(whole.ptr + spans[index].from, spans[index].to - spans[index].from);
    if (text.len == 0) {
      continue;
    }
    const MsSpan header = header_of(text);
    for (uint32_t unit = 0; unit < count; unit++) {
      if (unit == unit_of[index]) {
        append_definition(&outs[unit], header, ms_span_of(text.ptr + header.len, text.len - header.len));
      } else {
        append_declaration(&outs[unit], header);
      }
    }
  }
  ms_free(unit_of);
  ms_free(dense);
  return count;
}
