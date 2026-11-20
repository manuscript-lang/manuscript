/* The state of `for piece in text.split(separator)`, which walks the pieces without building the list.
 * Ported from crates/ms-rt/src/string.rs, with one change of design: the Rust iterator owned a private string
 * and rewrote it for every piece; here a piece is a view of the text (an inline copy when it is short), so no
 * piece is allocated or copied. The loop borrows each piece until the next call, and a body that keeps one
 * clones it, which copies a view.
 *
 * The iterator holds copies of the two string values, not references: the loop keeps the strings alive, and a
 * short string's bytes are inside its value, so the copy must be inside the iterator. */
#include "ms_rt/alloc.h"
#include "ms_rt/safe.h"
#include "ms_rt/search.h"
#include "ms_rt/strbuild.h"
#include "ms_rt/utf8.h"
#include "string_slice.h"

struct MsSplitIter {
    MsObj header;
    MsStr text;
    MsStr separator;
    MsNeedle needle; /* the separator, prepared for the text; its pattern points into `separator` */
    size_t position; /* the start of the next piece */
    bool done;
};

static void split_iter_drop(MsObj *object) {
    msrt_free(object);
}

MsSplitIter *msrt_string_split_iter(const MsStr *s, const MsStr *sep) {
    MsSplitIter *iter = msrt_alloc(sizeof *iter);
    iter->header = (MsObj){.clone = NULL, .drop = split_iter_drop};
    iter->text = *s;
    iter->separator = *sep;
    const MsBytes separator = ms_str_bytes(&iter->separator);
    iter->needle = separator.len == 0 ? (MsNeedle){0} : ms_needle_for(separator, ms_str_len(&iter->text));
    iter->position = 0;
    iter->done = false;
    return iter;
}

/* The next piece of a split after each scalar, or none when the text is used up. */
static bool next_scalar(MsSplitIter *iter, MsBytes text, MsBytes *piece) {
    if (iter->position >= text.len) {
        return false;
    }
    const size_t width = ms_utf8_decode(text.ptr + iter->position, text.len - iter->position).width;
    *piece = ms_string_slice(text, iter->position, iter->position + width);
    iter->position += width;
    return true;
}

/* The next piece of a split at a separator; the last one runs to the end of the text. */
static MsBytes next_delimited(MsSplitIter *iter, MsBytes text, MsBytes separator) {
    const MsBytes rest = ms_string_slice(text, iter->position, text.len);
    const size_t at = ms_needle_find(&iter->needle, rest);
    if (at == SIZE_MAX) {
        iter->done = true;
        return rest;
    }
    iter->position += at + separator.len;
    return ms_string_slice(rest, 0, at);
}

uint8_t msrt_split_next(MsSplitIter *iter, MsStr *out) {
    if (iter->done) {
        return 0;
    }
    const MsBytes text = ms_str_bytes(&iter->text);
    const MsBytes separator = ms_str_bytes(&iter->separator);
    MsBytes piece = {0};
    if (separator.len == 0) {
        if (!next_scalar(iter, text, &piece)) {
            iter->done = true;
            return 0;
        }
    } else {
        piece = next_delimited(iter, text, separator);
    }
    *out = ms_str_view_of(piece.ptr, piece.len);
    return 1;
}
