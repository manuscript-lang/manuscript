/* src/runtime/std/path.c: the @std/os/path natives: a glob compiled once and matched against many values.
 *
 * Syntax: `*`, `?`, `[...]` classes, extended `@(a|b) +(..) ?(..) !(..) *(..)` groups, `{a,b}` and `{1..3}` brace
 * expansion, and `**` path segments. Patterns and values are slash separated; the Windows dialect reads
 * backslashes as slashes first. Matching keeps, per atom, the set of value positions reachable so far, so it never
 * backtracks. The compiled form is a handle that owns every allocation below it (`MsGlobCell`).
 *
 * Limits (a pattern past one is invalid): 4096 bytes, 1025 brace alternatives, 64 nested groups or brace groups.
 * Allocation goes through msrt_alloc; a failed allocation reports STATUS_FAILED and leaks nothing.
 */
#include "ms_rt/alloc.h"
#include "ms_rt/base.h"
#include "ms_rt/path.h"
#include "ms_rt/safe.h"
#include "ms_rt/chars.h"

#include <string.h>

enum {
    STATUS_OK = 0,
    STATUS_INVALID_INPUT = 1,
    STATUS_FAILED = 11,
    MAX_PATTERN_BYTES = 4096,
    MAX_BRACE_RESULTS = 1025,
    MAX_BRACE_RANGE = 1024,
    MAX_NESTING = 64,
    INLINE_WORDS = 2, /* position sets for up to 127 positions live on the stack */
};

/* How a step of parsing or expansion ended. */
typedef enum MsPathResult {
    PATH_OK,
    PATH_INVALID,
    PATH_NO_MEMORY,
} MsPathResult;

/* A String value as the runtime passes it (ms_rt/string.h `ms_str`, whose declaration does not pass the style gate
 * yet): two words, where the top two bits of `tagged` say the bytes are inline (01) or at `ptr`. */
typedef struct MsStringView {
    const uint8_t *ptr;
    uint64_t tagged;
} MsStringView;

/* The bytes of the String value that `value` points to. Borrowed from it. */
static MsBytes string_bytes(const void *value) {
    const MsStringView *s = value;
    bool inline_bytes = (s->tagged >> 62) == 1;
    size_t len = inline_bytes ? (size_t)((s->tagged >> 56) & 15) : (size_t)(s->tagged & (((uint64_t)1 << 31) - 1));
    return ms_bytes_of(inline_bytes ? (const uint8_t *)s : s->ptr, len);
}

/* ---- memory helpers ---- */

/* A zeroed array of `count` elements of `size` bytes; NULL on overflow or failure. Owned by the caller. */
static void *array_new(size_t count, size_t size) {
    size_t bytes = 0;
    if (!ms_size_mul(count, size, &bytes) || bytes == 0) {
        return NULL;
    }
    return msrt_alloc_zeroed(bytes);
}

/* Replaces *array (capacity *capacity) with one of at least `needed` elements, keeping `count` of them.
 * False on failure, leaving the old array in place. */
static MS_NODISCARD bool array_reserve(void **array, size_t *capacity, size_t count, size_t needed, size_t size) {
    if (needed <= *capacity) {
        return true;
    }
    size_t grown = 0;
    if (!ms_size_mul(*capacity == 0 ? 4 : *capacity, 2, &grown)) {
        return false;
    }
    grown = grown < needed ? needed : grown;
    void *fresh = array_new(grown, size);
    if (fresh == NULL) {
        return false;
    }
    size_t bytes = 0;
    if (count != 0 && ms_size_mul(count, size, &bytes)) {
        memcpy(fresh, *array, bytes);
    }
    msrt_free(*array);
    *array = fresh;
    *capacity = grown;
    return true;
}

/* ---- text: owned byte strings for the brace expansion ---- */

typedef struct MsText {
    char *ptr; /* owned */
    size_t len;
} MsText;

typedef struct MsTextList {
    MsText *items; /* owned, each item owned */
    size_t count;
    size_t capacity;
} MsTextList;

static void text_list_free(MsTextList *list) {
    for (size_t i = 0; i < list->count; i++) {
        msrt_free(list->items[i].ptr);
    }
    msrt_free(list->items);
    *list = (MsTextList){0};
}

/* Appends prefix + middle + suffix to the list. */
static MS_NODISCARD bool text_list_push3(MsTextList *list, MsBytes prefix, MsBytes middle, MsBytes suffix) {
    size_t length = 0;
    if (!ms_size_add(prefix.len, middle.len, &length) || !ms_size_add(length, suffix.len, &length)) {
        return false;
    }
    size_t bytes = 0;
    if (!ms_size_add(length, 1, &bytes) || !array_reserve((void **)&list->items, &list->capacity, list->count, list->count + 1, sizeof(MsText))) {
        return false;
    }
    char *text = msrt_alloc(bytes);
    if (text == NULL) {
        return false;
    }
    if (prefix.len != 0) {
        memcpy(text, prefix.ptr, prefix.len);
    }
    if (middle.len != 0) {
        memcpy(text + prefix.len, middle.ptr, middle.len);
    }
    if (suffix.len != 0) {
        memcpy(text + prefix.len + middle.len, suffix.ptr, suffix.len);
    }
    text[length] = '\0';
    list->items[list->count++] = (MsText){.ptr = text, .len = length};
    return true;
}

/* ---- brace expansion ---- */

static MsBytes bytes_range(MsBytes bytes, size_t start, size_t end) {
    MsBytes slice = {0};
    return ms_bytes_slice(bytes, start, end, &slice) ? slice : (MsBytes){0};
}

/* Byte index of the first `{` outside a `[...]` class and not escaped, from `from`; SIZE_MAX when there is none. */
static size_t find_open_brace(MsBytes pattern, size_t from) {
    bool escaped = false;
    bool in_class = false;
    for (size_t i = from; i < pattern.len; i++) {
        uint8_t byte = pattern.ptr[i];
        if (escaped) {
            escaped = false;
        } else if (byte == '\\') {
            escaped = true;
        } else if (byte == '[') {
            in_class = true;
        } else if (byte == ']') {
            in_class = false;
        } else if (byte == '{' && !in_class) {
            return i;
        }
    }
    return SIZE_MAX;
}

/* Index of the `}` matching the `{` at `open`; false when unbalanced. */
static bool find_close_brace(MsBytes pattern, size_t open, size_t *close) {
    size_t depth = 1;
    for (size_t i = open + 1; i < pattern.len; i++) {
        if (pattern.ptr[i] == '{') {
            depth++;
        } else if (pattern.ptr[i] == '}' && --depth == 0) {
            *close = i;
            return true;
        }
    }
    return false;
}

/* Iterates the comma separated parts of a brace group's text: `cursor` starts at 0, and each call yields the next
 * part, skipping commas inside nested braces. False after the last part. */
static bool next_part(MsBytes text, size_t *cursor, MsBytes *part) {
    if (*cursor > text.len) {
        return false;
    }
    int64_t nested = 0;
    size_t start = *cursor;
    size_t i = start;
    for (; i < text.len; i++) {
        uint8_t byte = text.ptr[i];
        if (byte == '{') {
            nested++;
        } else if (byte == '}') {
            nested--;
        } else if (byte == ',' && nested == 0) {
            break;
        }
    }
    *part = bytes_range(text, start, i);
    *cursor = i + 1;
    return true;
}

/* The fields of a range, `lo..hi` or `lo..hi..step`: at most MAX_FIELDS are kept and `count` says how many exist. */
enum { MAX_FIELDS = 4 };
typedef struct MsFields {
    MsBytes items[MAX_FIELDS];
    size_t count;
} MsFields;

static void split_dots(MsBytes text, MsFields *fields) {
    size_t start = 0;
    fields->count = 0;
    for (size_t i = 0; i <= text.len; i++) {
        bool at_dots = i + 1 < text.len && text.ptr[i] == '.' && text.ptr[i + 1] == '.';
        if (i != text.len && !at_dots) {
            continue;
        }
        if (fields->count < MAX_FIELDS) {
            fields->items[fields->count] = bytes_range(text, start, i);
        }
        fields->count++;
        start = i + 2;
        i++;
    }
}

/* Go's strconv.Atoi on bytes: an optional sign, then decimal digits only, no overflow. */
static bool parse_integer(MsBytes text, int64_t *value) {
    size_t i = 0;
    bool negative = false;
    if (text.len != 0 && (text.ptr[0] == '+' || text.ptr[0] == '-')) {
        negative = text.ptr[0] == '-';
        i = 1;
    }
    if (i == text.len) {
        return false;
    }
    uint64_t magnitude = 0;
    for (; i < text.len; i++) {
        uint8_t digit = (uint8_t)(text.ptr[i] - '0');
        if (digit > 9 || magnitude > (UINT64_MAX - digit) / 10) {
            return false;
        }
        magnitude = magnitude * 10 + digit;
    }
    if (magnitude > (negative ? (uint64_t)INT64_MAX + 1 : (uint64_t)INT64_MAX)) {
        return false;
    }
    *value = negative ? (int64_t)(0 - magnitude) : (int64_t)magnitude;
    return true;
}

/* The bounds of a `{lo..hi..step}` range once parsed. */
typedef struct MsRangeSpec {
    int64_t low;
    int64_t high;
    uint64_t step; /* absolute, never 0 */
    bool alphabetic;
    size_t width; /* zero padding, 0 for none */
} MsRangeSpec;

/* Reads the endpoints of a range from its `..` separated fields (two or three). */
static bool parse_range(const MsFields *fields, MsRangeSpec *spec) {
    MsBytes first = fields->items[0];
    MsBytes second = fields->items[1];
    spec->step = 1;
    if (fields->count == 3) {
        int64_t step = 0;
        if (!parse_integer(fields->items[2], &step) || step == 0) {
            return false;
        }
        spec->step = step < 0 ? 0 - (uint64_t)step : (uint64_t)step;
    }
    if (!parse_integer(first, &spec->low) || !parse_integer(second, &spec->high)) {
        if (first.len != 1 || second.len != 1 || !ms_ascii_is_alpha(first.ptr[0]) || !ms_ascii_is_alpha(second.ptr[0])) {
            return false;
        }
        spec->low = first.ptr[0];
        spec->high = second.ptr[0];
        spec->alphabetic = true;
    }
    const int64_t limit = 100000;
    if (spec->low < -limit || spec->low > limit || spec->high < -limit || spec->high > limit) {
        return false;
    }
    uint64_t span = spec->low > spec->high ? (uint64_t)(spec->low - spec->high) : (uint64_t)(spec->high - spec->low);
    if (span / spec->step > MAX_BRACE_RANGE) {
        return false;
    }
    for (size_t i = 0; i < 2; i++) {
        MsBytes endpoint = i == 0 ? first : second;
        size_t skip = endpoint.len != 0 && endpoint.ptr[0] == '-' ? 1 : 0;
        if (endpoint.len - skip > 1 && endpoint.ptr[skip] == '0' && endpoint.len - skip > spec->width) {
            spec->width = endpoint.len - skip;
        }
    }
    return true;
}

/* Writes element `n` of a range into `buffer` (at least 32 bytes) and returns its length. */
static size_t format_range_element(const MsRangeSpec *spec, int64_t n, char *buffer) {
    if (spec->alphabetic) {
        buffer[0] = (char)n;
        return 1;
    }
    char digits[24] = {0};
    size_t count = 0;
    uint64_t magnitude = n < 0 ? 0 - (uint64_t)n : (uint64_t)n;
    do {
        digits[count++] = (char)('0' + magnitude % 10);
        magnitude /= 10;
    } while (magnitude != 0);
    size_t length = 0;
    if (n < 0) {
        buffer[length++] = '-';
    }
    for (size_t pad = count; pad < spec->width; pad++) {
        buffer[length++] = '0';
    }
    while (count != 0) {
        buffer[length++] = digits[--count];
    }
    return length;
}

static MsPathResult expand_braces(MsBytes pattern, size_t depth, MsTextList *out);

/* Expands each alternative text in turn into `out`, with `prefix` and `suffix` around it. */
static MsPathResult expand_alternative(MsBytes prefix, MsBytes middle, MsBytes suffix, size_t depth, MsTextList *out) {
    MsTextList whole = {0};
    MsTextList expanded = {0};
    MsPathResult result = PATH_NO_MEMORY;
    if (!text_list_push3(&whole, prefix, middle, suffix)) {
        goto done;
    }
    MsBytes joined = ms_bytes_of((const uint8_t *)whole.items[0].ptr, whole.items[0].len);
    result = expand_braces(joined, depth + 1, &expanded);
    if (result != PATH_OK) {
        goto done;
    }
    if (out->count + expanded.count > MAX_BRACE_RESULTS) {
        result = PATH_INVALID;
        goto done;
    }
    for (size_t i = 0; i < expanded.count; i++) {
        MsBytes item = ms_bytes_of((const uint8_t *)expanded.items[i].ptr, expanded.items[i].len);
        if (!text_list_push3(out, item, (MsBytes){0}, (MsBytes){0})) {
            result = PATH_NO_MEMORY;
            goto done;
        }
    }
done:
    text_list_free(&whole);
    text_list_free(&expanded);
    return result;
}

/* Expands the elements of a range group. */
static MsPathResult expand_range(MsBytes pattern, size_t open, size_t close, size_t depth, MsTextList *out) {
    MsBytes inside = bytes_range(pattern, open + 1, close);
    MsFields fields = {0};
    MsRangeSpec spec = {0};
    split_dots(inside, &fields);
    if (fields.count < 2 || fields.count > 3 || !parse_range(&fields, &spec)) {
        return PATH_INVALID;
    }
    MsBytes prefix = bytes_range(pattern, 0, open);
    MsBytes suffix = bytes_range(pattern, close + 1, pattern.len);
    int64_t n = spec.low;
    int64_t direction = spec.low > spec.high ? -1 : 1;
    for (;;) {
        char buffer[32] = {0};
        size_t length = format_range_element(&spec, n, buffer);
        MsPathResult result = expand_alternative(prefix, ms_bytes_of((const uint8_t *)buffer, length), suffix, depth, out);
        if (result != PATH_OK) {
            return result;
        }
        uint64_t remaining = direction > 0 ? (uint64_t)(spec.high - n) : (uint64_t)(n - spec.high);
        if (remaining < spec.step) {
            return PATH_OK;
        }
        n += direction * (int64_t)spec.step; /* step <= remaining <= 200000 */
    }
}

/* Expands a group with commas: one alternative per part. */
static MsPathResult expand_parts(MsBytes pattern, size_t open, size_t close, size_t depth, MsTextList *out) {
    MsBytes inside = bytes_range(pattern, open + 1, close);
    MsBytes prefix = bytes_range(pattern, 0, open);
    MsBytes suffix = bytes_range(pattern, close + 1, pattern.len);
    size_t cursor = 0;
    MsBytes part = {0};
    while (next_part(inside, &cursor, &part)) {
        MsPathResult result = expand_alternative(prefix, part, suffix, depth, out);
        if (result != PATH_OK) {
            return result;
        }
    }
    return PATH_OK;
}

static bool has_top_level_comma(MsBytes inside) {
    size_t cursor = 0;
    MsBytes part = {0};
    return next_part(inside, &cursor, &part) && cursor <= inside.len;
}

static bool contains_dots(MsBytes inside) {
    for (size_t i = 0; i + 1 < inside.len; i++) {
        if (inside.ptr[i] == '.' && inside.ptr[i + 1] == '.') {
            return true;
        }
    }
    return false;
}

/* Expands the first brace group of `pattern` that has a comma or a range, and every later one, into `out`. A group
 * with neither stays literal, and the search continues after it. */
static MsPathResult expand_braces(MsBytes pattern, size_t depth, MsTextList *out) {
    if (depth > MAX_NESTING) {
        return PATH_INVALID;
    }
    size_t from = 0;
    for (;;) {
        size_t open = find_open_brace(pattern, from);
        if (open == SIZE_MAX) {
            return text_list_push3(out, pattern, (MsBytes){0}, (MsBytes){0}) ? PATH_OK : PATH_NO_MEMORY;
        }
        size_t close = 0;
        if (!find_close_brace(pattern, open, &close)) {
            return PATH_INVALID;
        }
        MsBytes inside = bytes_range(pattern, open + 1, close);
        if (has_top_level_comma(inside)) {
            return expand_parts(pattern, open, close, depth, out);
        }
        if (contains_dots(inside)) {
            return expand_range(pattern, open, close, depth, out);
        }
        from = close + 1;
    }
}

/* ---- glob syntax tree ---- */

typedef struct MsChars {
    const uint32_t *ptr; /* borrowed */
    size_t len;
} MsChars;

typedef struct MsRange {
    uint32_t low;
    uint32_t high;
} MsRange;

typedef enum MsAtomKind {
    ATOM_STAR,
    ATOM_ANY,
    ATOM_CLASS,
    ATOM_LITERAL,
    ATOM_GROUP,
} MsAtomKind;

typedef struct MsAtom MsAtom;

typedef struct MsSeq {
    MsAtom *atoms; /* owned */
    size_t count;
    size_t capacity;
} MsSeq;

struct MsAtom {
    MsAtomKind kind;
    uint32_t literal;      /* ATOM_LITERAL */
    bool negated;          /* ATOM_CLASS */
    MsRange *ranges;       /* ATOM_CLASS, owned */
    size_t range_count;
    uint32_t group_kind;   /* ATOM_GROUP: one of @ + ? ! * */
    MsSeq *alternatives;   /* ATOM_GROUP, owned, each owned */
    size_t alternative_count;
};

static void seq_free(MsSeq *seq) {
    for (size_t i = 0; i < seq->count; i++) {
        MsAtom *atom = &seq->atoms[i];
        msrt_free(atom->ranges);
        for (size_t a = 0; a < atom->alternative_count; a++) {
            seq_free(&atom->alternatives[a]);
        }
        msrt_free(atom->alternatives);
    }
    msrt_free(seq->atoms);
    *seq = (MsSeq){0};
}

/* Appends a zeroed atom of `kind` and returns it; NULL when out of memory. */
static MsAtom *seq_push(MsSeq *seq, MsAtomKind kind) {
    if (!array_reserve((void **)&seq->atoms, &seq->capacity, seq->count, seq->count + 1, sizeof(MsAtom))) {
        return NULL;
    }
    MsAtom *atom = &seq->atoms[seq->count++];
    atom->kind = kind;
    return atom;
}

static MsChars chars_from(MsChars chars, size_t start) {
    return start <= chars.len ? (MsChars){.ptr = chars.ptr + start, .len = chars.len - start} : (MsChars){0};
}

/* One class member, escaped or plain (Go's path.getEsc): false for an end, `-` or `]`, or when nothing would remain
 * after it, since the class's closing `]` must. */
static bool class_member(MsChars chunk, uint32_t *member, MsChars *rest) {
    if (chunk.len == 0 || chunk.ptr[0] == '-' || chunk.ptr[0] == ']') {
        return false;
    }
    MsChars at = chunk;
    if (at.ptr[0] == '\\') {
        at = chars_from(at, 1);
        if (at.len == 0) {
            return false;
        }
    }
    *member = at.ptr[0];
    *rest = chars_from(at, 1);
    return rest->len != 0;
}

/* Parses the members of a class after its `[` (and `^`), through the closing `]`. */
static MsPathResult parse_class_members(MsChars chunk, MsAtom *atom) {
    size_t capacity = 0;
    for (;;) {
        if (chunk.len != 0 && chunk.ptr[0] == ']' && atom->range_count != 0) {
            return PATH_OK;
        }
        uint32_t low = 0;
        if (!class_member(chunk, &low, &chunk)) {
            return PATH_INVALID;
        }
        uint32_t high = low;
        if (chunk.len != 0 && chunk.ptr[0] == '-') {
            if (!class_member(chars_from(chunk, 1), &high, &chunk)) {
                return PATH_INVALID;
            }
        }
        if (!array_reserve((void **)&atom->ranges, &capacity, atom->range_count, atom->range_count + 1, sizeof(MsRange))) {
            return PATH_NO_MEMORY;
        }
        atom->ranges[atom->range_count++] = (MsRange){.low = low, .high = high};
    }
}

/* Index of the `]` that closes the class opening at the start of `pattern`, skipping escaped characters. */
static bool class_end(MsChars pattern, size_t *end) {
    bool escaped = false;
    for (size_t i = 1; i < pattern.len; i++) {
        if (escaped) {
            escaped = false;
        } else if (pattern.ptr[i] == '\\') {
            escaped = true;
        } else if (pattern.ptr[i] == ']') {
            *end = i;
            return true;
        }
    }
    return false;
}

/* Parses the class at the start of `pattern`; `*length` is the characters it covers. */
static MsPathResult parse_class(MsChars pattern, MsSeq *seq, size_t *length) {
    size_t end = 0;
    if (!class_end(pattern, &end)) {
        return PATH_INVALID;
    }
    MsAtom *atom = seq_push(seq, ATOM_CLASS);
    if (atom == NULL) {
        return PATH_NO_MEMORY;
    }
    size_t members = 1;
    if (pattern.len > 1 && (pattern.ptr[1] == '^' || pattern.ptr[1] == '!')) {
        atom->negated = true;
        members = 2;
    }
    *length = end + 1;
    MsChars token = {.ptr = pattern.ptr, .len = end + 1};
    return parse_class_members(chars_from(token, members), atom);
}

static MsPathResult parse_sequence(MsChars pattern, size_t depth, MsSeq *seq);

static bool is_group_start(MsChars pattern, size_t at) {
    uint32_t c = pattern.ptr[at];
    bool kind = c == '@' || c == '+' || c == '?' || c == '!' || c == '*';
    return kind && at + 1 < pattern.len && pattern.ptr[at + 1] == '(';
}

/* Index of the `)` matching the group whose text starts at `start`. */
static bool group_end(MsChars pattern, size_t start, size_t *end) {
    size_t depth = 1;
    for (size_t i = start; i < pattern.len; i++) {
        if (pattern.ptr[i] == '(') {
            depth++;
        } else if (pattern.ptr[i] == ')' && --depth == 0) {
            *end = i;
            return true;
        }
    }
    return false;
}

/* The next `|` separated alternative of a group's text from `*cursor`; false after the last. */
static bool next_alternative(MsChars inside, size_t *cursor, MsChars *alternative) {
    if (*cursor > inside.len) {
        return false;
    }
    int64_t nested = 0;
    size_t i = *cursor;
    for (; i < inside.len; i++) {
        if (inside.ptr[i] == '(') {
            nested++;
        } else if (inside.ptr[i] == ')') {
            nested--;
        } else if (inside.ptr[i] == '|' && nested == 0) {
            break;
        }
    }
    *alternative = (MsChars){.ptr = inside.ptr + *cursor, .len = i - *cursor};
    *cursor = i + 1;
    return true;
}

/* Parses the group at the start of `pattern`; `*length` is the characters it covers. */
static MsPathResult parse_group(MsChars pattern, size_t depth, MsSeq *seq, size_t *length) {
    size_t end = 0;
    if (depth >= MAX_NESTING || !group_end(pattern, 2, &end)) {
        return PATH_INVALID;
    }
    MsChars inside = {.ptr = pattern.ptr + 2, .len = end - 2};
    size_t count = 0;
    size_t cursor = 0;
    MsChars alternative = {0};
    while (next_alternative(inside, &cursor, &alternative)) {
        count++;
    }
    MsAtom *atom = seq_push(seq, ATOM_GROUP);
    if (atom == NULL) {
        return PATH_NO_MEMORY;
    }
    atom->group_kind = pattern.ptr[0];
    atom->alternatives = array_new(count, sizeof(MsSeq));
    if (atom->alternatives == NULL) {
        return PATH_NO_MEMORY;
    }
    atom->alternative_count = count;
    cursor = 0;
    for (size_t i = 0; next_alternative(inside, &cursor, &alternative); i++) {
        MsPathResult result = parse_sequence(alternative, depth + 1, &atom->alternatives[i]);
        if (result != PATH_OK) {
            return result;
        }
    }
    *length = end + 1;
    return PATH_OK;
}

/* Parses one atom at the start of `pattern` into `seq`; `*length` is the characters it covers. */
static MsPathResult parse_atom(MsChars pattern, size_t depth, MsSeq *seq, size_t *length) {
    uint32_t c = pattern.ptr[0];
    *length = 1;
    if (is_group_start(pattern, 0)) {
        return parse_group(pattern, depth, seq, length);
    }
    if (c == '[') {
        return parse_class(pattern, seq, length);
    }
    MsAtom *atom = NULL;
    if (c == '*') {
        atom = seq_push(seq, ATOM_STAR);
    } else if (c == '?') {
        atom = seq_push(seq, ATOM_ANY);
    } else if (c == '\\') {
        if (pattern.len < 2) {
            return PATH_INVALID;
        }
        atom = seq_push(seq, ATOM_LITERAL);
        if (atom != NULL) {
            atom->literal = pattern.ptr[1];
        }
        *length = 2;
    } else {
        atom = seq_push(seq, ATOM_LITERAL);
        if (atom != NULL) {
            atom->literal = c;
        }
    }
    return atom == NULL ? PATH_NO_MEMORY : PATH_OK;
}

/* Parses `pattern` into `seq`, which the caller frees whatever the result. */
static MsPathResult parse_sequence(MsChars pattern, size_t depth, MsSeq *seq) {
    size_t at = 0;
    while (at < pattern.len) {
        size_t length = 0;
        MsPathResult result = parse_atom(chars_from(pattern, at), depth, seq, &length);
        if (result != PATH_OK) {
            return result;
        }
        at += length;
    }
    return PATH_OK;
}

/* ---- matching: sets of reachable positions ---- */

/* The positions 0..=n a match can have reached. `words` points at `inline_words` for short values, so a set is
 * never copied; `capacity_words` 0 marks a set whose allocation failed, which holds nothing. */
typedef struct MsPositions {
    uint64_t *words; /* owned unless it is inline_words */
    size_t capacity_words;
    uint64_t inline_words[INLINE_WORDS];
} MsPositions;

/* Matching state: the value being matched, and whether any allocation failed. */
typedef struct MsMatch {
    const uint32_t *value;
    size_t length;
    bool failed;
} MsMatch;

static void positions_init(MsMatch *match, MsPositions *set, size_t n) {
    size_t words = n / 64 + 1;
    *set = (MsPositions){0};
    if (words <= INLINE_WORDS) {
        set->words = set->inline_words;
        set->capacity_words = words;
        return;
    }
    set->words = array_new(words, sizeof(uint64_t));
    if (set->words == NULL) {
        match->failed = true;
        return;
    }
    set->capacity_words = words;
}

static void positions_free(MsPositions *set) {
    if (set->words != set->inline_words) {
        msrt_free(set->words);
    }
    set->words = NULL;
    set->capacity_words = 0;
}

static void positions_clear(MsPositions *set) {
    if (set->capacity_words != 0) {
        memset(set->words, 0, set->capacity_words * sizeof(uint64_t));
    }
}

static void positions_insert(MsPositions *set, size_t i) {
    if (i / 64 < set->capacity_words) {
        set->words[i / 64] |= (uint64_t)1 << (i % 64);
    }
}

static void positions_remove(MsPositions *set, size_t i) {
    if (i / 64 < set->capacity_words) {
        set->words[i / 64] &= ~((uint64_t)1 << (i % 64));
    }
}

static bool positions_has(const MsPositions *set, size_t i) {
    return i / 64 < set->capacity_words && ((set->words[i / 64] >> (i % 64)) & 1) == 1;
}

/* The lowest position in the set; false when it is empty. */
static bool positions_first(const MsPositions *set, size_t *first) {
    for (size_t w = 0; w < set->capacity_words; w++) {
        if (set->words[w] != 0) {
            *first = w * 64 + (size_t)__builtin_ctzll(set->words[w]);
            return true;
        }
    }
    return false;
}

static void positions_merge(MsPositions *into, const MsPositions *from) {
    for (size_t w = 0; w < into->capacity_words && w < from->capacity_words; w++) {
        into->words[w] |= from->words[w];
    }
}

/* Replaces the contents of `into` with those of `from`, which has the same capacity unless an allocation failed. */
static void positions_assign(MsPositions *into, const MsPositions *from) {
    positions_clear(into);
    positions_merge(into, from);
}

static void seq_ends(MsMatch *match, const MsSeq *seq, size_t start, MsPositions *out);

static bool class_matches(const MsAtom *atom, uint32_t c) {
    bool inside = false;
    for (size_t i = 0; i < atom->range_count; i++) {
        inside = inside || (atom->ranges[i].low <= c && c <= atom->ranges[i].high);
    }
    return inside != atom->negated;
}

/* The positions after one single-character atom, from each position of `from`. */
static void step_character(const MsMatch *match, const MsAtom *atom, const MsPositions *from, MsPositions *next) {
    for (size_t at = 0; at < match->length; at++) {
        if (!positions_has(from, at)) {
            continue;
        }
        uint32_t c = match->value[at];
        bool accepted = atom->kind == ATOM_ANY || (atom->kind == ATOM_LITERAL && c == atom->literal) ||
                        (atom->kind == ATOM_CLASS && class_matches(atom, c));
        if (accepted) {
            positions_insert(next, at + 1);
        }
    }
}

/* One or more repetitions of a group after `accepted`, closed under another pass of any alternative. */
static void repeat_group(MsMatch *match, const MsAtom *atom, const MsPositions *accepted, size_t at, MsPositions *next) {
    size_t n = match->length;
    MsPositions seen;
    MsPositions pending;
    MsPositions reached;
    positions_init(match, &seen, n);
    positions_init(match, &pending, n);
    positions_init(match, &reached, n);
    positions_insert(&seen, at);
    for (size_t e = 0; e <= n; e++) {
        if (positions_has(accepted, e) && !positions_has(&seen, e)) {
            positions_insert(&seen, e);
            positions_insert(&pending, e);
        }
    }
    size_t position = 0;
    while (positions_first(&pending, &position)) {
        positions_remove(&pending, position);
        for (size_t a = 0; a < atom->alternative_count; a++) {
            positions_clear(&reached);
            seq_ends(match, &atom->alternatives[a], position, &reached);
            for (size_t e = 0; e <= n; e++) {
                if (!positions_has(&reached, e)) {
                    continue;
                }
                positions_insert(next, e);
                if (!positions_has(&seen, e)) {
                    positions_insert(&seen, e);
                    positions_insert(&pending, e);
                }
            }
        }
    }
    positions_free(&seen);
    positions_free(&pending);
    positions_free(&reached);
}

/* The positions after a group atom, from each position of `from`. */
static void step_group(MsMatch *match, const MsAtom *atom, const MsPositions *from, MsPositions *next) {
    size_t n = match->length;
    MsPositions accepted;
    MsPositions reached;
    positions_init(match, &accepted, n);
    positions_init(match, &reached, n);
    for (size_t at = 0; at <= n; at++) {
        if (!positions_has(from, at)) {
            continue;
        }
        positions_clear(&accepted);
        for (size_t a = 0; a < atom->alternative_count; a++) {
            positions_clear(&reached);
            seq_ends(match, &atom->alternatives[a], at, &reached);
            positions_merge(&accepted, &reached);
        }
        if (atom->group_kind == '!') {
            for (size_t e = at; e <= n; e++) {
                if (!positions_has(&accepted, e)) {
                    positions_insert(next, e);
                }
            }
            continue;
        }
        positions_merge(next, &accepted);
        if (atom->group_kind == '?' || atom->group_kind == '*') {
            positions_insert(next, at);
        }
        if (atom->group_kind == '+' || atom->group_kind == '*') {
            repeat_group(match, atom, &accepted, at, next);
        }
    }
    positions_free(&accepted);
    positions_free(&reached);
}

static void step_atom(MsMatch *match, const MsAtom *atom, const MsPositions *from, MsPositions *next) {
    size_t first = 0;
    switch (atom->kind) {
    case ATOM_STAR:
        if (positions_first(from, &first)) {
            for (size_t at = first; at <= match->length; at++) {
                positions_insert(next, at);
            }
        }
        return;
    case ATOM_GROUP:
        step_group(match, atom, from, next);
        return;
    case ATOM_ANY:
    case ATOM_CLASS:
    case ATOM_LITERAL:
        step_character(match, atom, from, next);
        return;
    }
}

/* out = the positions reachable after matching `seq` from `start`. `out` is initialised for this value. */
static void seq_ends(MsMatch *match, const MsSeq *seq, size_t start, MsPositions *out) {
    MsPositions first;
    MsPositions second;
    positions_init(match, &first, match->length);
    positions_init(match, &second, match->length);
    MsPositions *current = &first;
    MsPositions *next = &second;
    positions_insert(current, start);
    size_t any = 0;
    for (size_t i = 0; i < seq->count && positions_first(current, &any); i++) {
        positions_clear(next);
        step_atom(match, &seq->atoms[i], current, next);
        MsPositions *swap = current;
        current = next;
        next = swap;
    }
    positions_assign(out, current);
    positions_free(&first);
    positions_free(&second);
}

/* Whether `seq` matches all of the `length` characters at `value`. */
static bool matches_whole(bool *failed, const MsSeq *seq, const uint32_t *value, size_t length) {
    MsMatch match = {.value = value, .length = length, .failed = false};
    MsPositions ends;
    positions_init(&match, &ends, length);
    seq_ends(&match, seq, 0, &ends);
    bool whole = positions_has(&ends, length);
    positions_free(&ends);
    *failed = *failed || match.failed;
    return whole;
}

/* ---- compiled glob ---- */

typedef struct MsSegment {
    bool double_star;  /* the segment is `**` */
    bool leading_dot;  /* the segment's text starts with `.` */
    MsSeq seq;         /* owned; empty for `**` */
} MsSegment;

typedef struct MsAlternative {
    MsSegment *segments; /* owned */
    size_t count;
} MsAlternative;

typedef struct MsGlobCell {
    MsObj header; /* must be first: the runtime drops the handle through it */
    bool windows;
    MsAlternative *alternatives; /* owned */
    size_t alternative_count;
} MsGlobCell;

_Static_assert(offsetof(MsGlobCell, header) == 0, "the runtime reads the object header at the start of a handle");

static void alternative_free(MsAlternative *alternative) {
    for (size_t i = 0; i < alternative->count; i++) {
        seq_free(&alternative->segments[i].seq);
    }
    msrt_free(alternative->segments);
    *alternative = (MsAlternative){0};
}

static void glob_drop(MsObj *object) {
    MsGlobCell *cell = (MsGlobCell *)object;
    for (size_t i = 0; i < cell->alternative_count; i++) {
        alternative_free(&cell->alternatives[i]);
    }
    msrt_free(cell->alternatives);
    msrt_free(cell);
}

/* The width of the UTF-8 sequence a lead byte starts; 1 for an ASCII or invalid lead. */
static size_t utf8_width(uint8_t lead) {
    if (lead >= 0xF0) {
        return 4;
    }
    if (lead >= 0xE0) {
        return 3;
    }
    return lead >= 0xC0 ? 2 : 1;
}

/* Decodes UTF-8 into code points (an invalid byte becomes U+FFFD). `*chars` is owned by the caller and is NULL for
 * empty text. */
static bool decode_text(MsBytes text, uint32_t **chars, size_t *count) {
    *chars = NULL;
    *count = 0;
    if (text.len == 0) {
        return true;
    }
    uint32_t *decoded = array_new(text.len, sizeof(uint32_t));
    if (decoded == NULL) {
        return false;
    }
    size_t n = 0;
    for (size_t i = 0; i < text.len;) {
        uint8_t lead = text.ptr[i];
        size_t width = utf8_width(lead);
        uint32_t c = width == 1 ? lead : (uint32_t)(lead & (0xFFu >> (width + 1)));
        bool valid = i + width <= text.len;
        for (size_t k = 1; valid && k < width; k++) {
            valid = ms_utf8_is_continuation(text.ptr[i + k]);
            c = (c << 6) | (uint32_t)(text.ptr[i + k] & 0x3F);
        }
        decoded[n++] = valid ? c : 0xFFFDu;
        i += valid ? width : 1;
    }
    *chars = decoded;
    *count = n;
    return true;
}

/* Parses one slash separated segment of an expanded pattern into `segment`. */
static MsPathResult parse_segment(MsBytes text, MsSegment *segment) {
    segment->double_star = text.len == 2 && text.ptr[0] == '*' && text.ptr[1] == '*';
    segment->leading_dot = text.len != 0 && text.ptr[0] == '.';
    if (segment->double_star) {
        return PATH_OK;
    }
    uint32_t *chars = NULL;
    size_t count = 0;
    if (!decode_text(text, &chars, &count)) {
        return PATH_NO_MEMORY;
    }
    MsPathResult result = parse_sequence((MsChars){.ptr = chars, .len = count}, 0, &segment->seq);
    msrt_free(chars);
    return result;
}

/* Parses an expanded pattern (no braces left) into its segments. */
static MsPathResult parse_alternative(MsBytes text, MsAlternative *alternative) {
    size_t segments = 1;
    for (size_t i = 0; i < text.len; i++) {
        segments += text.ptr[i] == '/' ? 1 : 0;
    }
    alternative->segments = array_new(segments, sizeof(MsSegment));
    if (alternative->segments == NULL) {
        return PATH_NO_MEMORY;
    }
    alternative->count = segments;
    size_t start = 0;
    size_t index = 0;
    for (size_t i = 0; i <= text.len; i++) {
        if (i != text.len && text.ptr[i] != '/') {
            continue;
        }
        MsPathResult result = parse_segment(bytes_range(text, start, i), &alternative->segments[index++]);
        if (result != PATH_OK) {
            return result;
        }
        start = i + 1;
    }
    return PATH_OK;
}

/* Fills the cell from `pattern`, with backslashes already read as slashes where the dialect says so. */
static MsPathResult glob_fill(MsGlobCell *cell, MsBytes pattern) {
    MsTextList expanded = {0};
    MsPathResult result = expand_braces(pattern, 0, &expanded);
    if (result == PATH_OK) {
        cell->alternatives = array_new(expanded.count, sizeof(MsAlternative));
        result = cell->alternatives == NULL ? PATH_NO_MEMORY : PATH_OK;
    }
    for (size_t i = 0; result == PATH_OK && i < expanded.count; i++) {
        cell->alternative_count = i + 1;
        MsBytes text = ms_bytes_of((const uint8_t *)expanded.items[i].ptr, expanded.items[i].len);
        result = parse_alternative(text, &cell->alternatives[i]);
    }
    text_list_free(&expanded);
    return result;
}

/* A copy of `text` with each backslash a slash when `windows`, plus a NUL; NULL when out of memory. */
static char *slash_copy(MsBytes text, bool windows) {
    size_t bytes = 0;
    if (!ms_size_add(text.len, 1, &bytes)) {
        return NULL;
    }
    char *copy = msrt_alloc(bytes);
    if (copy == NULL) {
        return NULL;
    }
    for (size_t i = 0; i < text.len; i++) {
        char c = (char)text.ptr[i];
        if (windows && c == '\\') {
            c = (char)'/';
        }
        copy[i] = c;
    }
    copy[text.len] = '\0';
    return copy;
}

static bool has_nul(MsBytes text) {
    return text.len != 0 && memchr(text.ptr, 0, text.len) != NULL;
}

static uint8_t status_of(MsPathResult result) {
    return result == PATH_INVALID ? STATUS_INVALID_INPUT : STATUS_FAILED;
}

uint8_t msstd_path_host_windows(void) {
#ifdef _WIN32
    return 1;
#else
    return 0;
#endif
}

uint8_t msstd_path_compile_glob(uint8_t windows, const void *pattern, MsObj **out) {
    MsBytes text = string_bytes(pattern);
    if (text.len > MAX_PATTERN_BYTES || has_nul(text)) {
        return STATUS_INVALID_INPUT;
    }
    char *slashed = slash_copy(text, windows != 0);
    MsGlobCell *cell = msrt_alloc_zeroed(sizeof *cell);
    MsPathResult result = PATH_NO_MEMORY;
    if (slashed != NULL && cell != NULL) {
        cell->header.drop = glob_drop;
        cell->windows = windows != 0;
        result = glob_fill(cell, ms_bytes_of((const uint8_t *)slashed, text.len));
    }
    msrt_free(slashed);
    if (result != PATH_OK) {
        if (cell != NULL) {
            glob_drop(&cell->header);
        }
        return status_of(result);
    }
    *out = &cell->header;
    return STATUS_OK;
}

/* ---- matching a value ---- */

/* The characters of a value and where each slash separated part starts and ends. */
typedef struct MsParts {
    uint32_t *chars; /* owned */
    size_t *starts;  /* owned, `count` entries */
    size_t *ends;    /* owned, `count` entries */
    size_t count;
} MsParts;

static void parts_free(MsParts *parts) {
    msrt_free(parts->chars);
    msrt_free(parts->starts);
    msrt_free(parts->ends);
    *parts = (MsParts){0};
}

/* Splits `text` (already slashed) into parts of characters. */
static bool parts_split(MsBytes text, MsParts *parts) {
    size_t count = 1;
    for (size_t i = 0; i < text.len; i++) {
        count += text.ptr[i] == '/' ? 1 : 0;
    }
    size_t chars = 0;
    if (!decode_text(text, &parts->chars, &chars)) {
        return false;
    }
    parts->starts = array_new(count, sizeof(size_t));
    parts->ends = array_new(count, sizeof(size_t));
    if (parts->starts == NULL || parts->ends == NULL) {
        return false;
    }
    parts->count = count;
    size_t part = 0;
    size_t start = 0;
    for (size_t i = 0; i < chars; i++) {
        if (parts->chars[i] == '/') {
            parts->starts[part] = start;
            parts->ends[part++] = i;
            start = i + 1;
        }
    }
    parts->starts[part] = start;
    parts->ends[part] = chars;
    return true;
}

/* Whether part j (1-based) is non-empty and starts with a dot, which `*` and `**` do not match. */
static bool part_is_dotted(const MsParts *parts, size_t j) {
    size_t start = parts->starts[j - 1];
    return start < parts->ends[j - 1] && parts->chars[start] == '.';
}

/* Positions 0..=n of `next` after one segment, given those of `previous`. */
static void step_segment(bool *failed, const MsParts *parts, const MsSegment *segment, const MsPositions *previous,
                         MsPositions *next) {
    size_t n = parts->count;
    if (segment->double_star) {
        if (positions_has(previous, 0)) {
            positions_insert(next, 0);
        }
        for (size_t j = 1; j <= n; j++) {
            if (positions_has(previous, j) || (positions_has(next, j - 1) && !part_is_dotted(parts, j))) {
                positions_insert(next, j);
            }
        }
        return;
    }
    for (size_t j = 1; j <= n; j++) {
        bool open = positions_has(previous, j - 1) && (!part_is_dotted(parts, j) || segment->leading_dot);
        size_t from = parts->starts[j - 1];
        if (open && matches_whole(failed, &segment->seq, parts->chars + from, parts->ends[j - 1] - from)) {
            positions_insert(next, j);
        }
    }
}

/* Whether the parts match one expanded alternative of the pattern. */
static bool match_alternative(bool *failed, const MsParts *parts, const MsAlternative *alternative) {
    MsMatch scratch = {.value = NULL, .length = 0, .failed = false};
    MsPositions first;
    MsPositions second;
    positions_init(&scratch, &first, parts->count);
    positions_init(&scratch, &second, parts->count);
    MsPositions *previous = &first;
    MsPositions *next = &second;
    positions_insert(previous, 0);
    for (size_t i = 0; i < alternative->count; i++) {
        positions_clear(next);
        step_segment(failed, parts, &alternative->segments[i], previous, next);
        MsPositions *swap = previous;
        previous = next;
        next = swap;
    }
    bool whole = positions_has(previous, parts->count);
    positions_free(&first);
    positions_free(&second);
    *failed = *failed || scratch.failed;
    return whole;
}

uint8_t msstd_path_glob_matches(const MsObj *glob, const void *value, uint8_t *out) {
    const MsGlobCell *cell = (const MsGlobCell *)glob;
    MsBytes text = string_bytes(value);
    if (has_nul(text)) {
        return STATUS_INVALID_INPUT;
    }
    char *slashed = slash_copy(text, cell->windows);
    MsParts parts = {0};
    bool failed = slashed == NULL || !parts_split(ms_bytes_of((const uint8_t *)slashed, text.len), &parts);
    bool matched = false;
    for (size_t i = 0; !failed && !matched && i < cell->alternative_count; i++) {
        matched = match_alternative(&failed, &parts, &cell->alternatives[i]);
    }
    parts_free(&parts);
    msrt_free(slashed);
    if (failed) {
        return STATUS_FAILED;
    }
    *out = matched ? 1 : 0;
    return STATUS_OK;
}
