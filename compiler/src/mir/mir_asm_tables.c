/* Fault tables from assembly text: see ms/mir_asm_tables.h. */
#include <stdlib.h>
#include <string.h>

#include "ms/mir_asm_tables.h"
#include "ms/mir_tables.h"

typedef struct AtFunc {
    MsStr sym, name;
    uint32_t file, line;
    uint32_t index; /* in the meta; the end label `.Lmse<index>` */
    uint32_t first_scope, nscopes; /* its inlined scopes: global numbers first_scope + 1 ... */
    bool seen;
} AtFunc;

typedef struct AtLoc { uint32_t func, line, scope; } AtLoc;

/* One value the assembler fills into the blob. */
typedef enum { AT_FUNC_ADDR, AT_LOC_ADDR, AT_FUNC_SIZE, AT_BLOB_ADDR } AtKind;
typedef struct AtPatch { size_t at; AtKind kind; size_t value; } AtPatch;

static int at_patch_cmp(const void *a, const void *b) {
    const size_t x = ((const AtPatch *)a)->at, y = ((const AtPatch *)b)->at;
    return x < y ? -1 : x > y;
}

/* A function symbol and its number, sorted by symbol for the lookup of labels. */
typedef struct AtKey { MsStr sym; uint32_t index; } AtKey;

static int at_sym_cmp(const void *a, const void *b) {
    const MsStr x = ((const AtKey *)a)->sym, y = ((const AtKey *)b)->sym;
    const size_t n = x.len < y.len ? x.len : y.len;
    const int c = memcmp(x.ptr, y.ptr, n);
    return c != 0 ? c : (x.len > y.len) - (x.len < y.len);
}

static uint32_t at_uint(const char **p) {
    char *end;
    const unsigned long v = strtoul(*p, &end, 10);
    *p = end;
    return (uint32_t)v;
}

static uint32_t at_file(const char **p) {
    char *end;
    const long v = strtol(*p, &end, 10);
    *p = end;
    return v < 0 ? MIR_NONE : (uint32_t)v;
}

typedef struct AtMeta {
    MirModule m;
    AtFunc *funcs;
    uint32_t nfuncs, cfuncs;
    MirScope *scopes;
    uint32_t nscopes, cscopes;
    bool bodies; /* a column past the scopes names a function body (LLVM may inline functions into each other) */
} AtMeta;

static void at_meta_parse(AtMeta *a, const char *text, size_t len) {
    const char *end = text + len;
    while (text < end) {
        const char *eol = memchr(text, '\n', (size_t)(end - text));
        if (eol == NULL) eol = end;
        const char *p = text + 2;
        if (text[0] == 'F') {
            const MsStr f = {p, (uint32_t)(eol - p)};
            MIR_PUSH(&a->m, a->m.files, a->m.nfiles, a->m.cfiles, MsStr, f);
        } else if (text[0] == 'Y') {
            const char *tab = memchr(p, '\t', (size_t)(eol - p));
            AtFunc f = {.sym = {p, (uint32_t)(tab - p)}, .first_scope = a->nscopes};
            p = tab + 1;
            f.file = at_file(&p);
            p++;
            f.line = at_uint(&p);
            p++;
            f.name = (MsStr){p, (uint32_t)(eol - p)};
            MIR_PUSH(&a->m, a->funcs, a->nfuncs, a->cfuncs, AtFunc, f);
        } else if (text[0] == 'B') {
            a->bodies = true;
        } else if (text[0] == 'S') {
            MirScope s = {0};
            s.file = at_file(&p);
            p++;
            s.parent = at_uint(&p);
            p++;
            s.call_line = at_uint(&p);
            p++;
            s.name = mir_name(&a->m, p, (size_t)(eol - p));
            MIR_PUSH(&a->m, a->scopes, a->nscopes, a->cscopes, MirScope, s);
            a->funcs[a->nfuncs - 1].nscopes++;
        }
        text = eol + 1;
    }
}

/* A symbol label at the start of a line, `name:` possibly followed by a comment (LLVM writes `f: # @f`);
 * returns its length, 0 when the line is not one. Local labels (`.L...`) and directives start with a dot. */
static size_t at_label_len(const char *line, size_t n) {
    if (n < 2 || line[0] == '.' || line[0] == '\t' || line[0] == ' ' || line[0] == '#') {
        return 0;
    }
    size_t k = 0;
    while (k < n && line[k] != ':' && line[k] != ' ' && line[k] != '\t') {
        k++;
    }
    return k < n && k > 0 && line[k] == ':' ? k : 0;
}

static bool at_ends_function(const char *line, size_t n) {
    static const char *const stops[] = {".size", ".type", ".text", ".data", ".section", ".globl", ".bss", ".cfi_endproc", ".def", ".seh_endproc"};
    while (n > 0 && (line[0] == '\t' || line[0] == ' ')) { /* LLVM indents directives */
        line++;
        n--;
    }
    if (n == 0 || line[0] != '.') {
        return false;
    }
    for (size_t i = 0; i < sizeof stops / sizeof *stops; i++) {
        const size_t k = strlen(stops[i]);
        if (n >= k && memcmp(line, stops[i], k) == 0) {
            return true;
        }
    }
    return false;
}

/* The line and scope of a `.loc file line col` (ELF, Mach-O; LLVM tabs) or `.cv_loc function file
 * line col` (COFF, LLVM) directive at the start of `text`. The scope is the column, 0 when there is none. */
static bool at_loc_args(const char *text, size_t n, AtLoc *out) {
    static const char loc[] = "\t.loc", cv[] = "\t.cv_loc";
    const bool is_cv = n > sizeof cv && memcmp(text, cv, sizeof cv - 1) == 0;
    const size_t name = is_cv ? sizeof cv - 1 : sizeof loc - 1;
    if (!is_cv && !(n > name && memcmp(text, loc, name) == 0)) {
        return false;
    }
    if (text[name] != ' ' && text[name] != '\t') {
        return false;
    }
    char *line_copy = malloc(n + 1); /* strtoul needs a NUL; owned, freed below */
    memcpy(line_copy, text + name, n - name);
    line_copy[n - name] = '\0';
    const char *q = line_copy;
    (void)at_uint(&q);
    if (is_cv) {
        (void)at_uint(&q); /* the file follows the function id */
    }
    out->line = at_uint(&q);
    out->scope = *q == ' ' || *q == '\t' ? at_uint(&q) : 0;
    free(line_copy);
    return true;
}

/* The number of the function whose symbol is `sym`, or UINT32_MAX. */
static uint32_t at_find(const AtKey *sorted, uint32_t n, MsStr sym) {
    const AtKey key = {sym, 0};
    const AtKey *hit = bsearch(&key, sorted, n, sizeof key, at_sym_cmp);
    return hit != NULL ? hit->index : UINT32_MAX;
}

static void at_put_blob(MsBuf *out, const uint8_t *blob, size_t size, AtPatch *patches, size_t npatches,
                        const AtFunc *funcs, const char *prefix) {
    qsort(patches, npatches, sizeof *patches, at_patch_cmp);
    ms_buf_printf(out, "\n.data\n.balign 8\n.globl %sms_tables\n%sms_tables:\n", prefix, prefix);
    size_t at = 0, next = 0;
    while (at < size) {
        if (next < npatches && patches[next].at == at) {
            const AtPatch *pt = &patches[next++];
            const AtFunc *f = pt->kind == AT_FUNC_ADDR || pt->kind == AT_FUNC_SIZE ? &funcs[pt->value] : NULL;
            switch (pt->kind) {
            case AT_FUNC_ADDR: ms_buf_printf(out, "\t.quad %s%.*s\n", prefix, (int)f->sym.len, f->sym.ptr); at += 8; break;
            case AT_LOC_ADDR: ms_buf_printf(out, "\t.quad .Lmsl%zu\n", pt->value); at += 8; break;
            case AT_FUNC_SIZE:
                ms_buf_printf(out, "\t.long .Lmse%u-%s%.*s\n", f->index, prefix, (int)f->sym.len, f->sym.ptr);
                at += 4;
                break;
            case AT_BLOB_ADDR: ms_buf_printf(out, "\t.quad %sms_tables+%zu\n", prefix, pt->value); at += 8; break;
            }
            continue;
        }
        const size_t stop = next < npatches ? patches[next].at : size;
        ms_buf_puts(out, "\t.byte ");
        const size_t from = at;
        for (; at < stop && at < from + 16; at++) {
            ms_buf_printf(out, "%s%u", at == from ? "" : ",", blob[at]);
        }
        ms_buf_putc(out, '\n');
    }
}


/* ---- functions LLVM inlined into each other ----
 * The `.loc` of an instruction names its own function body or inlined scope, not where LLVM put it. A range
 * whose scope belongs to another function than the one holding the code gets a scope of its own: a frame for
 * that callee whose parent is the function (the frame of a wrapper without a position is then left out). */

/* A clone is told by the function it lands in, the original scope (0x80000000 | q for the body of q) and the line
 * of the call it replaces. */
typedef struct AtCall { uint32_t line, scope; } AtCall; /* the call an inlined body replaces: its line and the scope it was in */
typedef struct AtClone { uint32_t func, scope; AtCall call; uint32_t id; } AtClone;

typedef struct AtRemap {
    AtMeta *a;
    uint32_t *owner; /* per original scope: the function whose body it was in */
    uint32_t norig;
    MsBuf memo; /* AtClone */
} AtRemap;

static uint32_t at_memo(AtRemap *r, AtClone key) {
    const AtClone *all = ms_buf_items(&r->memo);
    for (size_t i = 0; i < r->memo.len / sizeof *all; i++) {
        if (all[i].func == key.func && all[i].scope == key.scope && all[i].call.line == key.call.line && all[i].call.scope == key.call.scope) {
            return all[i].id;
        }
    }
    return 0;
}

static uint32_t at_new_scope(AtRemap *r, AtClone key, MirScope s) {
    MIR_PUSH(&r->a->m, r->a->scopes, r->a->nscopes, r->a->cscopes, MirScope, s);
    key.id = r->a->nscopes;
    ms_buf_put(&r->memo, &key, sizeof key);
    return key.id;
}

/* The scope of function `q`'s own body inlined into function `p` at `call`. */
static uint32_t at_inlined_body(AtRemap *r, uint32_t q, uint32_t p, AtCall call) {
    const AtClone key = {p, 0x80000000u | q, call, 0};
    const uint32_t known = at_memo(r, key);
    if (known != 0) {
        return known;
    }
    const AtFunc *f = &r->a->funcs[q];
    return at_new_scope(r, key, (MirScope){mir_name(&r->a->m, f->name.ptr, f->name.len), f->file, call.scope, call.line});
}

/* A copy of scope `c` (a global number) for code in function `p`, its chain ending at the inlined body. */
static uint32_t at_clone(AtRemap *r, uint32_t c, uint32_t p, AtCall call) {
    const AtClone key = {p, c, call, 0};
    const uint32_t known = at_memo(r, key);
    if (known != 0) {
        return known;
    }
    MirScope s = r->a->scopes[c - 1];
    const uint32_t q = r->owner[c - 1];
    if (s.parent == 0) {
        s.parent = at_inlined_body(r, q, p, call);
    } else if (r->owner[s.parent - 1] != p) {
        s.parent = at_clone(r, s.parent, p, call);
    }
    return at_new_scope(r, key, s);
}

static void at_remap_scopes(AtMeta *a, AtLoc *all, size_t nlocs) {
    AtRemap r = {.a = a, .norig = a->nscopes};
    r.owner = MS_NEW_N(&a->m.arena, uint32_t, a->nscopes ? a->nscopes : 1);
    for (uint32_t f = 0; f < a->nfuncs; f++) {
        for (uint32_t k = 0; k < a->funcs[f].nscopes; k++) {
            r.owner[a->funcs[f].first_scope + k] = f;
        }
    }
    /* LLVM's locations carry no call site: the caller's line and scope are those of its own code just before the range. */
    AtCall *own = MS_NEW_N(&a->m.arena, AtCall, a->nfuncs ? a->nfuncs : 1);
    memset(own, 0, sizeof *own * (a->nfuncs ? a->nfuncs : 1));
    for (size_t i = 0; i < nlocs; i++) {
        const uint32_t p = all[i].func, c = all[i].scope;
        if (c > r.norig) {
            const uint32_t q = c - r.norig - 1;
            all[i].scope = q >= a->nfuncs || q == p ? 0 : at_inlined_body(&r, q, p, own[p]);
        } else if (c > 0 && r.owner[c - 1] != p) {
            all[i].scope = at_clone(&r, c, p, own[p]);
        }
        if (all[i].scope == 0 || all[i].scope <= r.norig) {
            own[p] = (AtCall){all[i].line, all[i].scope};
        }
    }
    ms_buf_free(&r.memo);
}

/* The tables as data after the assembly: the blob of `mir_fault_tables`, its code addresses the labels. */
static void at_emit_tables(AtMeta *a, AtLoc *all, size_t nlocs, const char *prefix, MsBuf *out) {
    if (a->bodies) {
        at_remap_scopes(a, all, nlocs);
    }
    /* A function the compiler removed (an internal one LLVM inlined everywhere) has no code and no entry. */
    AtFunc *kept = MS_NEW_N(&a->m.arena, AtFunc, a->nfuncs ? a->nfuncs : 1);
    uint32_t nkept = 0;
    for (uint32_t f = 0; f < a->nfuncs; f++) {
        if (a->funcs[f].seen) {
            kept[nkept] = a->funcs[f];
            kept[nkept++].index = f;
        }
    }
    MirFuncTable *tables = MS_NEW_N(&a->m.arena, MirFuncTable, nkept ? nkept : 1);
    MirCodeRange *ranges = MS_NEW_N(&a->m.arena, MirCodeRange, nlocs ? nlocs : 1);
    size_t at = 0;
    for (uint32_t f = 0, n = 0; f < a->nfuncs; f++) {
        if (!a->funcs[f].seen) {
            continue;
        }
        const size_t first = at;
        for (size_t k = 0; k < nlocs; k++) {
            if (all[k].func == f) {
                ranges[at++] = (MirCodeRange){(uint32_t)k + 1, MIR_NONE, all[k].line, all[k].scope};
            }
        }
        tables[n++] = (MirFuncTable){a->funcs[f].name, a->funcs[f].file, a->funcs[f].line, 0, ranges + first,
                                     (uint32_t)(at - first)};
    }
    MirTables t;
    mir_fault_tables(&a->m.arena, &a->m, tables, nkept, a->scopes, a->nscopes, &t);
    AtPatch *patches = MS_NEW_N(&a->m.arena, AtPatch, t.npcs * 2 + 5 + 1);
    size_t np = 0;
    for (size_t i = 0; i < t.npcs; i++) {
        const MirTablePc *pc = &t.pcs[i];
        if (pc->off == 0) {
            patches[np++] = (AtPatch){pc->at, AT_FUNC_ADDR, pc->func};
            patches[np++] = (AtPatch){pc->at + 8, AT_FUNC_SIZE, pc->func};
        } else {
            patches[np++] = (AtPatch){pc->at, AT_LOC_ADDR, pc->off - 1};
        }
    }
    for (int i = 0; i < 5; i++) {
        patches[np++] = (AtPatch){t.pointers[i].at, AT_BLOB_ADDR, t.pointers[i].to};
    }
    at_put_blob(out, t.blob, t.size, patches, np, kept, prefix);
}

/* Copies the assembly to `out` with a label after every `.loc` and at the end of every function, and
 * collects the places in `locs`. */
static void at_scan(AtMeta *a, const AtKey *sorted, const char *asm_text, size_t asm_len, const char *prefix,
                    bool strip_lines, MsBuf *out, MsBuf *locs) {
    const size_t plen = strlen(prefix);
    int cur = -1;
    AtLoc l;
    const char *p = asm_text, *end = asm_text + asm_len;
    while (p < end) {
        const char *eol = memchr(p, '\n', (size_t)(end - p));
        if (eol == NULL) eol = end;
        const size_t n = (size_t)(eol - p);
        if (cur >= 0 && at_ends_function(p, n)) {
            ms_buf_printf(out, ".Lmse%d:\n", cur);
            cur = -1;
        }
        const bool is_loc = cur >= 0 && at_loc_args(p, n, &l);
        if (!(is_loc && strip_lines)) {
            ms_buf_put(out, p, n);
            ms_buf_putc(out, '\n');
        }
        const size_t label = at_label_len(p, n);
        if (label > plen && memcmp(p, prefix, plen) == 0) {
            const uint32_t f = at_find(sorted, a->nfuncs, (MsStr){p + plen, (uint32_t)(label - plen)});
            if (f != UINT32_MAX && !a->funcs[f].seen) {
                a->funcs[f].seen = true;
                cur = (int)f;
            }
        } else if (is_loc && l.line != 0) { /* line 0 is code LLVM made up: the range before it goes on */
            l.func = (uint32_t)cur;
            ms_buf_printf(out, ".Lmsl%zu:\n", locs->len / sizeof l);
            ms_buf_put(locs, &l, sizeof l);
        }
        p = eol + 1;
    }
    if (cur >= 0) {
        ms_buf_printf(out, ".Lmse%d:\n", cur);
    }
}

bool mir_asm_tables(const char *meta, size_t meta_len, const char *asm_text, size_t asm_len,
                    const char *prefix, bool strip_lines, MsBuf *out, MsBuf *why) {
    AtMeta a = {0};
    mir_module_init(&a.m);
    at_meta_parse(&a, meta, meta_len);
    AtKey *sorted = malloc((a.nfuncs ? a.nfuncs : 1) * sizeof *sorted);
    for (uint32_t i = 0; i < a.nfuncs; i++) {
        sorted[i] = (AtKey){a.funcs[i].sym, i};
    }
    qsort(sorted, a.nfuncs, sizeof *sorted, at_sym_cmp);
    MsBuf locs = {0};
    at_scan(&a, sorted, asm_text, asm_len, prefix, strip_lines, out, &locs);
    at_emit_tables(&a, ms_buf_items(&locs), locs.len / sizeof(AtLoc), prefix, out);
    free(sorted);
    ms_buf_free(&locs);
    mir_module_free(&a.m);
    (void)why;
    return true;
}

void mir_tables_meta(const MirModule *m, const MsSym *display, uint32_t ndisplay, MsBuf *out) {
    for (uint32_t i = 0; i < m->nfiles; i++) {
        ms_buf_printf(out, "F %.*s\n", (int)m->files[i].len, m->files[i].ptr);
    }
    ms_buf_puts(out, "B\n"); /* LLVM inlines: scope numbers past the module's name function bodies */
    uint32_t base = 0;
    for (uint32_t i = 0; i < m->nfuncs; i++) {
        const MirFunc *f = &m->funcs[i];
        const MsStr name = ms_name(&m->names, f->name); /* source names are identifiers and dots */
        const MsStr shown = i < ndisplay ? ms_name(&m->names, display[i]) : name; /* glue added by the emitter */
        ms_buf_printf(out, "Y %.*s\t%d\t%u\t%.*s\n", (int)name.len, name.ptr,
                      f->loc.file == MIR_NONE ? -1 : (int)f->loc.file, f->loc.line, (int)shown.len, shown.ptr);
        for (uint32_t k = 0; k < f->nscopes; k++) {
            const MirScope *s = &f->scopes[k];
            const MsStr sn = ms_name(&m->names, s->name);
            ms_buf_printf(out, "S %d\t%u\t%u\t%.*s\n", s->file == MIR_NONE ? -1 : (int)s->file,
                          s->parent == 0 ? 0 : base + s->parent, s->call_line, (int)sn.len, sn.ptr);
        }
        base += f->nscopes;
    }
}
