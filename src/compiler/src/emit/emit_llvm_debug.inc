/* Source places for the fault tables (included from emit_llvm.c). Every instruction gets
 * `!dbg !DILocation(line: <line>, column: <scope>)` in a line-tables-only compile unit, so the assembly
 * clang writes has a `.loc file line scope` (`.cv_loc` on Windows) before each instruction, which
 * ms_asm_tables turns into the tables (ms/mir_asm_tables.h). The column carries the module-wide scope
 * of the inlined callee, 0 for the function itself. The nodes are collected in `LlDebug.nodes` and
 * written after the last function. */

typedef struct LlDebug {
    MsBuf nodes;     /* the numbered metadata lines of the subprograms and locations */
    uint32_t next;   /* the next free metadata number */
    uint32_t sp;     /* the subprogram of the function being written */
    uint32_t cached; /* the DILocation node of `cached_line`/`cached_column`, 0 when none */
    uint32_t cached_line, cached_column;
} LlDebug;

enum { LL_MD_CU = 0, LL_MD_FILE = 1, LL_MD_FLAGS = 2, LL_MD_NO_TYPES = 3, LL_MD_TYPE = 4, LL_MD_FIRST = 5 };

static void ll_debug_init(LlDebug *d) {
    d->next = LL_MD_FIRST;
}

/* Starts function `f`'s subprogram and returns its number. */
static uint32_t ll_debug_subprogram(LlDebug *d, MsStr name, uint32_t line) {
    d->sp = d->next++;
    d->cached = 0;
    ms_buf_printf(&d->nodes,
                  "!%u = distinct !DISubprogram(name: \"%.*s\", scope: !%u, file: !%u, line: %u, type: !%u, "
                  "scopeLine: %u, spFlags: DISPFlagDefinition, unit: !%u)\n",
                  d->sp, (int)name.len, name.ptr, LL_MD_FILE, LL_MD_FILE, line, LL_MD_TYPE, line, LL_MD_CU);
    return d->sp;
}

static uint32_t ll_debug_location(LlDebug *d, uint32_t line, uint32_t column) {
    if (d->cached != 0 && d->cached_line == line && d->cached_column == column) {
        return d->cached;
    }
    d->cached = d->next++;
    d->cached_line = line;
    d->cached_column = column;
    ms_buf_printf(&d->nodes, "!%u = !DILocation(line: %u, column: %u, scope: !%u)\n", d->cached, line, column, d->sp);
    return d->cached;
}

/* The text of the module's debug metadata, after its functions. */
static void ll_debug_finish(const LlDebug *d, MsStr file, MsBuf *out) {
    ms_buf_printf(out,
                  "\n!llvm.dbg.cu = !{!%u}\n!llvm.module.flags = !{!%u}\n"
                  "!%u = distinct !DICompileUnit(language: DW_LANG_C99, file: !%u, producer: \"ms\", "
                  "isOptimized: true, runtimeVersion: 0, emissionKind: LineTablesOnly)\n"
                  "!%u = !DIFile(filename: \"%.*s\", directory: \"\")\n"
                  "!%u = !{i32 2, !\"Debug Info Version\", i32 3}\n"
                  "!%u = !{}\n"
                  "!%u = !DISubroutineType(types: !%u)\n",
                  LL_MD_CU, LL_MD_FLAGS, LL_MD_CU, LL_MD_FILE, LL_MD_FILE, (int)file.len, file.ptr, LL_MD_FLAGS,
                  LL_MD_NO_TYPES, LL_MD_TYPE,
                  LL_MD_NO_TYPES);
    ms_buf_put(out, d->nodes.data, d->nodes.len);
}

/* Adds `, !dbg !<node>` to every instruction written since `from`: the lines indented by two spaces. A `switch`
 * spans several lines (`... [`, its cases indented further, `]`), and the closing bracket line takes the metadata. */
static void ll_debug_tag(MsBuf *out, size_t from, uint32_t node) {
    MsBuf tail = {0};
    ms_buf_put(&tail, out->data + from, out->len - from);
    out->len = from;
    const char *p = tail.data, *end = tail.data + tail.len;
    while (p < end) {
        const char *eol = memchr(p, '\n', (size_t)(end - p));
        eol = eol != NULL ? eol : end;
        ms_buf_put(out, p, (size_t)(eol - p));
        const bool instruction = eol - p > 2 && p[0] == ' ' && p[1] == ' ' && p[2] != ' ' && eol[-1] != '[';
        if (instruction) {
            ms_buf_printf(out, ", !dbg !%u", node);
        }
        if (eol < end) {
            ms_buf_putc(out, '\n');
        }
        p = eol + 1;
    }
    ms_buf_free(&tail);
}
