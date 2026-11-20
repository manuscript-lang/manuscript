/* String primitives that build strings: construction, copies, concatenation, trimmed views, slices and views.
 * Ported from crates/ms-rt/src/string.rs. Memory comes from the allocator (ms_rt/alloc.h).
 *
 * A string is a MsStr (ms_rt/string.h). Every function here follows its rules: owned strings have a NUL after
 * their bytes, inline strings keep the bytes past their length zero, one-character ASCII and empty results are
 * static, and a view never points into an inline string. */
#include <string.h>
#include "ms_rt/alloc.h"
#include "ms_rt/fmt.h"
#include "ms_rt/search.h"
#include "ms_rt/safe.h"
#include "ms_rt/string.h"
#include "ms_rt/utf8.h"
#include "ms_rt/chars.h"

/* The fault entry point and the table of one-character ASCII strings (two bytes each, the second a NUL) are
 * still defined by the Rust runtime. */
MS_NORETURN void msrt_fault(const uint8_t *msg, size_t len);
extern uint8_t msrt_ascii_chars[128][2];

#define MS_STR_TAG_INLINE (UINT64_C(1) << MS_STR_TAG_SHIFT)
#define MS_STR_TAG_STATIC (UINT64_C(2) << MS_STR_TAG_SHIFT)
#define MS_STR_TAG_VIEW (UINT64_C(3) << MS_STR_TAG_SHIFT)
#define MS_STR_MAX_BYTES ((size_t)1 << 30)

#define MS_STR_LIMIT_MESSAGE "string: limit exceeded"

/* Keeps a slow path out of its callers, which are small and hot. */
#define MS_NOINLINE __attribute__((noinline))

typedef unsigned __int128 ms_u128_t;

static uint8_t empty_bytes[1];

static MS_NORETURN void fault_limit(void) {
    msrt_fault((const uint8_t *)MS_STR_LIMIT_MESSAGE, sizeof MS_STR_LIMIT_MESSAGE - 1);
}

/* ---- Making and reading string values ---- */

static MsStr make_static(const uint8_t *bytes, size_t len) {
    return (MsStr){.bytes = bytes, .tagged = len | MS_STR_TAG_STATIC};
}

static MsStr make_empty(void) { return make_static(empty_bytes, 0); }

/* An inline string of `len` <= 15 bytes whose little-endian bits are `bits` (zero past `len`). */
static MsStr inline_from_bits(ms_u128_t bits, size_t len) {
    return (MsStr){.low_bits = (uint64_t)bits,
                   .tagged = (uint64_t)(bits >> 64) | MS_STR_TAG_INLINE | ((uint64_t)len << MS_STR_INLINE_SHIFT)};
}

/* The bytes as little-endian bits, zero past the end. At most 16 bytes. */
static ms_u128_t pack_bits(MsBytes bytes) {
    uint8_t buffer[16] = {0};
    ms_u128_t bits = 0;
    if (!ms_bytes_copy(ms_bytes_mut(buffer, sizeof buffer), bytes)) {
        return 0;
    }
    __builtin_memcpy(&bits, buffer, sizeof bits);
    return bits;
}

static MsBytes str_bytes(const MsStr *s) { return ms_bytes_of(ms_str_data(s), ms_str_len(s)); }

/* The bytes of a string of at most 16 bytes as little-endian bits. */
static ms_u128_t str_bits(const MsStr *s) {
    if (ms_str_is_inline(s)) {
        const uint64_t inline_high_mask = (UINT64_C(1) << MS_STR_INLINE_SHIFT) - 1;
        return (ms_u128_t)s->low_bits | ((ms_u128_t)(s->tagged & inline_high_mask) << 64);
    }
    return pack_bits(str_bytes(s));
}

static bool owns_block(const MsStr *s) { return (s->tagged >> MS_STR_TAG_SHIFT) == 0; }

/* A copy of an inline or static string is the same two words. */
static bool copies_bitwise(const MsStr *s) { return ((s->tagged >> MS_STR_TAG_SHIFT) - 1) < 2; }

static bool str_is_ascii(const MsStr *s) {
    const uint64_t high_bits = UINT64_C(0x8080808080808080);
    if (ms_str_is_inline(s)) {
        ms_u128_t high_mask = ((ms_u128_t)high_bits << 64) | high_bits;
        return (str_bits(s) & high_mask) == 0;
    }
    MsBytes bytes = str_bytes(s);
    return (s->tagged & MS_STR_ASCII) != 0 || ms_utf8_is_ascii(bytes.ptr, bytes.len);
}

/* ---- Owned blocks ---- */

/* An owned string of `len` bytes and the writable bytes of its block, which are uninitialised except for the
 * NUL after them. */
typedef struct OwnedBlock {
    MsStr str;
    MsBytesMut bytes;
} OwnedBlock;

/* Faults past the string size limit. */
static OwnedBlock owned_block_new(size_t len) {
    size_t block_size = 0;
    if (len > MS_STR_MAX_BYTES || !ms_size_add(len, 1, &block_size)) {
        fault_limit();
    }
    uint8_t *block = msrt_alloc(block_size);
    block[len] = 0;
    return (OwnedBlock){.str = {.ptr_word = block, .tagged = len}, .bytes = ms_bytes_mut(block, len)};
}

static MsStr with_ascii_flag(MsStr s) {
    s.tagged |= MS_STR_ASCII;
    return s;
}

/* Copies `source` into the start of `destination`, which the caller sized for it. */
static void copy_into(MsBytesMut destination, MsBytes source) {
    if (!ms_bytes_copy(destination, source)) {
        fault_limit();
    }
}

/* Copies `source` to the start of `*cursor` and moves the cursor past it: the one place that writes a string
 * piece by piece. The copy is checked first, so the pointer step stays inside the block. */
static void append_bytes(MsBytesMut *cursor, MsBytes source) {
    copy_into(*cursor, source);
    cursor->ptr += source.len;
    cursor->len -= source.len;
}

static MsStr heap_copy(MsBytes source) {
    OwnedBlock block = owned_block_new(source.len);
    copy_into(block.bytes, source);
    return ms_utf8_is_ascii(source.ptr, source.len) ? with_ascii_flag(block.str) : block.str;
}

/* An owned copy of the bytes: inline when it fits. */
static MS_NOINLINE MsStr owned_copy(MsBytes source) {
    if (source.len <= MS_STR_INLINE_MAX) {
        return inline_from_bits(pack_bits(source), source.len);
    }
    return heap_copy(source);
}

static MsStr cloned(const MsStr *s) {
    if (copies_bitwise(s)) {
        return *s;
    }
    return owned_copy(str_bytes(s));
}

/* New string from bytes: empty and one-character ASCII results are static, up to 15 bytes inline. */
static MsStr from_bytes(MsBytes bytes) {
    uint8_t first = 0;
    if (bytes.len == 0) {
        return make_empty();
    }
    if (bytes.len == 1 && ms_bytes_get(bytes, 0, &first) && first < 0x80) {
        return make_static(msrt_ascii_chars[first], 1);
    }
    return owned_copy(bytes);
}

/* The bytes inside another live string as a string: an inline copy when they fit, otherwise a view. */
static MsStr view_of(MsBytes bytes) {
    if (bytes.len <= MS_STR_INLINE_MAX) {
        return inline_from_bits(pack_bits(bytes), bytes.len);
    }
    return (MsStr){.bytes = bytes.ptr, .tagged = bytes.len | MS_STR_TAG_VIEW};
}

void msrt_string_from_bytes(const uint8_t *ptr, size_t len, MsStr *out) { *out = from_bytes(ms_bytes_of(ptr, len)); }

void msrt_string_empty(MsStr *out) { *out = make_empty(); }

void msrt_string_clone(const MsStr *s, MsStr *out) { *out = cloned(s); }

/* `tagged` is the second word of an owned string or a view, never of an inline string. */
void msrt_str_copy(const uint8_t *ptr, size_t tagged, MsStr *out) {
    *out = owned_copy(ms_bytes_of(ptr, tagged & MS_STR_LEN_MASK));
}

void msrt_str_free(uint8_t *ptr) { msrt_free(ptr); }

void msrt_string_free(const MsStr *s) {
    if (owns_block(s)) {
        msrt_free(s->ptr_word);
    }
}

/* ---- Concatenation ---- */

void msrt_string_concat(const MsStr *a, const MsStr *b, MsStr *out) {
    size_t length_a = ms_str_len(a);
    size_t length_b = ms_str_len(b);
    size_t total = 0;
    if (length_b == 0) {
        *out = cloned(a);
        return;
    }
    if (length_a == 0) {
        *out = cloned(b);
        return;
    }
    if (!ms_size_add(length_a, length_b, &total)) {
        fault_limit();
    }
    if (total <= MS_STR_INLINE_MAX) {
        *out = inline_from_bits(str_bits(a) | (str_bits(b) << (8 * length_a)), total);
        return;
    }
    OwnedBlock block = owned_block_new(total);
    MsBytesMut cursor = block.bytes;
    append_bytes(&cursor, str_bytes(a));
    append_bytes(&cursor, str_bytes(b));
    *out = (str_is_ascii(a) && str_is_ascii(b)) ? with_ascii_flag(block.str) : block.str;
}

/* Room after the text and NUL that an owned string records, as a lower bound of what its block holds. */
#define MS_STR_SPARE_SHIFT 31
#define MS_STR_SPARE_MASK (((UINT64_C(1) << 30) - 1) << MS_STR_SPARE_SHIFT)

static size_t recorded_spare(const MsStr *s) { return (size_t)((s->tagged & MS_STR_SPARE_MASK) >> MS_STR_SPARE_SHIFT); }

static MsStr with_spare(MsStr s, size_t spare) {
    const size_t most = (size_t)(MS_STR_SPARE_MASK >> MS_STR_SPARE_SHIFT);
    s.tagged = (s.tagged & ~MS_STR_SPARE_MASK) | ((uint64_t)(spare > most ? most : spare) << MS_STR_SPARE_SHIFT);
    return s;
}

/* Whether `piece` lies inside the text of `s` (or just past its end), so growing `s` in place would move it. */
static bool lies_within(const MsStr *s, MsBytes piece) {
    uintptr_t start = (uintptr_t)s->ptr_word;
    uintptr_t at = (uintptr_t)piece.ptr;
    return at >= start && at - start <= ms_str_len(s);
}

/* `a + b` where the caller gives `a` up: an owned `a` grows in place, so `s = s + piece` in a loop reuses one block
 * and reallocates a logarithmic number of times. Otherwise it is a concatenation and `a` is released. */
void msrt_string_append(const MsStr *a, const MsStr *b, MsStr *out) {
    MsStr first = *a;
    size_t length_a = ms_str_len(&first);
    MsBytes added = str_bytes(b);
    size_t total = 0;
    if (!owns_block(&first) || length_a == 0 || lies_within(&first, added)) {
        msrt_string_concat(a, b, out);
        msrt_string_free(&first);
        return;
    }
    if (added.len == 0) {
        *out = first;
        return;
    }
    if (!ms_size_add(length_a, added.len, &total) || total > MS_STR_MAX_BYTES) {
        fault_limit();
    }
    /* Only a flagged `a` stays flagged: scanning an unflagged one on every append would be quadratic. */
    bool ascii = (first.tagged & MS_STR_ASCII) != 0 && str_is_ascii(b);
    size_t need = total + 1;
    size_t spare = 0;
    uint8_t *block = first.ptr_word;
    if (recorded_spare(&first) >= added.len) {
        spare = recorded_spare(&first) - added.len;
    } else if (msrt_heap_usable_size(block) >= need) {
        spare = msrt_heap_usable_size(block) - need;
    } else {
        block = msrt_realloc(block, need + need / 2);
        spare = need / 2;
    }
    MsBytesMut tail = {0};
    if (!ms_bytes_mut_slice(ms_bytes_mut(block, need), length_a, need, &tail)) {
        fault_limit();
    }
    append_bytes(&tail, added);
    tail.ptr[0] = 0; /* the NUL after the text: the one byte of `tail` left */
    MsStr grown = with_spare((MsStr){.ptr_word = block, .tagged = total}, spare);
    *out = ascii ? with_ascii_flag(grown) : grown;
}

static size_t total_length(const MsStr *const *parts, size_t count) {
    size_t total = 0;
    for (size_t i = 0; i < count; i++) {
        if (!ms_size_add(total, ms_str_len(parts[i]), &total)) {
            fault_limit();
        }
    }
    return total;
}

/* The parts joined with a single allocation. */
static void concat_parts(const MsStr *const *parts, size_t count, MsStr *out) {
    size_t total = total_length(parts, count);
    if (total <= MS_STR_INLINE_MAX) {
        ms_u128_t bits = 0;
        size_t offset = 0;
        for (size_t i = 0; i < count; i++) {
            bits |= str_bits(parts[i]) << (8 * offset);
            offset += ms_str_len(parts[i]);
        }
        *out = inline_from_bits(bits, total);
        return;
    }
    OwnedBlock block = owned_block_new(total);
    MsBytesMut cursor = block.bytes;
    for (size_t i = 0; i < count; i++) {
        append_bytes(&cursor, str_bytes(parts[i]));
    }
    *out = block.str;
}

void msrt_string_concat3(const MsStr *a, const MsStr *b, const MsStr *c, MsStr *out) {
    const MsStr *parts[] = {a, b, c};
    concat_parts(parts, MS_COUNT_OF(parts), out);
}

void msrt_string_concat4(const MsStr *a, const MsStr *b, const MsStr *c, const MsStr *d, MsStr *out) {
    const MsStr *parts[] = {a, b, c, d};
    concat_parts(parts, MS_COUNT_OF(parts), out);
}

void msrt_string_concat5(const MsStr *a, const MsStr *b, const MsStr *c, const MsStr *d, const MsStr *e, MsStr *out) {
    const MsStr *parts[] = {a, b, c, d, e};
    concat_parts(parts, MS_COUNT_OF(parts), out);
}

void msrt_string_concat6(const MsStr *a, const MsStr *b, const MsStr *c, const MsStr *d, const MsStr *e, const MsStr *f,
                         MsStr *out) {
    const MsStr *parts[] = {a, b, c, d, e, f};
    concat_parts(parts, MS_COUNT_OF(parts), out);
}

/* ---- Repeat and reverse ---- */

/* Fills `destination` with whole copies of `pattern`: the first copy is written, then the filled part doubles. */
static void fill_repeated(MsBytesMut destination, MsBytes pattern) {
    if (destination.len == 0) {
        return;
    }
    if (pattern.len == 1) {
        memset(destination.ptr, pattern.ptr[0], destination.len);
        return;
    }
    MsBytes first = pattern;
    if (first.len > destination.len && !ms_bytes_slice(pattern, 0, destination.len, &first)) {
        fault_limit();
    }
    MsBytesMut cursor = destination;
    append_bytes(&cursor, first);
    size_t filled = first.len;
    while (filled < destination.len) {
        size_t step = filled < destination.len - filled ? filled : destination.len - filled;
        append_bytes(&cursor, ms_bytes_of(destination.ptr, step));
        filled += step;
    }
}

/* `String.repeat`: a count of zero or below, or empty text, gives empty text; output beyond the string limit
 * faults like `concat`. */
void msrt_string_repeat(const MsStr *s, int64_t count, MsStr *out) {
    MsBytes text = str_bytes(s);
    if (count <= 0 || text.len == 0) {
        *out = make_empty();
        return;
    }
    if ((uint64_t)count > MS_STR_MAX_BYTES / text.len) {
        fault_limit();
    }
    OwnedBlock block = owned_block_new(text.len * (size_t)count);
    fill_repeated(block.bytes, text);
    *out = str_is_ascii(s) ? with_ascii_flag(block.str) : block.str;
}

/* Copies `text` into `destination` back to front, one byte at a time. */
static void reverse_ascii(MsBytesMut destination, MsBytes text) {
    for (size_t i = 0; i < text.len; i++) {
        uint8_t byte = 0;
        if (!ms_bytes_get(text, text.len - 1 - i, &byte)) {
            fault_limit();
        }
        destination.ptr[i] = byte;
    }
}

/* Copies the scalars of `text` into `destination` last first. A String is valid UTF-8, so a scalar is a lead byte
 * and its continuation bytes and moves as it is, without decoding. */
static void reverse_scalars(MsBytesMut destination, MsBytes text) {
    MsBytesMut cursor = destination;
    size_t end = text.len;
    while (end > 0) {
        size_t start = end - 1;
        uint8_t byte = 0;
        while (start > 0 && end - start < 4 && ms_bytes_get(text, start, &byte) && ms_utf8_is_continuation(byte)) {
            start--;
        }
        MsBytes scalar = {0};
        if (!ms_bytes_slice(text, start, end, &scalar)) {
            fault_limit();
        }
        append_bytes(&cursor, scalar);
        end = start;
    }
}

static void reverse_into(MsBytesMut destination, MsBytes text, bool ascii) {
    if (ascii) {
        reverse_ascii(destination, text);
    } else {
        reverse_scalars(destination, text);
    }
}

/* The text reversed by scalars; up to 15 bytes are built in a buffer and become an inline or static string like
 * any short result. */
static MsStr reversed(const MsStr *s, bool ascii) {
    MsBytes text = str_bytes(s);
    uint8_t small[MS_STR_INLINE_MAX + 1] = {0};
    if (text.len <= MS_STR_INLINE_MAX) {
        MsBytesMut buffer = ms_bytes_mut(small, text.len);
        reverse_into(buffer, text, ascii);
        return from_bytes(ms_bytes_of(small, text.len));
    }
    OwnedBlock block = owned_block_new(text.len);
    reverse_into(block.bytes, text, ascii);
    return ascii ? with_ascii_flag(block.str) : block.str;
}

void msrt_string_reverse(const MsStr *s, MsStr *out) { *out = reversed(s, str_is_ascii(s)); }

/* ---- Trimmed views ---- */

/* The range of bytes left after trimming. */
typedef struct TrimRange {
    size_t start;
    size_t end;
} TrimRange;

static bool is_ascii_space(uint8_t byte) { return byte == ' ' || (byte >= 9 && byte <= 13); }

/* Whether the byte is ASCII and not white space, so a trim that meets it stops without decoding. */
static bool is_ascii_text(uint8_t byte) { return byte < 0x80 && !is_ascii_space(byte); }

static size_t trim_start_scan(MsBytes text, size_t start, size_t end) {
    while (start < end) {
        uint8_t byte = text.ptr[start];
        if (byte < 0x80) {
            if (!is_ascii_space(byte)) {
                break;
            }
            start++;
            continue;
        }
        MsRune rune = ms_utf8_decode(text.ptr + start, end - start);
        if (!ms_utf8_is_space(rune.rune)) {
            break;
        }
        start += rune.width;
    }
    return start;
}

static size_t trim_end_scan(MsBytes text, size_t start, size_t end) {
    while (end > start) {
        uint8_t byte = text.ptr[end - 1];
        if (byte < 0x80) {
            if (!is_ascii_space(byte)) {
                break;
            }
            end--;
            continue;
        }
        MsRune rune = ms_utf8_decode_last(text.ptr + start, end - start);
        if (!ms_utf8_is_space(rune.rune)) {
            break;
        }
        end -= rune.width;
    }
    return end;
}

static TrimRange trim_range_scan(MsBytes text, bool trim_start, bool trim_end) {
    TrimRange range = {.start = 0, .end = text.len};
    if (trim_start) {
        range.start = trim_start_scan(text, range.start, range.end);
    }
    if (trim_end) {
        range.end = trim_end_scan(text, range.start, range.end);
    }
    return range;
}

/* The range left after trimming. Text whose first and last bytes (the ends asked for) are ASCII and not white
 * space, the usual case, is decided by those two bytes. */
static TrimRange trim_range(MsBytes text, bool trim_start, bool trim_end) {
    uint8_t first = 0;
    uint8_t last = 0;
    if (text.len != 0 && ms_bytes_get(text, 0, &first) && ms_bytes_get(text, text.len - 1, &last) &&
        (!trim_start || is_ascii_text(first)) && (!trim_end || is_ascii_text(last))) {
        return (TrimRange){.start = 0, .end = text.len};
    }
    return trim_range_scan(text, trim_start, trim_end);
}

/* A view of `s` without the white space the flags name: nothing is allocated. */
static void trim_view(const MsStr *s, bool trim_start, bool trim_end, MsStr *out) {
    MsBytes text = str_bytes(s);
    TrimRange range = trim_range(text, trim_start, trim_end);
    MsBytes kept = {0};
    if (range.start == range.end || !ms_bytes_slice(text, range.start, range.end, &kept)) {
        *out = make_empty(); /* an empty result borrows nothing */
    } else if (kept.len == text.len && copies_bitwise(s)) {
        *out = *s;
    } else {
        *out = view_of(kept);
    }
}

void msrt_string_trim_view(const MsStr *s, MsStr *out) { trim_view(s, true, true, out); }

void msrt_string_trim_start_view(const MsStr *s, MsStr *out) { trim_view(s, true, false, out); }

void msrt_string_trim_end_view(const MsStr *s, MsStr *out) { trim_view(s, false, true, out); }

/* ---- Trimmed copies ---- */

/* The text without white space at the ends the flags name: the same string when nothing is trimmed. */
static MsStr trimmed(const MsStr *s, bool trim_start, bool trim_end) {
    MsBytes text = str_bytes(s);
    TrimRange range = trim_range(text, trim_start, trim_end);
    MsBytes kept = {0};
    if (range.start == 0 && range.end == text.len) {
        return cloned(s);
    }
    if (!ms_bytes_slice(text, range.start, range.end, &kept)) {
        return make_empty();
    }
    return from_bytes(kept);
}

void msrt_string_trim(const MsStr *s, MsStr *out) { *out = trimmed(s, true, true); }

void msrt_string_trim_start(const MsStr *s, MsStr *out) { *out = trimmed(s, true, false); }

void msrt_string_trim_end(const MsStr *s, MsStr *out) { *out = trimmed(s, false, true); }

/* The string over the first `len` bytes of the owned block at `block`: the same block when it stays on the heap, an
 * inline copy (freeing the block) when it fits inline. */
static MsStr finish_owned(uint8_t *block, size_t len, bool ascii) {
    if (len <= MS_STR_INLINE_MAX) {
        MsStr result = from_bytes(ms_bytes_of(block, len));
        msrt_free(block);
        return result;
    }
    block[len] = 0;
    MsStr result = {.ptr_word = block, .tagged = len};
    return ascii ? with_ascii_flag(result) : result;
}

/* `trim`, `trim_start` or `trim_end` of a string that dies at the call: the kept bytes move to the front of the
 * same block. */
static void trimmed_take(MsStr *s, bool trim_start, bool trim_end, MsStr *out) {
    if (!owns_block(s)) {
        *out = trimmed(s, trim_start, trim_end);
        return;
    }
    uint8_t *block = s->ptr_word;
    bool ascii = (s->tagged & MS_STR_ASCII) != 0;
    MsBytes text = str_bytes(s);
    TrimRange range = trim_range(text, trim_start, trim_end);
    size_t kept = range.end > range.start ? range.end - range.start : 0;
    if (range.start > 0 && kept > 0) {
        MsBytes source = {0};
        if (!ms_bytes_slice(text, range.start, range.end, &source)) {
            fault_limit();
        }
        copy_into(ms_bytes_mut(block, kept), source);
    }
    *out = finish_owned(block, kept, ascii);
}

void msrt_string_trim_take(MsStr *s, MsStr *out) { trimmed_take(s, true, true, out); }

void msrt_string_trim_start_take(MsStr *s, MsStr *out) { trimmed_take(s, true, false, out); }

void msrt_string_trim_end_take(MsStr *s, MsStr *out) { trimmed_take(s, false, true, out); }

/* ---- Searching and characters ---- */

/* `String.index_of`: whether `v` occurs in `a`, and where. */
uint8_t msrt_string_index_of(const MsStr *a, const MsStr *v, int64_t *out) {
    size_t found = ms_find(ms_str_data(a), ms_str_len(a), ms_str_data(v), ms_str_len(v));
    if (found == SIZE_MAX) {
        return 0;
    }
    *out = (int64_t)found;
    return 1;
}

/* The character that starts at byte `at` (a lead byte or a stray byte, which reads as U+FFFD) as a one-character
 * string. The caller passes an offset inside the text. */
void msrt_string_char_at(const MsStr *s, int64_t at, MsStr *out) {
    MsBytes text = str_bytes(s);
    MsBytes rest = {0};
    if (at < 0 || !ms_bytes_slice(text, (size_t)at, text.len, &rest) || rest.len == 0) {
        *out = make_empty();
        return;
    }
    MsRune rune = ms_utf8_decode(rest.ptr, rest.len);
    if (rune.rune == MS_RUNE_ERROR && rune.width == 1) {
        static const uint8_t replacement[] = {0xEF, 0xBF, 0xBD};
        *out = from_bytes(ms_bytes_of(replacement, sizeof replacement));
        return;
    }
    MsBytes character = {0};
    if (!ms_bytes_slice(rest, 0, rune.width, &character)) {
        fault_limit();
    }
    *out = from_bytes(character);
}

/* ---- Padding ---- */

/* The padding bytes that fill `needed` scalars and the length of the padded text. */
typedef struct PadPlan {
    size_t pad_bytes;
    size_t total;
} PadPlan;

/* The plan for padding `text_length` bytes with `needed` scalars of `padding`; faults past the string limit. */
static PadPlan plan_padding(size_t text_length, size_t needed, const MsStr *padding) {
    MsBytes padding_bytes = str_bytes(padding);
    size_t padding_scalars = (size_t)msrt_string_scalar_length(padding);
    size_t cycle_bytes = 0;
    size_t prefix_bytes = 0;
    PadPlan plan = {0};
    if (needed % padding_scalars > 0) {
        prefix_bytes = ms_utf8_offset_of(padding_bytes.ptr, padding_bytes.len, needed % padding_scalars);
    }
    if (!ms_size_mul(needed / padding_scalars, padding_bytes.len, &cycle_bytes) ||
        !ms_size_add(cycle_bytes, prefix_bytes, &plan.pad_bytes) || !ms_size_add(text_length, plan.pad_bytes, &plan.total) ||
        plan.total > MS_STR_MAX_BYTES) {
        fault_limit();
    }
    return plan;
}

/* Writes the padded text into `destination` of `plan->total` bytes: the padding repeated (and cut at the last
 * scalar that fits) before the text when `at_start`, after it otherwise. */
static void write_padded(MsBytesMut destination, MsBytes text, MsBytes padding, const PadPlan *plan, bool at_start) {
    MsBytesMut pad_region = {0};
    MsBytesMut text_region = {0};
    size_t pad_start = at_start ? 0 : text.len;
    size_t text_start = at_start ? plan->pad_bytes : 0;
    if (!ms_bytes_mut_slice(destination, pad_start, pad_start + plan->pad_bytes, &pad_region) ||
        !ms_bytes_mut_slice(destination, text_start, text_start + text.len, &text_region)) {
        fault_limit();
    }
    copy_into(text_region, text);
    fill_repeated(pad_region, padding);
}

/* Pads to `target` scalars with repeated `padding`; a short target or empty padding leaves the text unchanged.
 * Output beyond the string limit faults like `concat`. */
static void pad(bool at_start, const MsStr *s, int64_t target, const MsStr *padding, MsStr *out) {
    int64_t needed = 0;
    MsBytes text = str_bytes(s);
    MsBytes padding_bytes = str_bytes(padding);
    if (__builtin_sub_overflow(target, msrt_string_scalar_length(s), &needed) || needed <= 0 || padding_bytes.len == 0) {
        *out = cloned(s);
        return;
    }
    PadPlan plan = plan_padding(text.len, (size_t)needed, padding);
    if (plan.total <= MS_STR_INLINE_MAX) {
        uint8_t small[MS_STR_INLINE_MAX + 1] = {0};
        write_padded(ms_bytes_mut(small, plan.total), text, padding_bytes, &plan, at_start);
        *out = inline_from_bits(pack_bits(ms_bytes_of(small, plan.total)), plan.total);
        return;
    }
    OwnedBlock block = owned_block_new(plan.total);
    write_padded(block.bytes, text, padding_bytes, &plan, at_start);
    *out = (str_is_ascii(s) && str_is_ascii(padding)) ? with_ascii_flag(block.str) : block.str;
}

void msrt_string_pad_start(const MsStr *s, int64_t target, const MsStr *padding, MsStr *out) {
    pad(true, s, target, padding, out);
}

void msrt_string_pad_end(const MsStr *s, int64_t target, const MsStr *padding, MsStr *out) {
    pad(false, s, target, padding, out);
}

/* ---- Slices and views ---- */

static bool is_boundary(MsBytes text, size_t index) {
    uint8_t byte = 0;
    return index == text.len || (ms_bytes_get(text, index, &byte) && !ms_utf8_is_continuation(byte));
}

/* A bound as an offset into `length` bytes: a negative bound counts back from the end. */
static int64_t resolve_bound(int64_t bound, int64_t length) { return bound < 0 ? length + bound : bound; }

static size_t clamp_to_text(int64_t offset, int64_t length) {
    if (offset < 0) {
        return 0;
    }
    return (size_t)(offset > length ? length : offset);
}

/* `String.slice(start, end)`: an owned copy of the bytes [start, end). Bounds outside the text clamp to it and a
 * bound inside a scalar moves inward, so the result is always whole characters and the call never fails. */
void msrt_string_slice(const MsStr *s, int64_t start, int64_t end, MsStr *out) {
    MsBytes text = str_bytes(s);
    int64_t length = (int64_t)text.len;
    size_t first = clamp_to_text(resolve_bound(start, length), length);
    size_t last = clamp_to_text(resolve_bound(end, length), length);
    MsBytes piece = {0};
    while (first < last && !is_boundary(text, first)) {
        first++;
    }
    while (last > first && !is_boundary(text, last)) {
        last--;
    }
    if (first >= last || !ms_bytes_slice(text, first, last, &piece)) {
        *out = make_empty();
    } else if (piece.len == text.len) {
        *out = cloned(s);
    } else {
        *out = from_bytes(piece);
    }
}

/* Appends `text` to the message being built in `message`, which the caller sized for it. */
static void message_append(MsBytesMut *message, const char *text, size_t length) {
    append_bytes(message, ms_bytes_of((const uint8_t *)text, length));
}

static void message_append_number(MsBytesMut *message, int64_t value) {
    uint8_t digits[MS_FMT_INTEGER_CAPACITY];
    size_t count = 0;
    if (msrt_fmt_i64(value, digits, sizeof digits, &count)) {
        append_bytes(message, ms_bytes_of(digits, count));
    }
}

static MS_NORETURN void fault_view_bounds(int64_t start, int64_t end) {
    static const char head[] = "String.view: bounds ";
    static const char tail[] = " are outside the text or inside a scalar";
    uint8_t buffer[sizeof head + sizeof tail + 48];
    MsBytesMut rest = ms_bytes_mut(buffer, sizeof buffer);
    message_append(&rest, head, sizeof head - 1);
    message_append_number(&rest, start);
    message_append(&rest, "..", 2);
    message_append_number(&rest, end);
    message_append(&rest, tail, sizeof tail - 1);
    msrt_fault(buffer, sizeof buffer - rest.len);
}

/* `String.view(start, end)`: the bytes [start, end) borrowed from the receiver, nothing allocated. A bound outside
 * the text or inside a scalar faults. */
void msrt_string_view(const MsStr *s, int64_t start, int64_t end, MsStr *out) {
    MsBytes text = str_bytes(s);
    int64_t length = (int64_t)text.len;
    int64_t first = resolve_bound(start, length);
    int64_t last = resolve_bound(end, length);
    MsBytes piece = {0};
    if (first < 0 || last < first || last > length || !is_boundary(text, (size_t)first) ||
        !is_boundary(text, (size_t)last) || !ms_bytes_slice(text, (size_t)first, (size_t)last, &piece)) {
        fault_view_bounds(start, end);
    }
    *out = piece.len == 0 ? make_empty() : view_of(piece);
}
