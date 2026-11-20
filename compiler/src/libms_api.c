/* Entry points declared in ms/libms.h: the stage table and the parse stage. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms/dump.h"
#include "ms/libms.h"
#include "ms/parse.h"

static const char *const stage_names[MS_STAGE_COUNT] = {"parse", "format", "check", "lower",
                                                        "emit",  "link",   "tool"};

/* The one place that says which stages are ported. */
static const MsImpl stage_table[MS_STAGE_COUNT] = {
    [MS_STAGE_PARSE] = MS_IMPL_C,
};

const char *ms_stage_name(MsStage stage) { return stage_names[stage]; }

MsImpl ms_stage_impl(MsStage stage) {
    /* MS_STAGES="parse=rust,check=c": a comma list of stage=impl. */
    const char *name = ms_stage_name(stage);
    size_t n = strlen(name);
    const char *p = getenv("MS_STAGES");
    while (p != NULL && *p != '\0') {
        size_t item = strcspn(p, ",");
        if (item > n + 1 && strncmp(p, name, n) == 0 && p[n] == '=') {
            return item == n + 2 && p[n + 1] == 'c' ? MS_IMPL_C : MS_IMPL_RUST;
        }
        p += item + (p[item] == ',');
    }
    return stage_table[stage];
}

void ms_compiler_init(MsCompiler *c) {
    memset(&c->arena, 0, sizeof c->arena);
    ms_names_init(&c->names);
}

void ms_compiler_free(MsCompiler *c) {
    ms_names_free(&c->names);
    ms_arena_free(&c->arena);
}

MsStatus ms_load_text(MsCompiler *c, const char *path, const char *text, size_t len, MsSource *out,
                      MsDiag *diag) {
    out->path = path;
    out->text = text;
    out->len = len;
    if (!ms_utf8_valid(text, len)) {
        return MS_ERR_UTF8;
    }
    return ms_parse(&c->arena, &c->names, text, len, &out->module, diag) ? MS_OK : MS_ERR_SYNTAX;
}

MsStatus ms_load_file(MsCompiler *c, const char *path, MsSource *out, MsDiag *diag) {
    FILE *f = fopen(path, "rb");
    if (f == NULL) {
        return MS_ERR_IO;
    }
    size_t cap = 4096, n = 0;
    char *buf = malloc(cap);
    for (;;) {
        n += fread(buf + n, 1, cap - n, f);
        if (n < cap) {
            break;
        }
        cap *= 2;
        buf = realloc(buf, cap);
    }
    bool bad = ferror(f) != 0;
    fclose(f);
    if (bad) {
        free(buf);
        return MS_ERR_IO;
    }
    char *text = ms_arena_strndup(&c->arena, buf, n);
    free(buf);
    return ms_load_text(c, ms_arena_strndup(&c->arena, path, strlen(path)), text, n, out, diag);
}

char *ms_syntax_dump_text(const char *path, const char *text, size_t len, size_t *out_len) {
    MsCompiler c;
    ms_compiler_init(&c);
    MsSource src;
    MsDiag diag;
    MsBuf buf = {0};
    MsStatus st = ms_load_text(&c, path, text, len, &src, &diag);
    char *result = NULL;
    if (st == MS_ERR_SYNTAX) {
        ms_dump_diag(&buf, &diag);
    } else if (st == MS_OK) {
        ms_dump_module(&buf, &c.names, &src.module);
    }
    if (st != MS_ERR_UTF8) {
        result = malloc(buf.len + 1);
        if (buf.len > 0) {
            memcpy(result, buf.data, buf.len);
        }
        result[buf.len] = '\0';
        *out_len = buf.len;
    }
    ms_buf_free(&buf);
    ms_compiler_free(&c);
    return result;
}
