/* ms_constfold_dump: answers stdin expressions the way crates/ms-syntax/examples/c_fold_oracle.rs
 * does, node by node, so constfold.c can be diffed against the Rust folding. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms/constfold.h"
#include "ms/parse.h"
#include "dump_io.h"

typedef struct Range {
    const char *name;
    MsInt128 lo, hi;
} Range;

#define INT64_LEAST (-(MsInt128)9223372036854775807LL - 1)

static const Range ranges[] = {
    {"Int8", -128, 127},
    {"UInt8", 0, 255},
    {"Int32", -(MsInt128)2147483647LL - 1, 2147483647},
    {"Int", INT64_LEAST, 9223372036854775807LL},
    {"UInt64", 0, (MsInt128)18446744073709551615ULL},
};

typedef struct Dump {
    MsArena *arena;
    MsLiteralFacts *facts;
} Dump;

static void put_int128(MsInt128 value) {
    char digits[48];
    size_t n = 0;
    bool negative = value < 0;
    unsigned __int128 magnitude = negative ? 0 - (unsigned __int128)value : (unsigned __int128)value;
    do {
        digits[n++] = (char)('0' + (int)(magnitude % 10));
        magnitude /= 10;
    } while (magnitude != 0);
    if (negative) {
        fputc('-', stdout);
    }
    while (n > 0) {
        fputc(digits[--n], stdout);
    }
}

static void put_message(const char *label, MsStr message) {
    if (message.len != 0) {
        printf("  fault %s: %.*s\n", label, (int)message.len, message.ptr);
    }
}

static void put_folds(const Dump *d, const MsExpr *e) {
    for (size_t i = 0; i < MS_COUNT_OF(ranges); i++) {
        MsInt128 value = 0;
        if (ms_fold(d->facts, e, ranges[i].lo, ranges[i].hi, &value)) {
            put_int128(value);
        } else {
            fputc('-', stdout);
        }
        fputc(' ', stdout);
    }
    switch (ms_literal_tree_kind(d->facts, e)) {
    case MS_LITERAL_NONE:
        puts("-");
        break;
    case MS_LITERAL_INTEGER:
        puts("int");
        break;
    case MS_LITERAL_FRACTIONAL:
        puts("frac");
        break;
    }
}

static void put_node(const Dump *d, const MsExpr *e);

static void put_binary(const Dump *d, const MsExpr *e) {
    for (size_t i = 0; i < MS_COUNT_OF(ranges); i++) {
        put_message(ranges[i].name, ms_constant_arithmetic_fault(d->arena, d->facts, (MsBinaryOp)e->op, e->u.bin.left,
                                                                  e->u.bin.right, ranges[i].name, ranges[i].lo,
                                                                  ranges[i].hi));
    }
    put_node(d, e->u.bin.left);
    put_node(d, e->u.bin.right);
}

static void put_index(const Dump *d, const MsExpr *e) {
    const Range *wide = &ranges[3];
    put_message("index", ms_constant_index_fault(d->arena, d->facts, e->u.bin.left, e->u.bin.right, wide->lo, wide->hi));
    put_node(d, e->u.bin.left);
    put_node(d, e->u.bin.right);
}

static void put_node(const Dump *d, const MsExpr *e) {
    put_folds(d, e);
    switch ((MsExprKind)e->kind) {
    case MS_E_BINARY:
        put_binary(d, e);
        break;
    case MS_E_UNARY:
        put_node(d, e->u.bin.left);
        break;
    case MS_E_INDEX:
        put_index(d, e);
        break;
    case MS_E_LIST:
        for (uint32_t i = 0; i < e->u.list.len; i++) {
            put_node(d, e->u.list.ptr[i]);
        }
        break;
    case MS_E_NUMBER:
    case MS_E_BOOL:
    case MS_E_VOID:
    case MS_E_TEXT:
    case MS_E_NAME:
    case MS_E_MEMBER:
    case MS_E_APPLY:
    case MS_E_PROBE:
    case MS_E_MAP:
    case MS_E_LAMBDA:
    case MS_E_CALL:
    case MS_E_MATCH:
        break;
    }
}

static void answer(const char *line) {
    MsArena arena = {0};
    MsNames names;
    ms_names_init(&names);
    MsStr source = ms_arena_fmt(&arena, "A := %s\n", line);
    MsModule module;
    MsDiag diag;
    if (!ms_parse(&arena, &names, source.ptr, source.len, &module, &diag)) {
        printf("parse-error %.*s\n", (int)diag.message.len, diag.message.ptr);
    } else if (module.ndecls == 0 || module.decls[0]->kind != MS_D_CONST) {
        puts("not-constant");
    } else {
        Dump d = {&arena, ms_literal_facts_new(&arena, &names, module.node_count)};
        put_node(&d, module.decls[0]->u.konst.value);
    }
    puts("---");
    ms_names_free(&names);
    ms_arena_free(&arena);
}

int main(void) {
    MsBuf line = {0};
    while (read_line(&line)) {
        answer(line.data);
    }
    ms_buf_free(&line);
    return 0;
}
