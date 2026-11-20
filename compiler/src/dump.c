/* The canonical tree dump of crates/ms-syntax/src/dump.rs, in C. */
#include <string.h>

#include "ms/dump.h"

typedef struct {
    MsBuf *b;
    const MsNames *names;
} D;

static void d_w(D *d, const char *s) { ms_buf_puts(d->b, s); }
static void d_p(D *d, MsPos pos) { ms_dump_pos(d->b, pos); }
static void d_q(D *d, MsStr s) { ms_dump_quote(d->b, s.ptr, s.len); }
static void d_qc(D *d, const char *s) { ms_dump_quote(d->b, s, strlen(s)); }
static void d_qn(D *d, MsSym s) { d_q(d, ms_name(d->names, s)); }

static void d_typ(D *d, const MsTypeRef *t);
static void d_expr(D *d, const MsExpr *e);
static void d_params(D *d, const MsParam *const *ps, uint32_t n);
static void d_body(D *d, MsStmt *const *b, uint32_t n);
static void d_pattern(D *d, const MsPattern *pt);

static void d_types(D *d, MsTypeRef *const *ts, uint32_t n) {
    d_w(d, "[");
    for (uint32_t i = 0; i < n; i++) {
        d_typ(d, ts[i]);
        d_w(d, " ");
    }
    d_w(d, "]");
}

static void d_typ(D *d, const MsTypeRef *t) {
    if (t == NULL) {
        d_w(d, "nil");
        return;
    }
    d_w(d, "(type ");
    d_p(d, t->pos);
    d_w(d, " ");
    if (t->kind == MS_TYPE_NAMED) {
        d_qn(d, t->name);
        d_w(d, " ");
        d_types(d, t->args.ptr, t->args.len);
        d_w(d, " ");
        d_params(d, NULL, 0);
        d_w(d, " nil)");
    } else {
        d_qc(d, "fn");
        d_w(d, " ");
        d_types(d, NULL, 0);
        d_w(d, " ");
        d_params(d, (const MsParam *const *)t->params.ptr, t->params.len);
        d_w(d, " ");
        d_typ(d, t->result);
        d_w(d, ")");
    }
}

static void d_params(D *d, const MsParam *const *ps, uint32_t n) {
    d_w(d, "[");
    for (uint32_t i = 0; i < n; i++) {
        const MsParam *pm = ps[i];
        d_w(d, "(param ");
        d_p(d, pm->pos);
        d_w(d, " ");
        d_qn(d, pm->name);
        d_w(d, " ");
        d_typ(d, pm->ty);
        d_w(d, " ");
        d_expr(d, pm->def);
        d_w(d, ") ");
    }
    d_w(d, "]");
}

typedef struct {
    const char *kind;
    MsStr text;
    const MsExpr *left, *right;
    const MsArg *args;
    uint32_t nargs;
    MsTypeRef *const *types;
    uint32_t ntypes;
    MsExpr *const *elements;
    uint32_t nelements;
    const MsMapEntry *entries;
    uint32_t nentries;
    const MsTextPart *parts;
    uint32_t nparts;
    MsParam *const *params;
    uint32_t nparams;
    const MsTypeRef *result;
    MsStmt *const *body;
    uint32_t nbody;
    MsArm *const *arms;
    uint32_t narms;
} Ef;

static void expr_fields(D *d, const MsExpr *e, const Ef *f) {
    d_w(d, "(expr ");
    d_p(d, e->pos);
    d_w(d, " ");
    d_w(d, f->kind);
    d_w(d, " ");
    d_q(d, f->text);
    d_w(d, " ");
    d_expr(d, f->left);
    d_w(d, " ");
    d_expr(d, f->right);
    d_w(d, " [");
    for (uint32_t i = 0; i < f->nargs; i++) {
        const MsArg *a = &f->args[i];
        d_w(d, "(arg ");
        d_p(d, a->pos);
        d_w(d, " ");
        if (a->has_name) {
            d_qn(d, a->name);
        } else {
            d_qc(d, "");
        }
        d_w(d, " ");
        d_expr(d, a->value);
        d_w(d, ") ");
    }
    d_w(d, "] ");
    d_types(d, f->types, f->ntypes);
    d_w(d, " [");
    for (uint32_t i = 0; i < f->nelements; i++) {
        d_expr(d, f->elements[i]);
        d_w(d, " ");
    }
    for (uint32_t i = 0; i < f->nentries; i++) {
        d_expr(d, f->entries[i].key);
        d_w(d, " ");
        d_expr(d, f->entries[i].value);
        d_w(d, " ");
    }
    d_w(d, "] [");
    for (uint32_t i = 0; i < f->nparts; i++) {
        const MsTextPart *part = &f->parts[i];
        d_w(d, "(part ");
        if (part->expr == NULL) {
            d_q(d, part->lit);
            d_w(d, " nil");
        } else {
            d_qc(d, "");
            d_w(d, " ");
            d_expr(d, part->expr);
        }
        d_w(d, ") ");
    }
    d_w(d, "] ");
    d_params(d, (const MsParam *const *)f->params, f->nparams);
    d_w(d, " ");
    d_typ(d, f->result);
    d_w(d, " ");
    d_body(d, f->body, f->nbody);
    d_w(d, " [");
    for (uint32_t i = 0; i < f->narms; i++) {
        const MsArm *a = f->arms[i];
        d_w(d, "(arm ");
        d_p(d, a->pos);
        d_w(d, " ");
        d_expr(d, a->path);
        d_w(d, " [");
        for (uint32_t k = 0; k < a->bindings.len; k++) {
            d_w(d, "(");
            d_qn(d, a->bindings.ptr[k].name);
            d_w(d, " ");
            d_p(d, a->bindings.ptr[k].pos);
            d_w(d, ") ");
        }
        d_w(d, "] ");
        d_body(d, a->body.ptr, a->body.len);
        d_w(d, " ");
        d_expr(d, a->value);
        d_w(d, ") ");
    }
    d_w(d, "])");
}

static void d_expr(D *d, const MsExpr *e) {
    if (e == NULL) {
        d_w(d, "nil");
        return;
    }
    Ef f;
    memset(&f, 0, sizeof f);
    switch (e->kind) {
    case MS_E_NUMBER: f.kind = "number"; f.text = ms_name(d->names, e->u.sym); break;
    case MS_E_BOOL: f.kind = "bool"; f.text = e->u.flag ? (MsStr){"true", 4} : (MsStr){"false", 5}; break;
    case MS_E_VOID: f.kind = "void"; f.text = (MsStr){"void", 4}; break;
    case MS_E_TEXT:
        f.kind = "text";
        f.parts = e->u.text.ptr;
        f.nparts = e->u.text.len;
        break;
    case MS_E_NAME: f.kind = "name"; f.text = ms_name(d->names, e->u.sym); break;
    case MS_E_MEMBER:
        f.kind = "member";
        f.text = ms_name(d->names, e->u.member.name);
        f.left = e->u.member.left;
        break;
    case MS_E_APPLY:
        f.kind = "apply";
        f.left = e->u.apply.left;
        f.right = e->u.apply.value;
        f.types = e->u.apply.types.ptr;
        f.ntypes = e->u.apply.types.len;
        break;
    case MS_E_INDEX:
        f.kind = "index";
        f.left = e->u.bin.left;
        f.right = e->u.bin.right;
        break;
    case MS_E_PROBE:
        f.kind = "probe";
        f.left = e->u.bin.left;
        break;
    case MS_E_LIST:
        f.kind = "list";
        f.text = (MsStr){"[", 1};
        f.elements = e->u.list.ptr;
        f.nelements = e->u.list.len;
        break;
    case MS_E_MAP:
        f.kind = "map";
        f.text = (MsStr){"{", 1};
        f.entries = e->u.map.ptr;
        f.nentries = e->u.map.len;
        break;
    case MS_E_UNARY: {
        const char *s = ms_unary_str((MsUnaryOp)e->op);
        f.kind = "unary";
        f.text = (MsStr){s, (uint32_t)strlen(s)};
        f.right = e->u.bin.left;
        break;
    }
    case MS_E_BINARY: {
        const char *s = ms_binary_str((MsBinaryOp)e->op);
        f.kind = "binary";
        f.text = (MsStr){s, (uint32_t)strlen(s)};
        f.left = e->u.bin.left;
        f.right = e->u.bin.right;
        break;
    }
    case MS_E_LAMBDA:
        f.kind = "lambda";
        f.params = e->u.lambda.params.ptr;
        f.nparams = e->u.lambda.params.len;
        f.result = e->u.lambda.result;
        f.body = e->u.lambda.body.ptr;
        f.nbody = e->u.lambda.body.len;
        break;
    case MS_E_CALL:
        f.kind = "call";
        f.left = e->u.call.callee;
        f.args = e->u.call.args.ptr;
        f.nargs = e->u.call.args.len;
        break;
    default:
        f.kind = "match";
        f.text = (MsStr){"match", 5};
        f.left = e->u.match.scrutinee;
        f.arms = e->u.match.arms.ptr;
        f.narms = e->u.match.arms.len;
        break;
    }
    expr_fields(d, e, &f);
}

static void d_pattern(D *d, const MsPattern *pt) {
    if (pt == NULL) {
        d_w(d, "nil");
        return;
    }
    d_w(d, "(pattern ");
    d_p(d, pt->pos);
    d_w(d, " ");
    if (pt->kind == MS_P_NAME) {
        d_w(d, "name ");
        d_qn(d, pt->u.name);
        d_w(d, " [] []");
    } else if (pt->kind == MS_P_LIST) {
        d_w(d, "list ");
        d_qc(d, "");
        d_w(d, " [");
        for (uint32_t i = 0; i < pt->u.list.len; i++) {
            d_pattern(d, pt->u.list.ptr[i]);
            d_w(d, " ");
        }
        d_w(d, "] []");
    } else {
        d_w(d, "type ");
        d_qc(d, "");
        d_w(d, " [] [");
        for (uint32_t i = 0; i < pt->u.fields.len; i++) {
            const MsPatternField *f = &pt->u.fields.ptr[i];
            d_w(d, "(pf ");
            d_p(d, f->pos);
            d_w(d, " ");
            d_qn(d, f->name);
            d_w(d, " ");
            d_pattern(d, f->pattern);
            d_w(d, ") ");
        }
        d_w(d, "]");
    }
    d_w(d, ")");
}

static void d_stmt(D *d, const MsStmt *s);

static void d_body(D *d, MsStmt *const *b, uint32_t n) {
    d_w(d, "[");
    for (uint32_t i = 0; i < n; i++) {
        d_stmt(d, b[i]);
        d_w(d, " ");
    }
    d_w(d, "]");
}

typedef struct {
    const char *kind;
    MsStr name;
    const char *compound;
    bool is_mutable;
    bool has_group;
    MsPos group;
    const MsPattern *pattern;
    const MsTypeRef *ty;
    const MsExpr *target, *value;
    MsStmt *const *body;
    uint32_t nbody;
    MsStmt *const *else_body;
    uint32_t nelse;
} Sf;

static void d_stmt(D *d, const MsStmt *s) {
    Sf f;
    memset(&f, 0, sizeof f);
    f.compound = "";
    switch (s->kind) {
    case MS_S_BIND:
        f.kind = "bind";
        f.is_mutable = s->u.bind.is_mutable;
        f.has_group = s->u.bind.has_group;
        f.group = s->u.bind.group;
        f.pattern = s->u.bind.pattern;
        f.ty = s->u.bind.ty;
        f.value = s->u.bind.value;
        break;
    case MS_S_ASSIGN:
        f.kind = "assign";
        if (s->u.assign.has_compound) {
            f.compound = ms_binary_str((MsBinaryOp)s->u.assign.compound);
        }
        if (s->u.assign.member_target) {
            f.target = s->u.assign.target;
        } else {
            f.name = ms_name(d->names, s->u.assign.name);
        }
        f.value = s->u.assign.value;
        break;
    case MS_S_CALL: f.kind = "call"; f.value = s->u.expr; break;
    case MS_S_RETURN: f.kind = "return"; f.value = s->u.expr; break;
    case MS_S_BREAK: f.kind = "break"; break;
    case MS_S_CONTINUE: f.kind = "continue"; break;
    case MS_S_IF:
        f.kind = "if";
        f.is_mutable = s->u.branch.is_mutable;
        f.pattern = s->u.branch.binding;
        f.value = s->u.branch.cond;
        f.body = s->u.branch.body.ptr;
        f.nbody = s->u.branch.body.len;
        f.else_body = s->u.branch.else_body.ptr;
        f.nelse = s->u.branch.else_body.len;
        break;
    case MS_S_WHILE:
        f.kind = "while";
        f.value = s->u.loop.cond;
        f.body = s->u.loop.body.ptr;
        f.nbody = s->u.loop.body.len;
        break;
    default:
        f.kind = "for";
        f.name = ms_name(d->names, s->u.each.name);
        f.value = s->u.each.iter;
        f.body = s->u.each.body.ptr;
        f.nbody = s->u.each.body.len;
        break;
    }
    d_w(d, "(stmt ");
    d_p(d, s->pos);
    d_w(d, " ");
    d_w(d, f.kind);
    d_w(d, " ");
    d_q(d, f.name);
    d_w(d, " ");
    d_qc(d, f.compound);
    d_w(d, f.is_mutable ? " true " : " false ");
    d_p(d, f.has_group ? f.group : (MsPos){0, 0, 0});
    d_w(d, " ");
    d_pattern(d, f.pattern);
    d_w(d, " ");
    d_typ(d, f.ty);
    d_w(d, " ");
    d_expr(d, f.target);
    d_w(d, " ");
    d_expr(d, f.value);
    d_w(d, " ");
    d_body(d, f.body, f.nbody);
    d_w(d, " ");
    d_body(d, f.else_body, f.nelse);
    d_w(d, ")");
}

static void d_type_params(D *d, MsTypeParams tps) {
    d_w(d, "[");
    for (uint32_t i = 0; i < tps.len; i++) {
        const MsTypeParam *tp = tps.ptr[i];
        d_w(d, "(tp ");
        d_p(d, tp->pos);
        d_w(d, " ");
        d_qn(d, tp->name);
        d_w(d, " ");
        d_types(d, tp->bounds.ptr, tp->bounds.len);
        d_w(d, " ");
        d_typ(d, tp->def);
        d_w(d, ") ");
    }
    d_w(d, "]");
}

typedef struct {
    MsPos pos;
    const char *kind;
    MsStr name;
    bool is_exported, constant, synthetic;
    MsTypeParams tparams;
    MsParams fields;
    MsCase *const *cases;
    uint32_t ncases;
    MsMethod *const *methods;
    uint32_t nmethods;
    MsParams params;
    const MsTypeRef *result, *contract, *receiver;
    MsStmt *const *body;
    uint32_t nbody;
} Df;

static void decl_fields(D *d, const Df *f) {
    d_w(d, "(decl ");
    d_p(d, f->pos);
    d_w(d, " ");
    d_w(d, f->kind);
    d_w(d, " ");
    d_q(d, f->name);
    d_w(d, f->is_exported ? " true " : " false ");
    d_w(d, f->constant ? "true " : "false ");
    d_p(d, (MsPos){0, 0, 0});
    d_w(d, f->synthetic ? " true " : " false ");
    d_type_params(d, f->tparams);
    d_w(d, " ");
    d_params(d, (const MsParam *const *)f->fields.ptr, f->fields.len);
    d_w(d, " [");
    for (uint32_t i = 0; i < f->ncases; i++) {
        const MsCase *c = f->cases[i];
        d_w(d, "(case ");
        d_p(d, c->pos);
        d_w(d, " ");
        d_qn(d, c->name);
        d_w(d, " ");
        d_params(d, (const MsParam *const *)c->fields.ptr, c->fields.len);
        d_w(d, ") ");
    }
    d_w(d, "] [");
    for (uint32_t i = 0; i < f->nmethods; i++) {
        const MsMethod *m = f->methods[i];
        Df g;
        memset(&g, 0, sizeof g);
        g.pos = m->pos;
        g.kind = "fn";
        g.name = ms_name(d->names, m->func.name);
        g.tparams = m->func.type_params;
        g.params = m->func.params;
        g.result = m->func.result;
        g.body = m->func.body.ptr;
        g.nbody = m->func.body.len;
        decl_fields(d, &g);
        d_w(d, " ");
    }
    d_w(d, "] ");
    d_params(d, (const MsParam *const *)f->params.ptr, f->params.len);
    d_w(d, " ");
    d_typ(d, f->result);
    d_w(d, " ");
    d_typ(d, f->contract);
    d_w(d, " ");
    d_typ(d, f->receiver);
    d_w(d, " ");
    d_body(d, f->body, f->nbody);
    d_w(d, ")");
}

static void d_decl(D *d, const MsDecl *x, MsNames *scratch_names) {
    Df f;
    memset(&f, 0, sizeof f);
    f.pos = x->pos;
    f.is_exported = x->is_exported;
    f.synthetic = x->synthetic;
    switch (x->kind) {
    case MS_D_FN:
        f.kind = x->u.fn.external ? "extern fn" : "fn";
        f.name = ms_name(d->names, x->u.fn.name);
        f.tparams = x->u.fn.type_params;
        f.params = x->u.fn.params;
        f.result = x->u.fn.result;
        f.body = x->u.fn.body.ptr;
        f.nbody = x->u.fn.body.len;
        decl_fields(d, &f);
        return;
    case MS_D_CONST: {
        MsTypeRef placeholder;
        memset(&placeholder, 0, sizeof placeholder);
        placeholder.pos = x->u.konst.value->pos;
        placeholder.kind = MS_TYPE_NAMED;
        placeholder.name = ms_intern(scratch_names, "", 0);
        MsStmt ret;
        memset(&ret, 0, sizeof ret);
        ret.pos = x->u.konst.init_pos;
        ret.kind = MS_S_RETURN;
        ret.u.expr = x->u.konst.value;
        MsStmt *rp = &ret;
        f.kind = "fn";
        f.name = ms_name(d->names, x->u.konst.name);
        f.constant = true;
        f.result = x->u.konst.ty ? x->u.konst.ty : &placeholder;
        f.body = &rp;
        f.nbody = 1;
        decl_fields(d, &f);
        return;
    }
    case MS_D_TYPE:
        f.kind = "type";
        f.name = ms_name(d->names, x->u.type.name);
        f.tparams = x->u.type.type_params;
        f.fields = x->u.type.fields;
        break;
    case MS_D_ENUM:
        f.kind = "alternative";
        f.name = ms_name(d->names, x->u.enumeration.name);
        f.tparams = x->u.enumeration.type_params;
        f.cases = x->u.enumeration.cases.ptr;
        f.ncases = x->u.enumeration.cases.len;
        break;
    case MS_D_ALIAS:
        f.kind = "alias";
        f.name = ms_name(d->names, x->u.alias.name);
        f.tparams = x->u.alias.type_params;
        break;
    case MS_D_INTERFACE:
        f.kind = "interface";
        f.name = ms_name(d->names, x->u.iface.name);
        f.tparams = x->u.iface.type_params;
        f.methods = x->u.iface.methods.ptr;
        f.nmethods = x->u.iface.methods.len;
        break;
    case MS_D_IMPL:
        f.kind = "impl";
        f.methods = x->u.impl.methods.ptr;
        f.nmethods = x->u.impl.methods.len;
        f.contract = x->u.impl.contract;
        f.receiver = x->u.impl.receiver;
        break;
    default: {
        MsTypeRef unit;
        memset(&unit, 0, sizeof unit);
        unit.pos = x->pos;
        unit.kind = MS_TYPE_NAMED;
        unit.name = ms_intern(scratch_names, "Void", 4);
        f.kind = x->u.test.bench ? "bench" : "test";
        f.name = x->u.test.name;
        f.result = &unit;
        f.body = x->u.test.body.ptr;
        f.nbody = x->u.test.body.len;
        decl_fields(d, &f);
        return;
    }
    }
    decl_fields(d, &f);
}

void ms_dump_module(MsBuf *out, const MsNames *names, const MsModule *m) {
    D d = {out, names};
    /* The placeholder type names ("" and "Void") are interned into a throwaway copy would change
     * ids; the real table is only read here, so intern into it through a cast: the names exist
     * after this call as ordinary table entries. */
    MsNames *table = (MsNames *)names;
    for (uint32_t i = 0; i < m->nimports; i++) {
        const MsImport *im = &m->imports[i];
        d_w(&d, "import ");
        d_p(&d, im->pos);
        d_w(&d, " ");
        d_p(&d, im->name_pos);
        d_w(&d, " ");
        d_qn(&d, im->name);
        d_w(&d, " ");
        d_q(&d, im->path);
        d_w(&d, "\n");
    }
    for (uint32_t i = 0; i < m->ndecls; i++) {
        d_decl(&d, m->decls[i], table);
        d_w(&d, "\n");
    }
    d_w(&d, "omitted [");
    for (uint32_t i = 0; i < m->nomitted; i++) {
        d_q(&d, m->omitted[i]);
        d_w(&d, " ");
    }
    d_w(&d, "]\nrecovered [");
    for (uint32_t i = 0; i < m->nrecovered; i++) {
        ms_buf_printf(out, "%u-%u ", m->recovered[i].start, m->recovered[i].end);
    }
    d_w(&d, "]\n");
}
