/* Entry points declared in ms/libms.h: the stage table and the parse stage. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms/dump.h"
#include "ms/libms.h"
#include "ms/parse.h"

static const char *const stage_names[MS_STAGE_COUNT] = {
    [MS_STAGE_PARSE] = "parse", [MS_STAGE_FORMAT] = "format", [MS_STAGE_CHECK] = "check",
    [MS_STAGE_LOWER] = "lower", [MS_STAGE_EMIT] = "emit",     [MS_STAGE_LINK] = "link",
    [MS_STAGE_TOOL] = "tool",
};

const char *ms_stage_name(MsStage stage) { return stage_names[stage]; }

/* The one place that says which stages are ported. */
MsStageTable ms_stage_table_default(void) {
    MsStageTable table = {.impl = {[MS_STAGE_PARSE] = MS_IMPL_C}};
    return table;
}

/* Finds the stage named by the `length` bytes at `name`. */
static bool find_stage(const char *name, size_t length, MsStage *out) {
    for (int stage = 0; stage < MS_STAGE_COUNT; stage++) {
        if (strlen(stage_names[stage]) == length && memcmp(stage_names[stage], name, length) == 0) {
            *out = (MsStage)stage;
            return true;
        }
    }
    return false;
}

/* Parses one "stage=impl" item of `length` bytes. */
static bool parse_override(const char *item, size_t length, MsStageTable *table) {
    const char *equals = memchr(item, '=', length);
    if (equals == NULL) {
        return false;
    }
    const size_t name_length = (size_t)(equals - item);
    const char *impl_name = equals + 1;
    const size_t impl_length = length - name_length - 1;
    MsStage stage = MS_STAGE_PARSE;
    if (!find_stage(item, name_length, &stage)) {
        return false;
    }
    if (impl_length == 1 && impl_name[0] == 'c') {
        table->impl[stage] = MS_IMPL_C;
    } else if (impl_length == 4 && memcmp(impl_name, "rust", 4) == 0) {
        table->impl[stage] = MS_IMPL_RUST;
    } else {
        return false;
    }
    return true;
}

bool ms_stage_table_override(MsStageTable *table, const char *spec) {
    MsStageTable updated = *table;
    while (*spec != '\0') {
        const size_t length = strcspn(spec, ",");
        if (!parse_override(spec, length, &updated)) {
            return false;
        }
        spec += length + (spec[length] == ',' ? 1 : 0);
    }
    *table = updated;
    return true;
}

void ms_compiler_init(MsCompiler *c) {
    c->arena = (MsArena){0};
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

/* Reads all of `file` into a malloc'd buffer (owned by the caller). False on a read error. */
static bool read_all(FILE *file, char **data, size_t *length) {
    size_t capacity = 4096;
    size_t used = 0;
    char *buffer = malloc(capacity);
    if (buffer == NULL) {
        abort();
    }
    for (;;) {
        used += fread(buffer + used, 1, capacity - used, file);
        if (used < capacity) {
            break;
        }
        size_t grown = 0;
        if (!ms_size_mul(capacity, 2, &grown)) {
            abort();
        }
        char *bigger = realloc(buffer, grown);
        if (bigger == NULL) {
            abort();
        }
        buffer = bigger;
        capacity = grown;
    }
    if (ferror(file) != 0) {
        free(buffer);
        return false;
    }
    *data = buffer;
    *length = used;
    return true;
}

MsStatus ms_load_file(MsCompiler *c, const char *path, MsSource *out, MsDiag *diag) {
    // NOLINTNEXTLINE(android-cloexec-fopen): mode "e" is glibc only, and the compiler never forks while reading.
    FILE *file = fopen(path, "rb");
    if (file == NULL) {
        return MS_ERR_IO;
    }
    char *data = NULL;
    size_t length = 0;
    const bool read_ok = read_all(file, &data, &length);
    fclose(file);
    if (!read_ok) {
        return MS_ERR_IO;
    }
    const char *text = ms_arena_strndup(&c->arena, data, length);
    free(data);
    const char *kept_path = ms_arena_strndup(&c->arena, path, strlen(path));
    return ms_load_text(c, kept_path, text, length, out, diag);
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
