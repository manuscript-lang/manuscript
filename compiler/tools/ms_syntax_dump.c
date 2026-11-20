/* ms_syntax_dump MODE FILE...: prints the tokens or the syntax tree of each file in the canonical
 * text form that crates/ms-syntax/examples/c_oracle.rs prints, so the two can be diffed. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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

int main(int argc, char **argv) {
    if (argc < 3) {
        fputs("usage: ms_syntax_dump tokens|ast FILE...\n", stderr);
        return 2;
    }
    bool tokens = strcmp(argv[1], "tokens") == 0;
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
        if (tokens) {
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
