/* Redundant prelude import fixes (ms/prelude_fix.h). */
#include "ms/text.h"
#include "ms/prelude_fix.h"
#include "ms_rt/chars.h"

#include <string.h>

#include "ms/lex.h"

typedef struct PfTokens {
    const MsToken *items;
    size_t count;
} PfTokens;

/* ---- text helpers ---- */

static bool pf_is_all_blank(MsStr s) {
    for (uint32_t i = 0; i < s.len; i++) {
        if (!ms_ascii_is_space((uint8_t)s.ptr[i])) {
            return false;
        }
    }
    return true;
}

/* The first `\n` at or after `from`, or the source length. */
static size_t pf_line_end(MsStr s, size_t from) {
    while (from < s.len && s.ptr[from] != '\n') {
        from++;
    }
    return from;
}

/* The start of the line holding byte `offset`. */
static size_t pf_line_start(MsStr s, size_t offset) {
    while (offset > 0 && s.ptr[offset - 1] != '\n') {
        offset--;
    }
    return offset;
}

/* `source.get(from..to).unwrap_or("")`, ignoring character boundaries (the offsets come from
 * tokens). */
static MsStr pf_text(MsStr source, size_t from, size_t to) {
    if (from > to || to > source.len) {
        return (MsStr){"", 0};
    }
    return (MsStr){source.ptr + from, (uint32_t)(to - from)};
}

static bool pf_is_comment_trivia(MsStr trivia) {
    return ms_text_contains(trivia, "//") || ms_text_contains(trivia, "/*");
}

/* Position of byte `offset` of the source, by counting lines. */
static MsPos pf_pos_at(MsStr source, size_t offset) {
    uint32_t line = 1;
    for (size_t i = 0; i < offset; i++) {
        line += source.ptr[i] == '\n';
    }
    return (MsPos){(uint32_t)offset, line, (uint32_t)(offset - pf_line_start(source, offset)) + 1};
}

/* ---- import statements in the token stream ---- */

/* The tokens of `item`'s statement, starting at `import`. */
static PfTokens pf_statement_tokens(const MsImport *item, PfTokens tokens) {
    size_t first = 0;
    while (first < tokens.count && tokens.items[first].pos.offset < item->pos.offset) {
        first++;
    }
    return (PfTokens){tokens.items + first, tokens.count - first};
}

/* Whether the binding sits inside a group of clauses (`import (A from "a", B from "b")`), as
 * opposed to a single clause. Reads lexer tokens, so comments and text never count. */
static bool pf_in_group(MsStr source, const MsImport *item, PfTokens tokens) {
    PfTokens rest = pf_statement_tokens(item, tokens);
    if (rest.count < 2 || rest.items[1].kind != MS_T_LParen) {
        return false;
    }
    for (size_t i = 2; i < rest.count && rest.items[i].kind != MS_T_RParen; i++) {
        MsStr text = pf_text(source, rest.items[i].pos.offset, rest.items[i].end.offset);
        if (rest.items[i].kind == MS_T_Name && text.len == 4 && memcmp(text.ptr, "from", 4) == 0) {
            return true;
        }
    }
    return false;
}

/* The offset just after the `)` that closes the statement's group. */
static bool pf_statement_end(PfTokens rest, size_t *end) {
    size_t depth = 0;
    for (size_t i = 1; i < rest.count; i++) {
        if (rest.items[i].kind == MS_T_LParen) {
            depth++;
        } else if (rest.items[i].kind == MS_T_RParen) {
            if (depth == 0) {
                return false;
            }
            depth--;
            if (depth == 0) {
                *end = rest.items[i].end.offset;
                return true;
            }
        }
    }
    return false;
}

/* The offset after the clause's path string, its trailing blanks and comma. */
static bool pf_clause_end(MsStr source, const MsImport *item, PfTokens rest, size_t *end) {
    size_t from = 0;
    while (from < rest.count && rest.items[from].pos.offset < item->clause.offset) {
        from++;
    }
    while (from < rest.count && rest.items[from].kind != MS_T_String) {
        from++;
    }
    if (from == rest.count || rest.items[from].end.offset > source.len) {
        return false;
    }
    size_t at = rest.items[from].end.offset;
    while (at < source.len && (source.ptr[at] == ' ' || source.ptr[at] == '\t')) {
        at++;
    }
    *end = at < source.len && source.ptr[at] == ',' ? at + 1 : at;
    return true;
}

/* The byte range that deletes this binding's whole clause from a grouped import, or the whole
 * statement when `statement` is set. The range takes the clause's trailing comma and, when the
 * clause is alone on its line, the line itself. */
static bool pf_group_removal(MsStr source, const MsImport *item, PfTokens tokens, bool statement,
                             size_t *out_start, size_t *out_end) {
    size_t start = statement ? item->pos.offset : item->clause.offset;
    PfTokens rest = pf_statement_tokens(item, tokens);
    size_t end;
    bool found = statement ? rest.count >= 1 && pf_statement_end(rest, &end)
                           : pf_clause_end(source, item, rest, &end);
    if (!found || start > source.len || end > source.len) {
        return false;
    }
    size_t line_start = pf_line_start(source, start);
    size_t line_stop = pf_line_end(source, end);
    MsStr before = pf_text(source, line_start, start);
    MsStr after = pf_text(source, end, line_stop);
    if (pf_is_all_blank(before) && pf_is_all_blank(after)) {
        end = line_stop + (line_stop < source.len ? 1 : 0);
        start = line_start;
    }
    *out_start = start;
    *out_end = end;
    return true;
}

/* ---- tokens when the whole file does not lex ---- */

/* Lexes only the complete declaration of `item`, with positions shifted back into the whole
 * file. A recovering editor snapshot can retain a valid import alongside unrelated lexer errors. */
static bool pf_declaration_tokens(MsArena *arena, MsStr source, const MsImport *item, PfTokens *out) {
    size_t start = item->pos.offset;
    size_t end = start;
    while (end < source.len) {
        end = pf_line_end(source, end);
        end += end < source.len ? 1 : 0;
        MsLexed lexed;
        MsDiag diag;
        if (!ms_lex(arena, source.ptr + start, end - start, &lexed, &diag)) {
            continue;
        }
        bool has_string = false;
        for (size_t i = 0; i < lexed.ntokens; i++) {
            has_string = has_string || lexed.tokens[i].kind == MS_T_String;
        }
        if (!has_string) {
            continue;
        }
        for (size_t i = 0; i < lexed.ntokens; i++) {
            MsPos *ends[2] = {&lexed.tokens[i].pos, &lexed.tokens[i].end};
            for (size_t k = 0; k < 2; k++) {
                ends[k]->column += ends[k]->line == 1 ? item->pos.column - 1 : 0;
                ends[k]->line += item->pos.line - 1;
                ends[k]->offset += (uint32_t)start;
            }
        }
        *out = (PfTokens){lexed.tokens, lexed.ntokens};
        return true;
    }
    return false;
}

/* The tokens of the file, or of the import's own declaration when the file does not lex. */
static bool pf_tokens(MsArena *arena, MsStr source, const MsImport *item, PfTokens *out) {
    MsLexed lexed;
    MsDiag diag;
    if (ms_lex(arena, source.ptr, source.len, &lexed, &diag)) {
        *out = (PfTokens){lexed.tokens, lexed.ntokens};
        return true;
    }
    return pf_declaration_tokens(arena, source, item, out);
}

/* ---- the fixes ---- */

static MsStr pf_comments_only(MsStr trivia) {
    return pf_is_comment_trivia(trivia) ? trivia : (MsStr){"", 0};
}

static MsStr pf_join(MsArena *arena, MsStr a, MsStr b) {
    return ms_arena_fmt(arena, "%.*s%.*s", (int)a.len, a.ptr, (int)b.len, b.ptr);
}

/* One binding of a group of several: its edit takes the comma after it, or before it for the last
 * binding. The last binding's edit then overlaps its neighbour's, so redundant names are removed
 * over successive runs until the whole import goes, never leaving an empty `import ( ) from ...`. */
static bool pf_group_binding(MsStr source, PfTokens tokens, size_t at, MsFix *out) {
    const MsToken *t = tokens.items;
    bool last = at + 2 >= tokens.count || t[at + 2].kind == MS_T_RParen;
    bool previous_comma = at > 0 && t[at - 1].kind == MS_T_Comma;
    bool next_comma = at + 1 < tokens.count && t[at + 1].kind == MS_T_Comma;
    if (next_comma && !(last && previous_comma)) {
        MsPos end = t[at + 1].end;
        if (at + 2 < tokens.count && t[at + 2].pos.line == t[at + 1].end.line) {
            end = t[at + 2].pos;
        }
        MsStr between = pf_text(source, t[at].end.offset, t[at + 1].pos.offset);
        *out = (MsFix){t[at].pos, end, pf_comments_only(between)};
        return true;
    }
    if (previous_comma) {
        MsPos end = next_comma ? t[at + 1].end : t[at].end;
        MsStr between = pf_text(source, t[at - 1].end.offset, t[at].pos.offset);
        *out = (MsFix){t[at - 1].pos, end, pf_comments_only(between)};
        return true;
    }
    return false;
}

/* Deletes a singleton import, retaining any comments inside a multiline group and any trailing
 * comment after the path string, and the line when nothing else is on it. */
static MsFix pf_singleton(MsArena *arena, MsStr source, const MsImport *item, PfTokens tokens, size_t at) {
    MsPos end = tokens.items[at].end;
    MsStr comments = {"", 0};
    size_t previous = item->pos.offset;
    for (size_t i = 0; i < tokens.count; i++) {
        const MsToken *token = &tokens.items[i];
        if (token->pos.offset < item->pos.offset) {
            continue;
        }
        MsStr trivia = pf_text(source, previous, token->pos.offset);
        if (pf_is_comment_trivia(trivia)) {
            comments = pf_join(arena, comments, trivia);
        }
        previous = token->end.offset;
        if (token->kind == MS_T_String) {
            end = token->end;
            break;
        }
    }
    MsFix fix = {item->pos, end, comments};
    if (comments.len != 0) {
        return fix;
    }
    MsStr tail = pf_text(source, end.offset, source.len);
    size_t newline = pf_line_end(tail, 0);
    if (newline < tail.len && pf_is_all_blank(pf_text(tail, 0, newline))) {
        fix.end.offset += (uint32_t)newline + 1;
        fix.end.line += 1;
        fix.end.column = 1;
    } else if (pf_is_all_blank(tail)) {
        fix.end.offset = source.len;
        fix.end.column += tail.len;
    }
    return fix;
}

MsStr ms_prelude_import_message(MsArena *arena, MsStr name) {
    return ms_arena_fmt(arena,
                        "redundant prelude import %.*s; remove %.*s from this import and use its "
                        "prelude declaration directly",
                        (int)name.len, name.ptr, (int)name.len, name.ptr);
}

bool ms_prelude_import_fix(MsArena *arena, MsStr source, const MsImport *imports, uint32_t nimports,
                           const MsImport *item, MsFix *out) {
    PfTokens tokens;
    if (!pf_tokens(arena, source, item, &tokens) || tokens.count == 0) {
        return false;
    }
    size_t at = 0;
    while (at < tokens.count && tokens.items[at].pos.offset != item->name_pos.offset) {
        at++;
    }
    if (at == tokens.count) {
        return false;
    }
    uint32_t count = 0;
    bool only = true;
    for (uint32_t i = 0; i < nimports; i++) {
        count += imports[i].clause.offset == item->clause.offset;
        only = only && (imports[i].pos.offset != item->pos.offset || imports[i].clause.offset == item->clause.offset);
    }
    if (count == 1 && pf_in_group(source, item, tokens)) {
        size_t start;
        size_t end;
        if (!pf_group_removal(source, item, tokens, only, &start, &end)) {
            return false;
        }
        *out = (MsFix){pf_pos_at(source, start), pf_pos_at(source, end), {"", 0}};
        return true;
    }
    if (count > 1) {
        return pf_group_binding(source, tokens, at, out);
    }
    *out = pf_singleton(arena, source, item, tokens, at);
    return true;
}
