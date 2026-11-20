/* Ownership scopes for the lowering: see ms/lower_scope.h. */
#include "ms/lower_scope.h"

void lscope_init(LScopes *s, MirBuilder *b) {
    *s = (LScopes){.b = b};
}

uint32_t lscope_push(LScopes *s) {
    const uint32_t parent = s->depth > 0 ? s->stack[s->depth - 1].id + 1 : 0;
    const LScope scope = {.id = s->next_id++, .parent = parent, .begun = false};
    MIR_PUSH(s->b->m, s->stack, s->depth, s->cap, LScope, scope);
    return s->depth - 1;
}

static MirImm lscope_imm(uint32_t id, uint32_t other) {
    return (MirImm){.tag = MI_SCOPE, .a = id, .b = other};
}

void lscope_own_in(LScopes *s, uint32_t depth, MirValue v, uint32_t kind) {
    for (uint32_t i = 0; i < s->depth; i++) {
        LScope *scope = &s->stack[i];
        if (!scope->begun) {
            scope->begun = true;
            (void)mir_b_emit(s->b, MOP_ScopeBegin, NULL, 0, lscope_imm(scope->id, scope->parent),
                             MIR_NONE);
        }
    }
    (void)mir_b_emit(s->b, MOP_ScopeOwn, &v, 1, lscope_imm(s->stack[depth].id, kind), MIR_NONE);
}

void lscope_own(LScopes *s, MirValue v, uint32_t kind) {
    lscope_own_in(s, s->depth - 1, v, kind);
}

void lscope_disown(LScopes *s, MirValue v) {
    (void)mir_b_emit(s->b, MOP_ScopeDisown, &v, 1, (MirImm){0}, MIR_NONE);
}

void lscope_exit_to(LScopes *s, uint32_t depth) {
    for (uint32_t i = s->depth; i > depth; i--) {
        const LScope *scope = &s->stack[i - 1];
        if (scope->begun) {
            (void)mir_b_emit(s->b, MOP_ScopeEnd, NULL, 0, lscope_imm(scope->id, 0), MIR_NONE);
        }
    }
}

void lscope_pop(LScopes *s, bool reached) {
    if (reached) {
        lscope_exit_to(s, s->depth - 1);
    }
    s->depth--;
}
