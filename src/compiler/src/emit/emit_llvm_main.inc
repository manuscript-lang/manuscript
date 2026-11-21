/* The program's `main` and its fault tables as one more LLVM module for emit_llvm.c (included from
 * it). The tables describe code that exists only once the other units are compiled, so the caller
 * measures each function in the objects, builds the blob with `mir_fault_tables`, and asks for this
 * unit. Every code address in the blob is a word that names a function's symbol, so the functions
 * must be external (`mir_emit_llvm_with` with `export_all`). */

/* Appends `bytes[from, to)` as one array field of the table's struct: its type and its constant. */
static void ll_blob_run(MsBuf *types, MsBuf *values, const uint8_t *bytes, size_t from, size_t to) {
    ms_buf_printf(types, "%s[%zu x i8]", types->len > 0 ? ", " : "", to - from);
    ms_buf_printf(values, "%s[%zu x i8] c\"", values->len > 0 ? ", " : "", to - from);
    for (size_t k = from; k < to; k++) {
        ms_buf_printf(values, "\\%02X", bytes[k]);
    }
    ms_buf_putc(values, '"');
}

/* Appends the word at `at`: the address of the blob's own byte `to`, or of function `func` plus `off`. */
static void ll_blob_word(MsBuf *types, MsBuf *values, const MirModule *m, const MirTablePointer *own,
                         const MirTablePc *pc) {
    ms_buf_printf(types, "%si64", types->len > 0 ? ", " : "");
    ms_buf_printf(values, "%si64 ptrtoint (ptr getelementptr (i8, ptr ", values->len > 0 ? ", " : "");
    if (own != NULL) {
        ms_buf_printf(values, "@\"ms.tables\", i64 %zu) to i64)", own->to);
        return;
    }
    ll_sym(values, ms_name(&m->names, m->funcs[pc->func].name));
    ms_buf_printf(values, ", i64 %u) to i64)", pc->off);
}

/* One word of the blob: its offset and where its value comes from. */
typedef struct LlWord {
    size_t at;
    const MirTablePointer *own;
    const MirTablePc *pc;
} LlWord;

static int ll_word_order(const void *a, const void *b) {
    const size_t x = ((const LlWord *)a)->at, y = ((const LlWord *)b)->at;
    return x < y ? -1 : x > y;
}

bool mir_emit_llvm_main(const MirModule *m, const MirTables *tables, MsBuf *out) {
    if (m->entry == MIR_NONE) {
        return false;
    }
    const size_t nwords = 5 + tables->npcs;
    LlWord *words = calloc(nwords, sizeof *words); /* owned, freed below */
    if (words == NULL) {
        return false;
    }
    for (size_t k = 0; k < 5; k++) {
        words[k] = (LlWord){tables->pointers[k].at, &tables->pointers[k], NULL};
    }
    for (size_t k = 0; k < tables->npcs; k++) {
        words[5 + k] = (LlWord){tables->pcs[k].at, NULL, &tables->pcs[k]};
    }
    qsort(words, nwords, sizeof *words, ll_word_order);
    MsBuf types = {0}, values = {0};
    size_t at = 0;
    for (size_t k = 0; k < nwords; k++) {
        if (words[k].at > at) {
            ll_blob_run(&types, &values, tables->blob, at, words[k].at);
        }
        ll_blob_word(&types, &values, m, words[k].own, words[k].pc);
        at = words[k].at + 8;
    }
    if (at < tables->size) {
        ll_blob_run(&types, &values, tables->blob, at, tables->size);
    }
    const MsStr entry = ms_name(&m->names, m->funcs[m->entry].name);
    bool *declared = calloc(m->nfuncs ? m->nfuncs : 1, sizeof *declared); /* owned, freed below */
    if (declared == NULL) {
        free(words);
        ms_buf_free(&types);
        ms_buf_free(&values);
        return false;
    }
    declared[m->entry] = true;
    ms_buf_puts(out, "declare void ");
    ll_sym(out, entry);
    ms_buf_puts(out, "()\n");
    for (size_t k = 0; k < tables->npcs; k++) {
        const uint32_t func = (uint32_t)tables->pcs[k].func;
        if (declared[func]) {
            continue;
        }
        declared[func] = true;
        ms_buf_puts(out, "declare void ");
        ll_sym(out, ms_name(&m->names, m->funcs[func].name));
        ms_buf_puts(out, "()\n");
    }
    free(declared);
    ms_buf_printf(out, "declare i64 @msrt_start(i64, i64, i64, i64)\n@\"ms.tables\" = internal constant <{ %.*s }> <{ %.*s }>, align 8\n",
                  (int)types.len, types.data, (int)values.len, values.data);
    ms_buf_puts(out, "define i32 @main(i32 %argc, ptr %argv) #0 {\nentry:\n  %n = sext i32 %argc to i64\n"
                     "  %v = ptrtoint ptr %argv to i64\n  %r = call i64 @msrt_start(i64 ptrtoint (ptr ");
    ll_sym(out, entry);
    ms_buf_puts(out, " to i64), i64 ptrtoint (ptr @\"ms.tables\" to i64), i64 %n, i64 %v)\n  %c = trunc i64 %r to i32\n"
                     "  ret i32 %c\n}\nattributes #0 = { \"frame-pointer\"=\"all\" nounwind }\n");
    ms_buf_free(&types);
    ms_buf_free(&values);
    free(words);
    return true;
}
