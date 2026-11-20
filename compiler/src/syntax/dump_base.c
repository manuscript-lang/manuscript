#include "ms/dump.h"

void ms_dump_quote(MsBuf *out, const char *s, size_t n) {
    ms_buf_putc(out, '"');
    for (size_t i = 0; i < n; i++) {
        uint8_t c = (uint8_t)s[i];
        if (c >= 0x20 && c < 0x7f && c != '"' && c != '\\') {
            ms_buf_putc(out, (char)c);
        } else {
            ms_buf_printf(out, "\\x%02x", c);
        }
    }
    ms_buf_putc(out, '"');
}

void ms_dump_pos(MsBuf *out, MsPos p) {
    ms_buf_printf(out, "%u:%u:%u", p.line, p.column, p.offset);
}

void ms_dump_diag(MsBuf *out, const MsDiag *d) {
    ms_buf_puts(out, "error ");
    ms_dump_pos(out, d->pos);
    ms_buf_puts(out, " end=");
    if (d->has_end) {
        ms_dump_pos(out, d->end);
    } else {
        ms_buf_putc(out, '-');
    }
    ms_buf_puts(out, " fix=");
    if (d->has_fix) {
        ms_dump_pos(out, d->fix_pos);
        ms_buf_putc(out, '-');
        ms_dump_pos(out, d->fix_end);
        ms_buf_putc(out, '=');
        ms_dump_quote(out, d->replacement.ptr, d->replacement.len);
    } else {
        ms_buf_putc(out, '-');
    }
    ms_buf_printf(out, " opener=%u ", d->opener_line);
    ms_dump_quote(out, d->message.ptr, d->message.len);
    ms_buf_putc(out, '\n');
}
