/* Syntax helpers the formatter's passes share (format_internal.h). */
#include "ms/format.h"

#include "format_internal.h"

MsStmts fmt_written_body(const MsExpr *lambda) {
    MsStmts body = lambda->u.lambda.body;
    uint32_t heads = 0;
    while (heads < body.len && fmt_is_destructure_head(body.ptr[heads])) {
        heads++;
    }
    body.ptr += heads;
    body.len -= heads;
    return body;
}

bool fmt_block_lambda(const MsExpr *e) {
    return e->kind == MS_E_LAMBDA && fmt_written_body(e).len > 1;
}

const MsExpr *fmt_statement_value(const MsStmt *s) {
    switch ((MsStmtKind)s->kind) {
    case MS_S_BIND: return s->u.bind.value;
    case MS_S_ASSIGN: return s->u.assign.value;
    case MS_S_CALL:
    case MS_S_RETURN: return s->u.expr;
    case MS_S_IF: return s->u.branch.cond;
    case MS_S_WHILE: return s->u.loop.cond;
    case MS_S_FOR: return s->u.each.iter;
    case MS_S_BREAK:
    case MS_S_CONTINUE: return NULL;
    }
    return NULL;
}

bool fmt_is_written_match(const MsExpr *e) {
    return e->kind == MS_E_MATCH && !(e->u.match.arms.len > 0 && e->u.match.arms.ptr[0]->from_if);
}

bool fmt_suite_expression(const MsExpr *e) {
    while (e->kind == MS_E_UNARY) {
        e = e->u.bin.left;
    }
    return e->kind == MS_E_LAMBDA || e->kind == MS_E_MATCH;
}

bool fmt_is_destructure_head(const MsStmt *s) {
    if (s->kind != MS_S_BIND || s->u.bind.has_group) {
        return false;
    }
    const MsPos a = s->u.bind.pattern->pos;
    const MsPos b = s->u.bind.value->pos;
    return a.offset == s->pos.offset && a.line == s->pos.line && a.column == s->pos.column &&
           b.offset == s->pos.offset && b.line == s->pos.line && b.column == s->pos.column;
}

Str fmt_apply_edits(Fmt *f, Str source, const FmtEdit *edits, size_t count) {
    MsBuf out = {0};
    size_t cursor = 0;
    for (size_t i = 0; i < count; i++) {
        fmt_put(&out, fmt_slice(source, cursor, edits[i].from));
        fmt_put(&out, edits[i].text);
        cursor = edits[i].to;
    }
    fmt_put(&out, fmt_slice(source, cursor, source.len));
    return fmt_take(f, &out);
}
