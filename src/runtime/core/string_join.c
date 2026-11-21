/* The natives behind f-strings. `msrt_string_fmtN` joins N parts into a new string; `msrt_string_append_fmtN`
 * joins parts onto an owned string and grows it in place, so `s += f"{k}={n};"` in a loop builds no temporary.
 * A part is a string or, when its bit in `mask` is set, an Int written in decimal (no temporary for it either).
 *
 * A result of 15 bytes or fewer is inline; a longer one is one allocation of its text and a NUL. A text over
 * MS_STR_MAX_BYTES faults.
 */
#include "ms_rt/alloc.h"
#include "fmt_fixed.h"
#include "ms_rt/string.h"
#include "rt_calls.h"

#define JOIN_PARTS_MAX 6
#define MS_STR_MAX_BYTES (UINT64_C(1) << 30)
#define MS_STR_TAG_INLINE (UINT64_C(1) << 62)
/* The high bit of each byte of a word; an inline string's second word holds 7 bytes below its length. */
#define INLINE_HIGH_BITS_FIRST UINT64_C(0x8080808080808080)
#define INLINE_HIGH_BITS_SECOND UINT64_C(0x0080808080808080)

/* One piece of the result. `string` is the part's string value, or null for an integer part. */
typedef struct JoinPart {
    MsBytes text;
    const MsStr *string;
} JoinPart;

/* The parts of one join, and the room for the digits of its integer parts. */
typedef struct Join {
    JoinPart parts[JOIN_PARTS_MAX];
    uint8_t digits[JOIN_PARTS_MAX][MS_FMT_INTEGER_CAPACITY];
    size_t count;
    size_t total;
} Join;

MS_NORETURN static void fault_limit(void) {
    static const char message[] = "string: limit exceeded";
    msrt_fault((const uint8_t *)message, sizeof message - 1);
}

static size_t checked_add(size_t a, size_t b) {
    size_t sum = 0;
    if (!ms_size_add(a, b, &sum)) {
        fault_limit();
    }
    return sum;
}

static bool is_owned(const MsStr *s) { return s->tagged < MS_STR_TAG_INLINE; }

static void release(const MsStr *s) {
    if (is_owned(s)) {
        msrt_free(s->ptr_word);
    }
}

/* Whether every byte of `text` is ASCII, eight at a time. */
static bool bytes_ascii(MsBytes text) {
    size_t at = 0;
    for (; at + sizeof(uint64_t) <= text.len; at += sizeof(uint64_t)) {
        uint64_t word;
        __builtin_memcpy(&word, text.ptr + at, sizeof word);
        if ((word & INLINE_HIGH_BITS_FIRST) != 0) {
            return false;
        }
    }
    for (; at < text.len; at++) {
        if (text.ptr[at] >= 0x80) {
            return false;
        }
    }
    return true;
}

/* Whether every byte of `s` is ASCII: an inline string by its bits, another by its flag, else by a scan. */
static bool is_ascii(const MsStr *s) {
    if (ms_str_is_inline(s)) {
        return (s->low_bits & INLINE_HIGH_BITS_FIRST) == 0 && (s->tagged & INLINE_HIGH_BITS_SECOND) == 0;
    }
    return (s->tagged & MS_STR_ASCII) != 0 || bytes_ascii((MsBytes){s->ptr_word, ms_str_len(s)});
}

/* ---- the parts ---- */

/* Records part `slot`: an Int in decimal when `as_int`, else the string at address `arg`. */
static inline MS_ALWAYS_INLINE void add_part(Join *join, size_t slot, bool as_int, size_t arg) {
    JoinPart *part = &join->parts[slot];
    if (as_int) {
        size_t length = ms_fmt_i64_fixed((int64_t)arg, join->digits[slot]);
        *part = (JoinPart){.text = {join->digits[slot], length}, .string = NULL};
    } else {
        /* The argument is an address in an integer register; copying its bytes avoids an integer to pointer cast. */
        const MsStr *string;
        _Static_assert(__SIZEOF_POINTER__ == sizeof arg, "an argument holds an address");
        __builtin_memcpy(&string, &arg, sizeof arg);
        *part = (JoinPart){.text = {ms_str_data(string), ms_str_len(string)}, .string = string};
    }
    join->total = checked_add(join->total, part->text.len);
}

/* Collects `count` parts; bit k of `mask` makes part k an Int. */
static inline MS_ALWAYS_INLINE void collect(Join *join, int64_t mask, const size_t *args, size_t count) {
    join->count = count;
    join->total = 0;
    for (size_t slot = 0; slot < count; slot++) {
        add_part(join, slot, ((uint64_t)mask >> slot) & 1, args[slot]);
    }
}

/* Writes the parts one after another from `dst`, which has room for all of them. */
static inline MS_ALWAYS_INLINE void copy_parts(const Join *join, uint8_t *dst) {
    for (size_t slot = 0; slot < join->count; slot++) {
        MsBytes text = join->parts[slot].text;
        if (text.len != 0) {
            __builtin_memcpy(dst, text.ptr, text.len);
        }
        dst += text.len;
    }
}

/* ---- the result ---- */

/* An inline string holding `head` and then the parts (15 bytes or fewer in all). */
static inline MS_ALWAYS_INLINE MsStr inline_join(MsBytes head, const Join *join) {
    MsStr result = {.low_bits = 0, .tagged = 0};
    __builtin_memset(result.inline_bytes, 0, sizeof result.inline_bytes);
    if (head.len != 0) {
        __builtin_memcpy(result.inline_bytes, head.ptr, head.len);
    }
    copy_parts(join, result.inline_bytes + head.len);
    const size_t length = head.len + join->total;
    result.tagged |= MS_STR_TAG_INLINE | ((uint64_t)length << MS_STR_INLINE_SHIFT);
    return result;
}

/* A new string holding `head` and then the parts. */
static inline MS_ALWAYS_INLINE MsStr joined(MsBytes head, const Join *join) {
    size_t length = checked_add(head.len, join->total);
    if (length <= MS_STR_INLINE_MAX) {
        return inline_join(head, join);
    }
    if (length > MS_STR_MAX_BYTES) {
        fault_limit();
    }
    uint8_t *bytes = msrt_alloc(length + 1);
    if (head.len != 0) {
        __builtin_memcpy(bytes, head.ptr, head.len);
    }
    copy_parts(join, bytes + head.len);
    bytes[length] = 0;
    return (MsStr){.ptr_word = bytes, .tagged = length};
}

/* Whether a part's bytes lie in `[start, start + length]`: such a part would be read after those bytes move. */
static bool part_within(const Join *join, const uint8_t *start, size_t length) {
    uintptr_t low = (uintptr_t)start;
    uintptr_t high = low + length;
    for (size_t slot = 0; slot < join->count; slot++) {
        uintptr_t at = (uintptr_t)join->parts[slot].text.ptr;
        if (at >= low && at <= high) {
            return true;
        }
    }
    return false;
}

/* Whether every string part is ASCII. */
static bool parts_ascii(const Join *join) {
    for (size_t slot = 0; slot < join->count; slot++) {
        const MsStr *string = join->parts[slot].string;
        if (string != NULL && !is_ascii(string)) {
            return false;
        }
    }
    return true;
}

/* `a` and then the parts, taking `a`: an owned `a` is written in place, growing as `msrt_string_append` grows
 * it; any other joins into a new string and `a` is released. */
static MsStr appended(const MsStr *a, const Join *join) {
    size_t length = ms_str_len(a);
    if (!is_owned(a) || length == 0 || part_within(join, a->ptr_word, length)) {
        MsStr result = joined((MsBytes){ms_str_data(a), length}, join);
        release(a);
        return result;
    }
    size_t new_length = checked_add(length, join->total);
    if (new_length > MS_STR_MAX_BYTES) {
        fault_limit();
    }
    /* Only an `a` flagged ASCII stays flagged, and only when every string part is ASCII. */
    bool ascii = (a->tagged & MS_STR_ASCII) != 0 && parts_ascii(join);
    size_t need = new_length + 1;
    uint8_t *bytes = a->ptr_word;
    if (msrt_heap_usable_size(bytes) < need) {
        bytes = msrt_realloc(bytes, need + need / 2);
    }
    copy_parts(join, bytes + length);
    bytes[new_length] = 0;
    return (MsStr){.ptr_word = bytes, .tagged = new_length | (ascii ? MS_STR_ASCII : 0)};
}

static void put(MsStr result, MsStr *out) {
    out->ptr_word = result.ptr_word;
    out->tagged = result.tagged;
}

/* ---- the natives ---- */

static inline MS_ALWAYS_INLINE void join_into(int64_t mask, const size_t *args, size_t count, MsStr *out) {
    Join join;
    collect(&join, mask, args, count);
    put(joined((MsBytes){NULL, 0}, &join), out);
}

/* `a` has the join it replaces as its part 0, so the mask of the parts is shifted down by one. */
static inline MS_ALWAYS_INLINE void append_into(const MsStr *a, int64_t mask, const size_t *args, size_t count, MsStr *out) {
    Join join;
    collect(&join, mask >> 1, args, count);
    put(appended(a, &join), out);
}

void msrt_string_fmt2(int64_t mask, size_t a, size_t b, MsStr *out) {
    const size_t args[] = {a, b};
    join_into(mask, args, 2, out);
}

void msrt_string_fmt3(int64_t mask, size_t a, size_t b, size_t c, MsStr *out) {
    const size_t args[] = {a, b, c};
    join_into(mask, args, 3, out);
}

void msrt_string_fmt4(int64_t mask, size_t a, size_t b, size_t c, size_t d, MsStr *out) {
    const size_t args[] = {a, b, c, d};
    join_into(mask, args, 4, out);
}

void msrt_string_fmt5(int64_t mask, size_t a, size_t b, size_t c, size_t d, size_t e, MsStr *out) {
    const size_t args[] = {a, b, c, d, e};
    join_into(mask, args, 5, out);
}

void msrt_string_fmt6(int64_t mask, size_t a, size_t b, size_t c, size_t d, size_t e, size_t f, MsStr *out) {
    const size_t args[] = {a, b, c, d, e, f};
    join_into(mask, args, 6, out);
}

void msrt_string_append_fmt1(const MsStr *s, int64_t mask, size_t a, MsStr *out) {
    const size_t args[] = {a};
    append_into(s, mask, args, 1, out);
}

void msrt_string_append_fmt2(const MsStr *s, int64_t mask, size_t a, size_t b, MsStr *out) {
    const size_t args[] = {a, b};
    append_into(s, mask, args, 2, out);
}

void msrt_string_append_fmt3(const MsStr *s, int64_t mask, size_t a, size_t b, size_t c, MsStr *out) {
    const size_t args[] = {a, b, c};
    append_into(s, mask, args, 3, out);
}

void msrt_string_append_fmt4(const MsStr *s, int64_t mask, size_t a, size_t b, size_t c, size_t d, MsStr *out) {
    const size_t args[] = {a, b, c, d};
    append_into(s, mask, args, 4, out);
}

void msrt_string_append_fmt5(const MsStr *s, int64_t mask, size_t a, size_t b, size_t c, size_t d, size_t e,
                             MsStr *out) {
    const size_t args[] = {a, b, c, d, e};
    append_into(s, mask, args, 5, out);
}
