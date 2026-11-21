/* ms_desugar_dump user|std FILE... | ms_desugar_dump foreign FOREIGN FILE...
 *
 * Prints each file's declarations after inherent-impl desugaring, in the form
 * crates/ms-check/examples/c_oracle_desugar.rs prints, so the two can be compared. `std` treats the
 * files as bundled `@std/` modules, and `foreign` lets their methods name the types of FOREIGN. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms/desugar.h"
#include "ms/dump.h"
#include "ms/parse.h"

static char *read_file(const char *path, size_t *length) {
    FILE *file = fopen(path, "rb");
    if (file == NULL) {
        return NULL;
    }
    size_t cap = 4096;
    char *text = malloc(cap);
    *length = 0;
    for (size_t n; (n = fread(text + *length, 1, cap - *length, file)) > 0;) {
        *length += n;
        if (*length == cap) {
            cap *= 2;
            text = realloc(text, cap);
        }
    }
    fclose(file);
    return text;
}

/* The declarations of `module` that are types, for another module's methods to name. */
static MsDecl **foreign_types(MsArena *arena, const MsModule *module, uint32_t *count) {
    MsDecl **types = MS_NEW_N(arena, MsDecl *, module->ndecls);
    *count = 0;
    for (uint32_t i = 0; i < module->ndecls; i++) {
        if (module->decls[i]->kind == MS_D_TYPE || module->decls[i]->kind == MS_D_ENUM) {
            types[(*count)++] = module->decls[i];
        }
    }
    return types;
}

static void print_ids(MsBuf *out, const MsDecl *decl) {
    ms_buf_printf(out, "decl %u", decl->id);
    if (decl->kind == MS_D_IMPL) {
        for (uint32_t i = 0; i < decl->u.impl.methods.len; i++) {
            ms_buf_printf(out, " %u", decl->u.impl.methods.ptr[i]->id);
        }
    } else if (decl->kind == MS_D_INTERFACE) {
        for (uint32_t i = 0; i < decl->u.iface.methods.len; i++) {
            ms_buf_printf(out, " %u", decl->u.iface.methods.ptr[i]->id);
        }
    }
    ms_buf_putc(out, '\n');
}

/* One `method NAME LINE:COL` line for each method of the inherent blocks, sorted. */
static void print_inherent_methods(MsBuf *out, MsNames *names, const MsDesugared *result) {
    char **lines = NULL;
    size_t count = 0;
    for (uint32_t i = 0; i < result->ndecls; i++) {
        if (!ms_decl_is_inherent_impl(result->decls[i])) {
            continue;
        }
        for (uint32_t k = 0; k < result->decls[i]->u.impl.methods.len; k++) {
            const MsMethod *m = result->decls[i]->u.impl.methods.ptr[k];
            const MsStr name = ms_name(names, m->func.name);
            char line[512];
            snprintf(line, sizeof line, "method %.*s %u:%u\n", (int)name.len, name.ptr, m->pos.line, m->pos.column);
            lines = realloc(lines, (count + 1) * sizeof *lines);
            lines[count] = malloc(strlen(line) + 1);
            memcpy(lines[count++], line, strlen(line) + 1);
        }
    }
    if (count > 1) {
        qsort(lines, count, sizeof *lines, ms_cmp_cstr);
    }
    for (size_t i = 0; i < count; i++) {
        ms_buf_puts(out, lines[i]);
        free(lines[i]);
    }
    free(lines);
}

static void print_result(MsBuf *out, MsNames *names, const MsModule *parsed, const MsDesugared *result) {
    MsModule desugared = *parsed;
    MsDecl **kept = malloc((result->ndecls + 1) * sizeof *kept);
    desugared.ndecls = 0;
    for (uint32_t i = 0; i < result->ndecls; i++) {
        if (!ms_decl_is_inherent_impl(result->decls[i])) {
            kept[desugared.ndecls++] = result->decls[i];
        }
    }
    desugared.decls = kept;
    desugared.node_count = result->node_count;
    ms_dump_module(out, names, &desugared);
    for (uint32_t i = 0; i < desugared.ndecls; i++) {
        print_ids(out, kept[i]);
    }
    free(kept);
    print_inherent_methods(out, names, result);
    for (uint32_t i = 0; i < result->nerrors; i++) {
        ms_buf_puts(out, "inherent ");
        ms_dump_pos(out, result->errors[i].pos);
        ms_buf_putc(out, ' ');
        ms_dump_quote(out, result->errors[i].message.ptr, result->errors[i].message.len);
        ms_buf_putc(out, '\n');
    }
}

static void desugar_file(MsBuf *out, MsNames *names, const char *path, const char *file_name,
                         MsDecl **foreign, uint32_t nforeign) {
    printf("=== %s\n", path);
    size_t length = 0;
    char *text = read_file(path, &length);
    if (text == NULL || !ms_utf8_valid(text, length)) {
        puts("error invalid-utf8");
        free(text);
        return;
    }
    MsArena arena = {0};
    MsModule parsed;
    MsDiag diag;
    if (!ms_parse(&arena, names, text, length, &parsed, &diag)) {
        puts("parse-error");
    } else {
        MsDesugarInput in = {{file_name, (uint32_t)strlen(file_name)}, {text, (uint32_t)length}, &parsed, foreign, nforeign};
        MsDesugared result;
        ms_desugar_inherent_impls(&arena, names, &in, &result);
        out->len = 0;
        print_result(out, names, &parsed, &result);
        fwrite(out->data, 1, out->len, stdout);
    }
    ms_arena_free(&arena);
    free(text);
}

int main(int argc, char **argv) {
    if (argc < 3) {
        fputs("usage: ms_desugar_dump user|std FILE... | foreign FOREIGN FILE...\n", stderr);
        return 2;
    }
    bool is_foreign = strcmp(argv[1], "foreign") == 0;
    const char *file_name = strcmp(argv[1], "std") == 0 ? "@std/f.ms" : "f.ms";
    MsNames names;
    ms_names_init(&names);
    MsArena foreign_arena = {0};
    MsDecl **foreign = NULL;
    char *foreign_text = NULL;
    uint32_t nforeign = 0;
    int first = 2;
    if (is_foreign) {
        size_t length = 0;
        char *text = read_file(argv[2], &length);
        foreign_text = text;
        MsModule module;
        MsDiag diag;
        if (text == NULL || !ms_parse(&foreign_arena, &names, text, length, &module, &diag)) {
            fprintf(stderr, "cannot parse %s\n", argv[2]);
            return 1;
        }
        foreign = foreign_types(&foreign_arena, &module, &nforeign);
        first = 3;
    }
    MsBuf out = {0};
    for (int i = first; i < argc; i++) {
        desugar_file(&out, &names, argv[i], file_name, foreign, nforeign);
    }
    ms_buf_free(&out);
    ms_names_free(&names);
    ms_arena_free(&foreign_arena);
    free(foreign_text);
    return 0;
}
