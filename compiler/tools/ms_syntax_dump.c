/* ms_syntax_dump MODE FILE...: prints the tokens or the syntax tree of each file in the canonical
 * text form that crates/ms-syntax/examples/c_oracle.rs prints, so the two can be diffed. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms/diag.h"
#include "ms/dump.h"
#include "ms/format.h"
#include "ms/lex.h"
#include "read_file.h"
#ifndef MS_NO_PARSER
#include "ms/ast.h"
#include "ms/parse.h"
#include "ms/walk.h"
#endif

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

#ifndef MS_NO_PARSER
static void put_stmt_id(void *ctx, const MsStmt *s) {
    ms_buf_printf(ctx, "S %u %u\n", s->id, s->pos.offset);
}

static void put_expr_id(void *ctx, const MsExpr *e) {
    ms_buf_printf(ctx, "E %u %u\n", e->id, e->pos.offset);
}

/* The `ids` mode: the node ids of imports, declarations, statements and expressions, in walk
 * order, as the Rust oracle prints them. */
static void dump_node_ids(MsBuf *out, const MsModule *mod) {
    for (uint32_t i = 0; i < mod->nimports; i++) {
        ms_buf_printf(out, "I %u %u\n", mod->imports[i].id, mod->imports[i].pos.offset);
    }
    MsVisitor ids = {.ctx = out, .stmt = put_stmt_id, .expr = put_expr_id};
    for (uint32_t i = 0; i < mod->ndecls; i++) {
        ms_buf_printf(out, "D %u %u\n", mod->decls[i]->id, mod->decls[i]->pos.offset);
        ms_walk_decl(&ids, mod->decls[i]);
    }
    ms_buf_printf(out, "nodes %u\n", mod->node_count);
}
#endif

typedef enum Mode { MODE_AST, MODE_TOKENS, MODE_CODES, MODE_PARTIAL, MODE_IDS, MODE_FORMAT } Mode;

typedef struct Source {
    const char *path;
    char *text;
    size_t len;
} Source;

static void dump_codes(MsBuf *out, MsArena *arena, const Source *src) {
    size_t n = strlen(src->path);
    if (n > 4 && strcmp(src->path + n - 4, ".txt") == 0) {
        print_message_codes(out, src->text, src->len);
        return;
    }
#ifndef MS_NO_PARSER
    MsNames names;
    ms_names_init(&names);
    MsModule mod;
    MsDiag diag;
    if (!ms_parse(arena, &names, src->text, src->len, &mod, &diag)) {
        print_code(out, "parse", diag.message);
    }
    ms_names_free(&names);
#endif
}

static void dump_partial(MsBuf *out, MsArena *arena, const Source *src) {
    MsNames names;
    ms_names_init(&names);
    MsModule mod;
    MsDiagList list;
    ms_parse_partial(arena, &names, src->text, src->len, &mod, &list);
    ms_dump_module(out, &names, &mod);
    ms_buf_printf(out, "nodes %u\n", mod.node_count);
    for (uint32_t k = 0; k < list.len; k++) {
        ms_dump_diag(out, &list.items[k]);
    }
    ms_names_free(&names);
}

static void dump_tokens(MsBuf *out, MsArena *arena, const Source *src) {
    MsLexed lexed;
    MsDiag diag;
    if (!ms_lex(arena, src->text, src->len, &lexed, &diag)) {
        ms_dump_diag(out, &diag);
        return;
    }
    for (size_t k = 0; k < lexed.ntokens; k++) {
        const MsToken *t = &lexed.tokens[k];
        ms_buf_printf(out, "%s %u %u ", ms_tok_str((MsTok)t->kind), t->lo, t->hi);
        ms_dump_pos(out, t->pos);
        ms_buf_putc(out, ' ');
        ms_dump_pos(out, t->end);
        ms_buf_putc(out, '\n');
    }
    for (size_t k = 0; k < lexed.nblocks; k++) {
        ms_buf_printf(out, "block %zu %zu\n", lexed.blocks[k].start, lexed.blocks[k].end);
    }
}

/* The syntax tree, or with MODE_IDS the node ids; a parse error prints as a diagnostic. */
static void dump_tree(MsBuf *out, MsArena *arena, const Source *src, Mode mode) {
#ifndef MS_NO_PARSER
    MsNames names;
    ms_names_init(&names);
    MsModule mod;
    MsDiag diag;
    if (!ms_parse(arena, &names, src->text, src->len, &mod, &diag)) {
        ms_dump_diag(out, &diag);
    } else if (mode == MODE_IDS) {
        dump_node_ids(out, &mod);
    } else {
        ms_dump_module(out, &names, &mod);
        ms_buf_printf(out, "nodes %u\n", mod.node_count);
    }
    ms_names_free(&names);
#endif
}

/* The formatted text, or the diagnostic that stopped the formatter. */
static void dump_format(MsBuf *out, MsArena *arena, const Source *src) {
    MsDiag diag;
    if (!ms_format(arena, src->text, src->len, out, &diag)) {
        ms_dump_diag(out, &diag);
    }
}

static void dump_source(MsBuf *out, const Source *src, Mode mode) {
    ms_buf_printf(out, "=== %s\n", src->path);
    if (!ms_utf8_valid(src->text, src->len)) {
        ms_buf_puts(out, "error invalid-utf8\n");
        return;
    }
    MsArena arena = {0};
    switch (mode) {
    case MODE_CODES:
        dump_codes(out, &arena, src);
        break;
    case MODE_PARTIAL:
        dump_partial(out, &arena, src);
        break;
    case MODE_TOKENS:
        dump_tokens(out, &arena, src);
        break;
    case MODE_AST:
    case MODE_IDS:
        dump_tree(out, &arena, src, mode);
        break;
    case MODE_FORMAT:
        dump_format(out, &arena, src);
        break;
    }
    ms_arena_free(&arena);
}

static bool parse_mode(const char *name, Mode *mode) {
    static const char *const names[] = {"ast", "tokens", "codes", "partial", "ids", "format"};
    for (int i = 0; i < 6; i++) {
        if (strcmp(name, names[i]) == 0) {
            *mode = (Mode)i;
            return true;
        }
    }
    return false;
}

int main(int argc, char **argv) {
    Mode mode = MODE_AST;
    if (argc < 3 || !parse_mode(argv[1], &mode)) {
        fputs("usage: ms_syntax_dump tokens|ast|codes|partial|ids|format FILE...\n", stderr);
        return 2;
    }
    MsBuf out = {0};
    for (int i = 2; i < argc; i++) {
        Source src = {.path = argv[i]};
        src.text = read_whole_file(argv[i], &src.len);
        if (src.text == NULL) {
            fprintf(stderr, "cannot read %s\n", argv[i]);
            ms_buf_free(&out);
            return 1;
        }
        dump_source(&out, &src, mode);
        free(src.text);
        fwrite(out.data, 1, out.len, stdout);
        out.len = 0;
    }
    ms_buf_free(&out);
    return 0;
}
