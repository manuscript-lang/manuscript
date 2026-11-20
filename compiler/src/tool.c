/* The tool interface (include/ms/tool.h): flat tables for Manuscript programs. */
#include "libms.c"
#include <stdlib.h>
#include <string.h>

#include "ms/lex.h"
#include "ms/tool.h"

static void push_int(ms_list *out, int64_t v) {
    ms_value value;
    memset(&value, 0, sizeof value);
    value.kind = MS_INT;
    value.as.i = v;
    ms_list_push(out, &value);
}

uint8_t ms_tool_lex(const ms_str *text, ms_list *out, int64_t *code_out, ms_str *message_out) {
    MsArena arena = {0};
    MsLexed lexed;
    MsDiag diag;
    const char *src = (const char *)ms_str_data(text);
    size_t len = ms_str_len(text);
    if (!ms_utf8_valid(src, len)) {
        static const char msg[] = "invalid UTF-8";
        ms_string_new((const uint8_t *)msg, sizeof msg - 1, message_out);
        *code_out = 0;
        return 1;
    }
    if (!ms_lex(&arena, src, len, &lexed, &diag)) {
        ms_string_new((const uint8_t *)diag.message.ptr, diag.message.len, message_out);
        *code_out = diag.pos.offset;
        ms_arena_free(&arena);
        return 1;
    }
    for (size_t i = 0; i < lexed.ntokens; i++) {
        const MsToken *t = &lexed.tokens[i];
        push_int(out, t->kind);
        push_int(out, t->lo);
        push_int(out, t->hi);
        push_int(out, t->pos.offset);
        push_int(out, t->pos.line);
        push_int(out, t->pos.column);
        push_int(out, t->end.offset);
        push_int(out, t->end.line);
        push_int(out, t->end.column);
    }
    ms_arena_free(&arena);
    return 0;
}

void ms_tool_token_kinds(ms_list *out) {
    for (int k = 0; k < MS_T_COUNT; k++) {
        const char *s = ms_tok_str((MsTok)k);
        ms_value value;
        memset(&value, 0, sizeof value);
        value.kind = MS_STRING;
        value.as.buf.data = (const uint8_t *)s;
        value.as.buf.len = strlen(s);
        ms_list_push(out, &value);
    }
}
