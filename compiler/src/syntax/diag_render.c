/* Diagnostic rendering, byte for byte as crates/ms-cli (diagnostic.rs, snippet.rs, engine/mod.rs):
 * the terminal report and the JSON document. It reads source files for excerpts and owns only what
 * it allocates for one call. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms/diag.h"
#include "ms/diag_render.h"

enum { MS_TAB_WIDTH = 4 };

/* ---- excerpt ---- */

/* The byte offset of the 1-based lexer column in `line`: a leading tab spans four columns, every
 * other byte one. */
static size_t render_byte_index(MsStr line, uint32_t column) {
    size_t target = column > 0 ? column - 1 : 0;
    size_t columns = 0;
    bool leading = true;
    for (uint32_t at = 0; at < line.len;) {
        uint32_t scalar = 0;
        int length = ms_utf8_decode(line.ptr + at, line.len - at, &scalar);
        leading = leading && (scalar == '\t' || scalar == ' ');
        size_t span = leading && scalar == '\t' ? MS_TAB_WIDTH : (size_t)length;
        if (columns + span > target) {
            return at;
        }
        columns += span;
        at += (uint32_t)length;
    }
    return line.len;
}

static size_t render_cell_width(uint32_t c) {
    if (c == '\t') {
        return MS_TAB_WIDTH;
    }
    if ((c >= 0x200b && c <= 0x200f) || (c >= 0x0300 && c <= 0x036f) || (c >= 0xfe00 && c <= 0xfe0f)) {
        return 0;
    }
    bool wide = (c >= 0x1100 && c <= 0x115f) || (c >= 0x2e80 && c <= 0xa4cf) ||
                (c >= 0xac00 && c <= 0xd7a3) || (c >= 0xf900 && c <= 0xfaff) ||
                (c >= 0xfe30 && c <= 0xfe6f) || (c >= 0xff00 && c <= 0xff60) ||
                (c >= 0xffe0 && c <= 0xffe6) || (c >= 0x1f300 && c <= 0x1f64f) ||
                (c >= 0x1f900 && c <= 0x1f9ff) || (c >= 0x20000 && c <= 0x3fffd);
    return wide ? 2 : 1;
}

/* Terminal cells the text occupies, tabs at a fixed width. */
static size_t render_width(MsStr text) {
    size_t cells = 0;
    for (uint32_t at = 0; at < text.len;) {
        uint32_t scalar = 0;
        at += (uint32_t)ms_utf8_decode(text.ptr + at, text.len - at, &scalar);
        cells += render_cell_width(scalar);
    }
    return cells;
}

/* The line as printed: tabs become spaces, a control character its one-cell picture. */
static void render_expand(MsBuf *out, MsStr text) {
    for (uint32_t at = 0; at < text.len;) {
        uint32_t scalar = 0;
        int length = ms_utf8_decode(text.ptr + at, text.len - at, &scalar);
        if (scalar == '\t') {
            ms_buf_puts(out, "    ");
        } else if (scalar < 0x20) {
            ms_utf8_put(out, 0x2400 + scalar);
        } else if (scalar == 0x7f) {
            ms_utf8_put(out, 0x2421);
        } else if (scalar >= 0x80 && scalar <= 0x9f) {
            ms_utf8_put(out, 0xfffd);
        } else {
            ms_buf_put(out, text.ptr + at, (size_t)length);
        }
        at += (uint32_t)length;
    }
}

static void render_repeat(MsBuf *out, char c, size_t count) {
    for (size_t i = 0; i < count; i++) {
        ms_buf_putc(out, c);
    }
}

/* The excerpt of `raw`, line `line` of the file, with the caret span. */
static void render_snippet(MsBuf *out, MsStr raw, uint32_t line, uint32_t column, uint32_t end_line,
                           uint32_t end_column) {
    MsStr source = raw;
    if (source.len > 0 && source.ptr[source.len - 1] == '\r') {
        source.len--;
    }
    size_t start = render_byte_index(source, column);
    size_t stop = start;
    if (end_line == line) {
        stop = render_byte_index(source, end_column);
    } else if (end_line > line) {
        stop = source.len;
    }
    if (stop < start) {
        stop = start;
    }
    size_t indent = render_width((MsStr){source.ptr, (uint32_t)start});
    size_t marks = render_width((MsStr){source.ptr + start, (uint32_t)(stop - start)});
    if (marks < 1) {
        marks = 1;
    }
    char number[16];
    int digits = snprintf(number, sizeof number, "%u", line);
    ms_buf_puts(out, "\n ");
    render_repeat(out, ' ', (size_t)digits);
    ms_buf_puts(out, " |\n ");
    ms_buf_puts(out, number);
    ms_buf_puts(out, " | ");
    render_expand(out, source);
    ms_buf_puts(out, "\n ");
    render_repeat(out, ' ', (size_t)digits);
    ms_buf_puts(out, " | ");
    render_repeat(out, ' ', indent);
    render_repeat(out, '^', marks);
}

void ms_render_excerpt(MsBuf *out, MsStr text, uint32_t line, uint32_t column, uint32_t end_line,
                       uint32_t end_column) {
    if (line == 0) {
        return;
    }
    size_t start = 0;
    for (uint32_t seen = 1; seen < line; seen++) {
        const char *newline = start < text.len ? memchr(text.ptr + start, '\n', text.len - start) : NULL;
        if (newline == NULL) {
            return;
        }
        start = (size_t)(newline - text.ptr) + 1;
    }
    if (start > text.len) {
        return;
    }
    const char *newline = memchr(text.ptr + start, '\n', text.len - start);
    size_t stop = newline != NULL ? (size_t)(newline - text.ptr) : text.len;
    render_snippet(out, (MsStr){text.ptr + start, (uint32_t)(stop - start)}, line, column, end_line, end_column);
}

/* ---- the sources of one report ---- */

/* One file read for its excerpts; unreadable or non-UTF-8 files give none. */
typedef struct RenderSource {
    char *path; /* owned */
    char *text; /* owned, NULL when unreadable */
    size_t len;
} RenderSource;

static void render_source_free(RenderSource *source) {
    free(source->path);
    free(source->text);
    *source = (RenderSource){0};
}

static void render_source_open(RenderSource *source, const char *path) {
    render_source_free(source);
    size_t path_len = strlen(path) + 1;
    source->path = malloc(path_len);
    if (source->path == NULL) {
        ms_oom();
    }
    memcpy(source->path, path, path_len);
    // NOLINTNEXTLINE(android-cloexec-fopen): mode "e" is glibc only, and the compiler never forks while reading.
    FILE *f = fopen(path, "rb");
    if (f == NULL) {
        return;
    }
    MsBuf bytes = {0};
    char chunk[4096];
    size_t n = 0;
    while ((n = fread(chunk, 1, sizeof chunk, f)) > 0) {
        ms_buf_put(&bytes, chunk, n);
    }
    fclose(f);
    if (bytes.data != NULL && ms_utf8_valid(bytes.data, bytes.len)) {
        source->text = bytes.data;
        source->len = bytes.len;
    } else {
        ms_buf_free(&bytes);
    }
}

static const char *render_shown(const MsReport *r) {
    return r->shown != NULL ? r->shown : r->file;
}

/* ---- order ---- */

typedef struct RenderOrder {
    const MsReport *report;
    size_t index;
} RenderOrder;

/* By file, line and column; ties keep the order the phases produced them in. */
static int render_compare(const void *a, const void *b) {
    const RenderOrder *x = a;
    const RenderOrder *y = b;
    int by_file = strcmp(x->report->file, y->report->file);
    if (by_file != 0) {
        return by_file;
    }
    if (x->report->diag.pos.line != y->report->diag.pos.line) {
        return x->report->diag.pos.line < y->report->diag.pos.line ? -1 : 1;
    }
    if (x->report->diag.pos.column != y->report->diag.pos.column) {
        return x->report->diag.pos.column < y->report->diag.pos.column ? -1 : 1;
    }
    if (x->index != y->index) {
        return x->index < y->index ? -1 : 1;
    }
    return 0;
}

static RenderOrder *render_sorted(const MsReport *items, size_t count) {
    RenderOrder *order = malloc((count > 0 ? count : 1) * sizeof *order);
    if (order == NULL) {
        ms_oom();
    }
    for (size_t i = 0; i < count; i++) {
        order[i] = (RenderOrder){&items[i], i};
    }
    qsort(order, count, sizeof *order, render_compare);
    return order;
}

/* ---- text ---- */

void ms_render_text(MsBuf *out, const MsReport *items, size_t count) {
    RenderOrder *order = render_sorted(items, count);
    RenderSource source = {0};
    for (size_t i = 0; i < count; i++) {
        const MsReport *r = order[i].report;
        const char *shown = render_shown(r);
        ms_buf_printf(out, "%s:%u:%u: %s: %.*s", shown, r->diag.pos.line, r->diag.pos.column, r->phase,
                      (int)r->diag.message.len, r->diag.message.ptr);
        if (source.path == NULL || strcmp(source.path, shown) != 0) {
            render_source_open(&source, shown);
        }
        if (source.text != NULL) {
            ms_render_excerpt(out, (MsStr){source.text, (uint32_t)source.len}, r->diag.pos.line,
                              r->diag.pos.column, r->diag.has_end ? r->diag.end.line : 0,
                              r->diag.has_end ? r->diag.end.column : 0);
        }
        ms_buf_putc(out, '\n');
    }
    render_source_free(&source);
    free(order);
    ms_buf_printf(out,
                  "%zu %s; fix them and re-run (ms check <file> --json gives the same diagnostics as structured data)\n",
                  count, count == 1 ? "error" : "errors");
}

/* ---- json ---- */

/* A JSON string as Go's encoder with HTML escaping writes it. */
static void render_json_string(MsBuf *out, MsStr text) {
    ms_buf_putc(out, '"');
    for (uint32_t at = 0; at < text.len;) {
        uint32_t c = 0;
        int length = ms_utf8_decode(text.ptr + at, text.len - at, &c);
        switch (c) {
        case '"': ms_buf_puts(out, "\\\""); break;
        case '\\': ms_buf_puts(out, "\\\\"); break;
        case '\n': ms_buf_puts(out, "\\n"); break;
        case '\r': ms_buf_puts(out, "\\r"); break;
        case '\t': ms_buf_puts(out, "\\t"); break;
        case 0x08: ms_buf_puts(out, "\\b"); break;
        case 0x0c: ms_buf_puts(out, "\\f"); break;
        case '<':
        case '>':
        case '&':
        case 0x2028:
        case 0x2029: ms_buf_printf(out, "\\u%04x", c); break;
        default:
            if (c < 0x20) {
                ms_buf_printf(out, "\\u%04x", c);
            } else {
                ms_buf_put(out, text.ptr + at, (size_t)length);
            }
        }
        at += (uint32_t)length;
    }
    ms_buf_putc(out, '"');
}

static void render_json_text(MsBuf *out, const char *text) {
    render_json_string(out, (MsStr){text, (uint32_t)strlen(text)});
}

/* `{file, line, column, offset}` as an object whose members sit `depth` levels deep. */
static void render_json_position(MsBuf *out, const char *file, MsPos pos, int depth) {
    ms_buf_puts(out, "{\n");
    render_repeat(out, ' ', (size_t)(depth + 1) * 2);
    ms_buf_puts(out, "\"file\": ");
    render_json_text(out, file);
    ms_buf_printf(out, ",\n%*s\"line\": %u,\n%*s\"column\": %u,\n%*s\"offset\": %u\n%*s}", (depth + 1) * 2, "",
                  pos.line, (depth + 1) * 2, "", pos.column, (depth + 1) * 2, "", pos.offset, depth * 2, "");
}

static void render_json_diag(MsBuf *out, const MsReport *r) {
    const MsDiag *d = &r->diag;
    const char *family = ms_code_for(r->phase, d->message);
    const MsSubcode *kind = ms_subcode_for(family, d->message);
    ms_buf_puts(out, "    {\n      \"code\": ");
    render_json_text(out, family);
    if (kind != NULL) {
        ms_buf_puts(out, ",\n      \"subcode\": ");
        render_json_text(out, kind->info.code);
    }
    if (r->phase[0] != 0) {
        ms_buf_puts(out, ",\n      \"phase\": ");
        render_json_text(out, r->phase);
    }
    ms_buf_puts(out, ",\n      \"message\": ");
    render_json_string(out, d->message);
    ms_buf_puts(out, ",\n      \"position\": ");
    render_json_position(out, r->file, d->pos, 3);
    if (d->has_end) {
        ms_buf_puts(out, ",\n      \"end\": ");
        render_json_position(out, r->file, d->end, 3);
    }
    if (d->has_fix) {
        ms_buf_puts(out, ",\n      \"fix\": {\n        \"position\": ");
        render_json_position(out, r->file, d->fix_pos, 4);
        ms_buf_puts(out, ",\n        \"end\": ");
        render_json_position(out, r->file, d->fix_end, 4);
        ms_buf_puts(out, ",\n        \"replacement\": ");
        render_json_string(out, d->replacement);
        ms_buf_puts(out, "\n      }");
    }
    ms_buf_puts(out, "\n    }");
}

void ms_render_json(MsBuf *out, const MsReport *items, size_t count) {
    RenderOrder *order = render_sorted(items, count);
    ms_buf_puts(out, "{\n  \"format\": 1,\n  \"diagnostics\": [");
    for (size_t i = 0; i < count; i++) {
        ms_buf_puts(out, i == 0 ? "\n" : ",\n");
        render_json_diag(out, order[i].report);
    }
    ms_buf_puts(out, count > 0 ? "\n  ]\n}\n" : "]\n}\n");
    free(order);
}
