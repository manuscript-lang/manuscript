/* ms_syntax_dump MODE FILE...: prints the tokens or the syntax tree of each file in the canonical
 * text form that crates/ms-syntax/examples/c_oracle.rs prints, so the two can be diffed. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms/diag.h"
#include "ms/dump.h"
#include "ms/lex.h"
#ifndef MS_NO_PARSER
#include "ms/ast.h"
#include "ms/parse.h"
#endif

static bool read_file(const char *path, char **data, size_t *len) {
    FILE *f = fopen(path, "rb");
    if (f == NULL) {
        return false;
    }
    size_t cap = 4096, n = 0;
    char *buf = malloc(cap);
    for (;;) {
        size_t got = fread(buf + n, 1, cap - n, f);
        n += got;
        if (n < cap) {
            break;
        }
        cap *= 2;
        buf = realloc(buf, cap);
    }
    fclose(f);
    *data = buf;
    *len = n;
    return true;
}

static void print_code(MsBuf *out, const char *phase, MsStr message) {
    const char *code = ms_code_for(phase, message);
    const MsSubcode *kind = ms_subcode_for(code, message);
    ms_buf_printf(out, "%s %s\n", code, kind ? kind->info.code : "-");
}

/* Lines of "phase<TAB>message". */
static void print_message_codes(MsBuf *out, const char *src, size_t len) {
    size_t at = 0;
    while (at < len) {
        size_t end = at;
        while (end < len && src[end] != '\n') {
            end++;
        }
        size_t tab = at;
        while (tab < end && src[tab] != '\t') {
            tab++;
        }
        char phase[32] = {0};
        size_t pn = tab - at < sizeof phase - 1 ? tab - at : sizeof phase - 1;
        memcpy(phase, src + at, pn);
        size_t m = tab < end ? tab + 1 : end;
        print_code(out, phase, (MsStr){src + m, (uint32_t)(end - m)});
        at = end + 1;
    }
}

int main(int argc, char **argv) {
    if (argc < 3) {
        fputs("usage: ms_syntax_dump tokens|ast FILE...\n", stderr);
        return 2;
    }
    bool tokens = strcmp(argv[1], "tokens") == 0;
    bool codes = strcmp(argv[1], "codes") == 0;
    bool partial = strcmp(argv[1], "partial") == 0;
    MsBuf out = {0};
    for (int i = 2; i < argc; i++) {
        char *src;
        size_t len;
        if (!read_file(argv[i], &src, &len)) {
            fprintf(stderr, "cannot read %s\n", argv[i]);
            return 1;
        }
        ms_buf_printf(&out, "=== %s\n", argv[i]);
        if (!ms_utf8_valid(src, len)) {
            ms_buf_puts(&out, "error invalid-utf8\n");
            free(src);
            continue;
        }
        MsArena arena = {0};
        MsDiag diag;
        if (codes) {
            size_t n = strlen(argv[i]);
            if (n > 4 && strcmp(argv[i] + n - 4, ".txt") == 0) {
                print_message_codes(&out, src, len);
            } else {
                MsNames names;
                ms_names_init(&names);
                MsModule mod;
                if (!ms_parse(&arena, &names, src, len, &mod, &diag)) {
                    print_code(&out, "parse", diag.message);
                }
                ms_names_free(&names);
            }
        } else if (partial) {
            MsNames names;
            ms_names_init(&names);
            MsModule mod;
            MsDiagList list;
            ms_parse_partial(&arena, &names, src, len, &mod, &list);
            ms_dump_module(&out, &names, &mod);
            ms_buf_printf(&out, "nodes %u\n", mod.node_count);
            for (uint32_t k = 0; k < list.len; k++) {
                ms_dump_diag(&out, &list.items[k]);
            }
            ms_names_free(&names);
        } else if (tokens) {
            MsLexed lexed;
            if (!ms_lex(&arena, src, len, &lexed, &diag)) {
                ms_dump_diag(&out, &diag);
            } else {
                for (size_t k = 0; k < lexed.ntokens; k++) {
                    const MsToken *t = &lexed.tokens[k];
                    ms_buf_printf(&out, "%s %u %u ", ms_tok_str((MsTok)t->kind), t->lo, t->hi);
                    ms_dump_pos(&out, t->pos);
                    ms_buf_putc(&out, ' ');
                    ms_dump_pos(&out, t->end);
                    ms_buf_putc(&out, '\n');
                }
                for (size_t k = 0; k < lexed.nblocks; k++) {
                    ms_buf_printf(&out, "block %zu %zu\n", lexed.blocks[k].start, lexed.blocks[k].end);
                }
            }
        } else {
#ifndef MS_NO_PARSER
            MsNames names;
            ms_names_init(&names);
            MsModule mod;
            if (!ms_parse(&arena, &names, src, len, &mod, &diag)) {
                ms_dump_diag(&out, &diag);
            } else {
                ms_dump_module(&out, &names, &mod);
                ms_buf_printf(&out, "nodes %u\n", mod.node_count);
            }
            ms_names_free(&names);
#endif
        }
        ms_arena_free(&arena);
        free(src);
        fwrite(out.data, 1, out.len, stdout);
        out.len = 0;
    }
    ms_buf_free(&out);
    return 0;
}
