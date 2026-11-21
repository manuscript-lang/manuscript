/* Unit test of the lowering's ownership scopes (src/compiler/src/check/lower_scope.c): the markers a
 * function emits, run through `elaborate` and the verifier, drop an owned value once on the
 * fall-through path and on an early `return`. */
#include <stdio.h>
#include <string.h>

#include "ms/lower_scope.h"
#include "ms/mir_pass.h"
#include "ms/mir_verify.h"

static int failures;

#define CHECK(cond)                                                                                \
    do {                                                                                           \
        if (!(cond)) {                                                                             \
            fprintf(stderr, "%s:%d: check failed: %s\n", __FILE__, __LINE__, #cond);              \
            failures++;                                                                            \
        }                                                                                          \
    } while (0)

static uint32_t count_ops(const MirModule *m, MirOp op) {
    uint32_t n = 0;
    const MirFunc *f = &m->funcs[0];
    for (uint32_t b = 0; b < f->nblocks; b++) {
        for (uint32_t i = 0; i < f->blocks[b].ninsts; i++) {
            n += f->blocks[b].insts[i].op == (uint8_t)op;
        }
    }
    return n;
}

/* fn f(s: str, c: bool) -> int: an owned copy of `s` lives in an inner scope; `c` returns early. */
static void early_return_and_fall_through(void) {
    MirModule m;
    mir_module_init(&m);
    MirBuilder b;
    const MirParam params[] = {{MIR_STR, MM_BORROW}, {MIR_BOOL, MM_BORROW}};
    mir_b_init(&b, &m, ms_intern_cstr(&m.names, "f"), params, 2, MIR_INT);
    MirValue p[2];
    mir_b_params(&b, p, 2);
    LScopes s;
    lscope_init(&s, &b);
    CHECK(lscope_push(&s) == 0);
    CHECK(lscope_push(&s) == 1);
    const MirValue copy = mir_b_emit(&b, MOP_Clone, &p[0], 1, (MirImm){0}, MIR_STR);
    lscope_own(&s, copy, 0);
    const MirBlock early = mir_b_new_block(&b), rest = mir_b_new_block(&b);
    mir_b_br_if(&b, p[1], early, NULL, 0, rest, NULL, 0);
    mir_b_seal_block(&b, early);
    mir_b_seal_block(&b, rest);
    mir_b_switch_to(&b, early);
    lscope_exit_to(&s, 0);
    mir_b_ret(&b, mir_b_iconst(&b, 1));
    mir_b_switch_to(&b, rest);
    lscope_pop(&s, true);
    lscope_pop(&s, true);
    mir_b_ret(&b, mir_b_iconst(&b, 2));
    uint32_t id;
    CHECK(mir_b_finish(&b, &id));

    CHECK(count_ops(&m, MOP_ScopeBegin) == 2);
    CHECK(count_ops(&m, MOP_ScopeOwn) == 1);
    CHECK(count_ops(&m, MOP_ScopeEnd) == 4); /* both scopes at the return, both at the end */
    MsBuf error = {0};
    CHECK(mir_elaborate(&m, &error));
    MirVerifyErrors errors = {0};
    CHECK(mir_verify_module(&m, false, &errors));
    CHECK(count_ops(&m, MOP_ScopeEnd) == 0);
    CHECK(count_ops(&m, MOP_Drop) == 2); /* one per path */
    ms_buf_free(&error);
    mir_module_free(&m);
}

/* A scope that owns nothing emits nothing. */
static void empty_scope(void) {
    MirModule m;
    mir_module_init(&m);
    MirBuilder b;
    mir_b_init(&b, &m, ms_intern_cstr(&m.names, "g"), NULL, 0, MIR_INT);
    LScopes s;
    lscope_init(&s, &b);
    (void)lscope_push(&s);
    lscope_exit_to(&s, 0);
    lscope_pop(&s, true);
    mir_b_ret(&b, mir_b_iconst(&b, 0));
    uint32_t id;
    CHECK(mir_b_finish(&b, &id));
    CHECK(count_ops(&m, MOP_ScopeBegin) + count_ops(&m, MOP_ScopeEnd) == 0);
    mir_module_free(&m);
}

/* A debugger scope nests under the open one and positions set inside it carry it. */
static void debugger_scopes(void) {
    MirModule m;
    mir_module_init(&m);
    MirBuilder b;
    mir_b_init(&b, &m, ms_intern_cstr(&m.names, "h"), NULL, 0, MIR_INT);
    const uint32_t outer = mir_b_open_scope(&b, ms_intern_cstr(&m.names, "d"), 0, 7);
    CHECK(outer == 0 && b.loc.scope == 1);
    const uint32_t inner = mir_b_open_scope(&b, ms_intern_cstr(&m.names, "e"), 0, 8);
    CHECK(inner == 1 && b.loc.scope == 2 && b.f.scopes[1].parent == 1 && b.f.scopes[1].call_line == 8);
    mir_b_close_scope(&b, inner);
    mir_b_close_scope(&b, outer);
    CHECK(b.loc.scope == 0 && b.f.nscopes == 2);
    mir_b_ret(&b, mir_b_iconst(&b, 0));
    uint32_t id;
    CHECK(mir_b_finish(&b, &id));
    mir_module_free(&m);
}

int main(void) {
    debugger_scopes();
    early_return_and_fall_through();
    empty_scope();
    return failures == 0 ? 0 : 1;
}
