/* String.normalize and NormalizationForm.normalize: Unicode normalization forms C, D, KC and KD over the generated
 * tables (ucd.h). Text already in the form is copied after one quick-check scan. Otherwise the text is cut into
 * segments that start at a scalar nothing before it can combine with; each segment is decomposed, put in canonical
 * order and, for the composing forms, recomposed before it is written. Hangul syllables are arithmetic, not table
 * entries. */
#include "ms_rt/alloc.h"
#include "ms_rt/strbuild.h"
#include "ms_rt/utf8.h"
#include "ucd.h"

enum { FORM_NFC = 0, FORM_NFD = 1, FORM_NFKC = 2, FORM_NFKD = 3 };

enum {
    HANGUL_S_BASE = 0xAC00,
    HANGUL_L_BASE = 0x1100,
    HANGUL_V_BASE = 0x1161,
    HANGUL_T_BASE = 0x11A7,
    HANGUL_L_COUNT = 19,
    HANGUL_V_COUNT = 21,
    HANGUL_T_COUNT = 28,
    HANGUL_S_COUNT = HANGUL_L_COUNT * HANGUL_V_COUNT * HANGUL_T_COUNT,
    MAX_DECOMPOSED = 32, /* the longest full compatibility decomposition has 18 scalars */
    SEGMENT_INLINE = 48,
    SORT_INSERTION_MAX = 32
};

typedef struct MsNormForm {
    bool compat; /* decompose with compatibility mappings */
    bool compose;
    uint32_t not_yes; /* the quick-check flag of the form */
} MsNormForm;

static MsNormForm form_of(int64_t kind) {
    switch (kind) {
    case FORM_NFC:
        return (MsNormForm){false, true, MS_UCD_NFC_NOT_YES};
    case FORM_NFD:
        return (MsNormForm){false, false, MS_UCD_NFD_NOT_YES};
    case FORM_NFKC:
        return (MsNormForm){true, true, MS_UCD_NFKC_NOT_YES};
    default:
        return (MsNormForm){true, false, MS_UCD_NFKD_NOT_YES};
    }
}

static inline uint32_t combining_class(uint32_t info) { return info & 0xFFu; }

/* Whether the text is already in the form: it is well-formed, every scalar passes the form's quick check and the
 * combining classes do not fall within a run of marks. */
static bool is_normalized(MsBytes text, const MsNormForm *form) {
    uint32_t previous = 0;
    size_t at = 0;
    while (at < text.len) {
        if (text.ptr[at] < 0x80) {
            previous = 0;
            at++;
            continue;
        }
        const MsRune scalar = ms_utf8_decode_multi(text.ptr + at, text.len - at);
        if (scalar.rune == MS_RUNE_ERROR && scalar.width == 1) {
            return false; /* a malformed byte becomes U+FFFD, so the text changes */
        }
        const uint32_t info = ms_ucd_norm_of(scalar.rune)[0];
        const uint32_t class = combining_class(info);
        if ((info & form->not_yes) != 0 || (class != 0 && class < previous)) {
            return false;
        }
        previous = class;
        at += scalar.width;
    }
    return true;
}

/* The scalars (in `scalars`, at most MAX_DECOMPOSED) that replace `scalar` in the form, and how many. */
static size_t decompose(uint32_t scalar, const uint16_t *record, bool compat, uint32_t *scalars) {
    const uint32_t hangul = scalar - HANGUL_S_BASE;
    if (hangul < HANGUL_S_COUNT) {
        const uint32_t trailing = hangul % HANGUL_T_COUNT;
        scalars[0] = HANGUL_L_BASE + hangul / (HANGUL_V_COUNT * HANGUL_T_COUNT);
        scalars[1] = HANGUL_V_BASE + hangul % (HANGUL_V_COUNT * HANGUL_T_COUNT) / HANGUL_T_COUNT;
        if (trailing == 0) {
            return 2;
        }
        scalars[2] = HANGUL_T_BASE + trailing;
        return 3;
    }
    const uint32_t canonical_units = record[2] & 15u;
    const uint32_t compat_units = (uint32_t)record[2] >> 4;
    uint32_t offset = record[1];
    uint32_t units = canonical_units;
    if (compat && compat_units != 0) {
        offset += canonical_units;
        units = compat_units;
    }
    if (units == 0) {
        scalars[0] = scalar;
        return 1;
    }
    size_t count = 0;
    for (uint32_t i = 0; i < units; i++) {
        uint32_t unit = ms_ucd_pool[offset + i];
        if (unit >= 0xD800u && unit < 0xDC00u) {
            i++;
            unit = 0x10000u + ((unit - 0xD800u) << 10) + (ms_ucd_pool[offset + i] - 0xDC00u);
        }
        scalars[count++] = unit;
    }
    return count;
}

/* The scalars of one segment with their records' `info` words (class in the low byte). */
typedef struct MsSegment {
    uint32_t *scalars; /* inline storage or an owned heap block */
    uint16_t *infos;
    size_t len;
    size_t cap;
    uint32_t inline_scalars[SEGMENT_INLINE];
    uint16_t inline_infos[SEGMENT_INLINE];
} MsSegment;

static void segment_init(MsSegment *segment) {
    segment->scalars = segment->inline_scalars;
    segment->infos = segment->inline_infos;
    segment->len = 0;
    segment->cap = SEGMENT_INLINE;
}

static void segment_free(MsSegment *segment) {
    if (segment->scalars != segment->inline_scalars) {
        msrt_free(segment->scalars);
        msrt_free(segment->infos);
    }
    segment->scalars = segment->inline_scalars;
    segment->infos = segment->inline_infos;
    segment->cap = SEGMENT_INLINE;
}

static void segment_grow(MsSegment *segment) {
    size_t cap = 0, scalar_bytes = 0, info_bytes = 0;
    if (!ms_size_mul(segment->cap, 2, &cap) || !ms_size_mul(cap, sizeof(uint32_t), &scalar_bytes) ||
        !ms_size_mul(cap, sizeof(uint16_t), &info_bytes)) {
        ms_limit_fault();
    }
    uint32_t *scalars = msrt_alloc(scalar_bytes);
    uint16_t *infos = msrt_alloc(info_bytes);
    __builtin_memcpy(scalars, segment->scalars, segment->len * sizeof(uint32_t));
    __builtin_memcpy(infos, segment->infos, segment->len * sizeof(uint16_t));
    if (segment->scalars != segment->inline_scalars) {
        msrt_free(segment->scalars);
        msrt_free(segment->infos);
    }
    segment->scalars = scalars;
    segment->infos = infos;
    segment->cap = cap;
}

static void segment_push(MsSegment *segment, uint32_t scalar, uint16_t info) {
    if (segment->len == segment->cap) {
        segment_grow(segment);
    }
    segment->scalars[segment->len] = scalar;
    segment->infos[segment->len] = info;
    segment->len++;
}

/* Puts the run of marks scalars[from, to) in canonical order: stable by combining class. */
static void sort_marks_insertion(MsSegment *segment, size_t from, size_t to) {
    for (size_t i = from + 1; i < to; i++) {
        const uint32_t scalar = segment->scalars[i];
        const uint16_t info = segment->infos[i];
        size_t at = i;
        while (at > from && combining_class(segment->infos[at - 1]) > combining_class(info)) {
            segment->scalars[at] = segment->scalars[at - 1];
            segment->infos[at] = segment->infos[at - 1];
            at--;
        }
        segment->scalars[at] = scalar;
        segment->infos[at] = info;
    }
}

/* The same for a long run: a stable counting sort by class, through a copy of the run. */
static void sort_marks_counting(MsSegment *segment, size_t from, size_t to) {
    const size_t count = to - from;
    uint32_t *scalars = msrt_alloc(count * sizeof(uint32_t));
    uint16_t *infos = msrt_alloc(count * sizeof(uint16_t));
    size_t starts[257] = {0};
    for (size_t i = from; i < to; i++) {
        starts[combining_class(segment->infos[i]) + 1]++;
    }
    for (size_t class = 0; class < 256; class++) {
        starts[class + 1] += starts[class];
    }
    for (size_t i = from; i < to; i++) {
        const size_t place = starts[combining_class(segment->infos[i])]++;
        scalars[place] = segment->scalars[i];
        infos[place] = segment->infos[i];
    }
    __builtin_memcpy(segment->scalars + from, scalars, count * sizeof(uint32_t));
    __builtin_memcpy(segment->infos + from, infos, count * sizeof(uint16_t));
    msrt_free(scalars);
    msrt_free(infos);
}

static void reorder(MsSegment *segment) {
    size_t at = 0;
    while (at < segment->len) {
        if (combining_class(segment->infos[at]) == 0) {
            at++;
            continue;
        }
        size_t end = at + 1;
        while (end < segment->len && combining_class(segment->infos[end]) != 0) {
            end++;
        }
        if (end - at <= SORT_INSERTION_MAX) {
            sort_marks_insertion(segment, at, end);
        } else {
            sort_marks_counting(segment, at, end);
        }
        at = end;
    }
}

/* The composite of the pair, or 0 when the two do not compose. Hangul is arithmetic; other pairs are in the sorted
 * table of primary composites. */
static uint32_t compose_pair(uint32_t first, uint32_t second) {
    const uint32_t leading = first - HANGUL_L_BASE;
    if (leading < HANGUL_L_COUNT) {
        const uint32_t vowel = second - HANGUL_V_BASE;
        return vowel < HANGUL_V_COUNT ? HANGUL_S_BASE + (leading * HANGUL_V_COUNT + vowel) * HANGUL_T_COUNT : 0;
    }
    const uint32_t syllable = first - HANGUL_S_BASE;
    if (syllable < HANGUL_S_COUNT && syllable % HANGUL_T_COUNT == 0) {
        const uint32_t trailing = second - HANGUL_T_BASE;
        return trailing < HANGUL_T_COUNT && trailing != 0 ? first + trailing : 0;
    }
    const uint64_t key = ((uint64_t)first << 21) | second;
    size_t low = 0, high = MS_UCD_COMP_COUNT;
    while (low < high) {
        const size_t middle = low + (high - low) / 2;
        if (ms_ucd_comp_key[middle] < key) {
            low = middle + 1;
        } else {
            high = middle;
        }
    }
    return low < MS_UCD_COMP_COUNT && ms_ucd_comp_key[low] == key ? ms_ucd_comp_value[low] : 0;
}

/* Whether the pair can compose at all, from the records' flags (Hangul jamo carry them too). */
static inline bool may_compose(uint16_t first_info, uint16_t second_info) {
    return (first_info & MS_UCD_COMP_FIRST) != 0 && (second_info & MS_UCD_COMP_SECOND) != 0;
}

/* Canonical composition of an ordered segment (UAX #15): each scalar combines with the last starter unless a mark of
 * the same or a higher class sits between them. */
static void compose(MsSegment *segment) {
    size_t written = 0;
    size_t starter = SIZE_MAX;
    uint32_t last_class = 0;
    for (size_t read = 0; read < segment->len; read++) {
        const uint32_t scalar = segment->scalars[read];
        const uint16_t info = segment->infos[read];
        const uint32_t class = combining_class(info);
        if (starter != SIZE_MAX && (last_class < class || last_class == 0) &&
            may_compose(segment->infos[starter], info)) {
            const uint32_t composite = compose_pair(segment->scalars[starter], scalar);
            if (composite != 0) {
                segment->scalars[starter] = composite;
                segment->infos[starter] = ms_ucd_norm_of(composite)[0];
                continue;
            }
        }
        if (class == 0) {
            starter = written;
        }
        last_class = class;
        segment->scalars[written] = scalar;
        segment->infos[written] = info;
        written++;
    }
    segment->len = written;
}

typedef struct MsNormState {
    MsNormForm form;
    MsSegment segment;
    MsUtf8Out *out;
} MsNormState;

/* Writes the finished segment and empties it; false when the text passes its limit. */
MS_NODISCARD static bool flush(MsNormState *state) {
    MsSegment *segment = &state->segment;
    if (segment->len > 1) {
        reorder(segment);
        if (state->form.compose) {
            compose(segment);
        }
    }
    for (size_t i = 0; i < segment->len; i++) {
        if (!ms_utf8_out_scalar(state->out, segment->scalars[i])) {
            return false;
        }
    }
    segment->len = 0;
    return true;
}

/* Whether a scalar with these flags starts a segment: nothing before it can reorder with or combine into it. */
static inline bool starts_segment(const MsNormForm *form, uint16_t info) {
    return combining_class(info) == 0 && !(form->compose && (info & MS_UCD_COMP_SECOND) != 0);
}

MS_NODISCARD static bool add_scalar(MsNormState *state, uint32_t scalar, uint16_t info) {
    if (starts_segment(&state->form, info) && !flush(state)) {
        return false;
    }
    segment_push(&state->segment, scalar, info);
    return true;
}

/* Normalizes one input scalar into the segment; false when the text passes its limit. */
MS_NODISCARD static bool add_decomposed(MsNormState *state, uint32_t scalar) {
    const uint16_t *record = ms_ucd_norm_of(scalar);
    uint32_t parts[MAX_DECOMPOSED];
    const size_t count = decompose(scalar, record, state->form.compat, parts);
    for (size_t i = 0; i < count; i++) {
        const uint16_t info = parts[i] == scalar ? record[0] : ms_ucd_norm_of(parts[i])[0];
        if (!add_scalar(state, parts[i], info)) {
            return false;
        }
    }
    return true;
}

static bool normalize_text(MsBytes text, MsNormState *state) {
    size_t at = 0;
    while (at < text.len) {
        const uint8_t byte = text.ptr[at];
        /* ASCII scalars before another ASCII scalar are segments of their own: write the run in one piece, keeping
         * its last scalar back when a non-ASCII one follows, since that may combine with it. */
        if (byte < 0x80) {
            size_t end = at + 1;
            while (end < text.len && text.ptr[end] < 0x80) {
                end++;
            }
            const size_t direct = end == text.len ? end - at : end - at - 1;
            if (direct > 0) {
                if (!flush(state) || !ms_utf8_out_bytes(state->out, text.ptr + at, direct)) {
                    return false;
                }
                at += direct;
                continue;
            }
        }
        const MsRune scalar = ms_utf8_decode(text.ptr + at, text.len - at);
        if (!add_decomposed(state, scalar.rune)) {
            return false;
        }
        at += scalar.width;
    }
    return flush(state);
}

/* The form of `s` into `out`; MS_STATUS_LIMIT_EXCEEDED when the result is longer than `limit` bytes. */
static uint8_t normalize_to(const MsStr *s, int64_t kind, size_t limit, MsStr *out) {
    const MsBytes text = ms_str_bytes(s);
    const MsNormForm form = form_of(kind);
    if (ms_str_is_ascii(s) || is_normalized(text, &form)) {
        if (text.len > limit) {
            return MS_STATUS_LIMIT_EXCEEDED;
        }
        ms_str_write(ms_str_cloned(s), out);
        return MS_STATUS_OK;
    }
    MsUtf8Out buffer;
    ms_utf8_out_init(&buffer, text.len, limit);
    MsNormState state = {.form = form, .out = &buffer};
    segment_init(&state.segment);
    const bool fits = normalize_text(text, &state);
    segment_free(&state.segment);
    if (!fits) {
        ms_utf8_out_free(&buffer);
        return MS_STATUS_LIMIT_EXCEEDED;
    }
    ms_str_write(ms_utf8_out_finish(&buffer), out);
    return MS_STATUS_OK;
}

static size_t limit_of(uint8_t has_max, int64_t max) { return has_max != 0 ? (size_t)max : SIZE_MAX; }

uint8_t msrt_string_normalize_kind(const MsStr *s, int64_t kind, uint8_t has_max, int64_t max, MsStr *out) {
    if (has_max != 0 && max < 0) {
        return MS_STATUS_INVALID_INPUT;
    }
    return normalize_to(s, kind, limit_of(has_max, max), out);
}

uint8_t msrt_string_normalize(const MsStr *s, const MsStr *form, uint8_t has_max, int64_t max, MsStr *out) {
    if (has_max != 0 && max < 0) {
        return MS_STATUS_INVALID_INPUT;
    }
    const MsBytes name = ms_str_bytes(form);
    static const char *const names[] = {"NFC", "NFD", "NFKC", "NFKD"};
    for (int64_t kind = 0; kind < 4; kind++) {
        const size_t length = kind < 2 ? 3 : 4;
        if (name.len == length && __builtin_memcmp(name.ptr, names[kind], length) == 0) {
            return normalize_to(s, kind, limit_of(has_max, max), out);
        }
    }
    return MS_STATUS_INVALID_INPUT;
}
