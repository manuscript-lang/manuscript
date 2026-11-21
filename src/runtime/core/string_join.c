/* runtime/core/string_join.c: the natives behind f-strings. `msrt_string_fmtN` joins N parts into a new
 * string; `msrt_string_append_fmtN` joins parts onto an owned string and grows it in place, so `s +=
 * f"{k}={n};"` in a loop builds no temporary. A part is a string or, when its bit in `mask` is set, an Int
 * written in decimal. */
#include "base/fmt.h"
#include "runtime/core/string.h"
#include "runtime/core/string_join.h"
#include "runtime/core/string_support.h"

#define JOIN_PARTS_MAX 6

/* The parts of one join, and the room for the digits of its integer parts. */
typedef struct Join {
  MsSpan parts[JOIN_PARTS_MAX];
  uint8_t digits[JOIN_PARTS_MAX][MS_FMT_INTEGER_CAPACITY];
  size_t count;
} Join;

/* Records part `slot`: an Int in decimal when `as_int`, else the string at address `arg`. */
static void add_part(Join *join, size_t slot, bool as_int, size_t arg) {
  if (as_int) {
    join->parts[slot] = ms_span_of(join->digits[slot], ms_fmt_i64_fixed((int64_t)arg, join->digits[slot]));
    return;
  }
  /* The argument is an address in an integer register; copying its bytes avoids an integer to pointer cast.
   */
  const MsString *string;
  _Static_assert(__SIZEOF_POINTER__ == sizeof arg, "an argument holds an address");
  __builtin_memcpy(&string, &arg, sizeof arg);
  join->parts[slot] = msrt_text(string);
}

/* Collects `count` parts; bit k of `mask` makes part k an Int. */
static void collect(Join *join, int64_t mask, const size_t *args, size_t count) {
  join->count = count;
  for (size_t slot = 0; slot < count; slot++) {
    add_part(join, slot, ((uint64_t)mask >> slot) & 1, args[slot]);
  }
}

static void join_into(int64_t mask, const size_t *args, size_t count, MsString *out) {
  Join join;
  collect(&join, mask, args, count);
  *out = msrt_string_join(join.parts, join.count);
}

/* `a` has the join it replaces as its part 0, so the mask of the parts is shifted down by one. */
static void append_into(const MsString *a, int64_t mask, const size_t *args, size_t count, MsString *out) {
  Join join;
  collect(&join, mask >> 1, args, count);
  *out = msrt_string_append_parts(a, join.parts, join.count);
}

void msrt_string_fmt2(int64_t mask, size_t a, size_t b, MsString *out) {
  const size_t args[] = {a, b};
  join_into(mask, args, 2, out);
}

void msrt_string_fmt3(int64_t mask, size_t a, size_t b, size_t c, MsString *out) {
  const size_t args[] = {a, b, c};
  join_into(mask, args, 3, out);
}

void msrt_string_fmt4(int64_t mask, size_t a, size_t b, size_t c, size_t d, MsString *out) {
  const size_t args[] = {a, b, c, d};
  join_into(mask, args, 4, out);
}

void msrt_string_fmt5(int64_t mask, size_t a, size_t b, size_t c, size_t d, size_t e, MsString *out) {
  const size_t args[] = {a, b, c, d, e};
  join_into(mask, args, 5, out);
}

void msrt_string_fmt6(int64_t mask, size_t a, size_t b, size_t c, size_t d, size_t e, size_t f,
                      MsString *out) {
  const size_t args[] = {a, b, c, d, e, f};
  join_into(mask, args, 6, out);
}

void msrt_string_append_fmt1(const MsString *s, int64_t mask, size_t a, MsString *out) {
  const size_t args[] = {a};
  append_into(s, mask, args, 1, out);
}

void msrt_string_append_fmt2(const MsString *s, int64_t mask, size_t a, size_t b, MsString *out) {
  const size_t args[] = {a, b};
  append_into(s, mask, args, 2, out);
}

void msrt_string_append_fmt3(const MsString *s, int64_t mask, size_t a, size_t b, size_t c, MsString *out) {
  const size_t args[] = {a, b, c};
  append_into(s, mask, args, 3, out);
}

void msrt_string_append_fmt4(const MsString *s, int64_t mask, size_t a, size_t b, size_t c, size_t d,
                             MsString *out) {
  const size_t args[] = {a, b, c, d};
  append_into(s, mask, args, 4, out);
}

void msrt_string_append_fmt5(const MsString *s, int64_t mask, size_t a, size_t b, size_t c, size_t d,
                             size_t e, MsString *out) {
  const size_t args[] = {a, b, c, d, e};
  append_into(s, mask, args, 5, out);
}
