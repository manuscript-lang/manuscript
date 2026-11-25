/* compiler/check/import_fix.c: removing a binding from an import statement (see import_fix.h). */
#include "compiler/check/import_fix.h"
#include "base/chars.h"

#include "base/strbuild.h"
#include "compiler/syntax/lex.h"

typedef struct FixInput {
  MsSpan source;
  const MsToken *tokens;
  size_t count;
  const MsModule *tree;
  const MsImport *item;
  size_t at; /* index of the binding's name token */
} FixInput;

static bool all_space(MsSpan text) {
  for (size_t index = 0; index < text.len; index++) {
    const uint8_t byte = text.ptr[index];
    if (!ms_ascii_is_blank(byte) && byte != '\n' && byte != '\r') {
      return false;
    }
  }
  return true;
}

static MsSpan text_between(MsSpan source, uint32_t from, uint32_t to) {
  MsSpan out = {0};
  return from <= to && ms_span_slice(source, from, to, &out) ? out : (MsSpan){0};
}

static bool has_comment(MsSpan trivia) {
  size_t at = 0;
  return ms_span_find(trivia, ms_span_of_text("//"), &at) || ms_span_find(trivia, ms_span_of_text("/*"), &at);
}

/* The position of byte `offset` of the source. */
static MsPos position_at(MsSpan source, uint32_t offset) {
  MsPos pos = {.offset = offset, .line = 1, .column = 1};
  for (uint32_t index = 0; index < offset; index++) {
    if (source.ptr[index] == '\n') {
      pos.line++;
      pos.column = 1;
    } else {
      pos.column++;
    }
  }
  return pos;
}

/* The first token at or after the statement's `import` keyword. */
static size_t statement_start(const FixInput *in) {
  size_t first = 0;
  while (first < in->count && in->tokens[first].pos.offset < in->item->pos.offset) {
    first++;
  }
  return first;
}

/* Whether the binding sits inside `import ( ... from ... )`. */
static bool in_group(const FixInput *in) {
  const size_t first = statement_start(in);
  if (first + 1 >= in->count || in->tokens[first + 1].kind != MS_T_LParen) {
    return false;
  }
  for (size_t index = first + 2; index < in->count && in->tokens[index].kind != MS_T_RParen; index++) {
    const MsToken *token = &in->tokens[index];
    if (token->kind == MS_T_Name && ms_span_is_text(text_between(in->source, token->pos.offset, token->end.offset), "from")) {
      return true;
    }
  }
  return false;
}

/* The offset after the matching close parenthesis of the group the statement opens. */
static bool statement_end(const FixInput *in, uint32_t *end) {
  size_t depth = 0;
  for (size_t index = statement_start(in) + 1; index < in->count; index++) {
    const MsTok kind = (MsTok)in->tokens[index].kind;
    depth += kind == MS_T_LParen;
    if (kind == MS_T_RParen) {
      if (depth == 0) {
        return false;
      }
      depth--;
      if (depth == 0) {
        *end = in->tokens[index].end.offset;
        return true;
      }
    }
  }
  return false;
}

/* The offset after this clause's path string and the comma that follows it. */
static bool clause_end(const FixInput *in, uint32_t *end) {
  size_t index = statement_start(in);
  while (index < in->count && in->tokens[index].pos.offset < in->item->clause.offset) {
    index++;
  }
  while (index < in->count && in->tokens[index].kind != MS_T_String) {
    index++;
  }
  if (index == in->count) {
    return false;
  }
  uint32_t at = in->tokens[index].end.offset;
  while (at < in->source.len && ms_ascii_is_blank(in->source.ptr[at])) {
    at++;
  }
  *end = at < in->source.len && in->source.ptr[at] == ',' ? at + 1 : at;
  return true;
}

/* The byte range that deletes the binding's clause from a grouped import, or the whole statement; a clause
 * alone on its line takes the line. */
static bool group_removal(const FixInput *in, bool statement, uint32_t *from, uint32_t *to) {
  const uint32_t start = statement ? in->item->pos.offset : in->item->clause.offset;
  uint32_t end = 0;
  if (!(statement ? statement_end(in, &end) : clause_end(in, &end))) {
    return false;
  }
  uint32_t line_start = start;
  while (line_start > 0 && in->source.ptr[line_start - 1] != '\n') {
    line_start--;
  }
  uint32_t line_end = end;
  while (line_end < in->source.len && in->source.ptr[line_end] != '\n') {
    line_end++;
  }
  const bool alone = all_space(text_between(in->source, line_start, start)) &&
                     all_space(text_between(in->source, end, line_end));
  *from = alone ? line_start : start;
  *to = alone ? (line_end < in->source.len ? line_end + 1 : line_end) : end;
  return true;
}

/* Whether the statement holds only this clause. */
static bool only_clause(const FixInput *in) {
  for (uint32_t index = 0; index < in->tree->nimports; index++) {
    const MsImport *other = &in->tree->imports[index];
    if (other->pos.offset == in->item->pos.offset && other->clause.offset != in->item->clause.offset) {
      return false;
    }
  }
  return true;
}

static bool fix_group(const FixInput *in, MsImportFix *fix) {
  uint32_t from = 0;
  uint32_t to = 0;
  if (!group_removal(in, only_clause(in), &from, &to)) {
    return false;
  }
  *fix = (MsImportFix){.pos = position_at(in->source, from), .end = position_at(in->source, to), .text = ms_string_empty()};
  return true;
}

/* The comments between two tokens, kept when the binding goes. */
static MsString kept_comments(const FixInput *in, uint32_t from, uint32_t to) {
  const MsSpan trivia = text_between(in->source, from, to);
  return has_comment(trivia) ? ms_string_from_span(trivia) : ms_string_empty();
}

/* One binding among several of one clause: it goes with a neighbouring comma. */
static bool fix_among(const FixInput *in, MsImportFix *fix) {
  const MsToken *tokens = in->tokens;
  const size_t at = in->at;
  const bool last = at + 2 >= in->count || tokens[at + 2].kind == MS_T_RParen;
  const bool previous_comma = at > 0 && tokens[at - 1].kind == MS_T_Comma;
  if (at + 1 < in->count && tokens[at + 1].kind == MS_T_Comma && !(last && previous_comma)) {
    const MsToken *comma = &tokens[at + 1];
    MsPos end = comma->end;
    if (at + 2 < in->count && tokens[at + 2].pos.line == comma->end.line) {
      end = tokens[at + 2].pos;
    }
    *fix = (MsImportFix){.pos = tokens[at].pos, .end = end,
                         .text = kept_comments(in, tokens[at].end.offset, comma->pos.offset)};
    return true;
  }
  if (previous_comma) {
    const MsToken *comma = &tokens[at - 1];
    const MsPos end = at + 1 < in->count && tokens[at + 1].kind == MS_T_Comma ? tokens[at + 1].end : tokens[at].end;
    *fix = (MsImportFix){.pos = comma->pos, .end = end, .text = kept_comments(in, comma->end.offset, tokens[at].pos.offset)};
    return true;
  }
  return false;
}

/* Extends a deletion to the rest of its line when nothing else is on it. */
static void take_line(const FixInput *in, MsImportFix *fix) {
  const MsSpan tail = text_between(in->source, fix->end.offset, (uint32_t)in->source.len);
  size_t first = 0;
  while (first < tail.len && tail.ptr[first] != '\n') {
    first++;
  }
  if (first < tail.len && all_space(ms_span_of(tail.ptr, first))) {
    fix->end.offset += (uint32_t)first + 1;
    fix->end.line += 1;
    fix->end.column = 1;
  } else if (all_space(tail)) {
    fix->end.offset = (uint32_t)in->source.len;
    fix->end.column += (uint32_t)tail.len;
  }
}

/* The only binding of its statement: the whole statement goes, with the comments inside it. */
static bool fix_statement(const FixInput *in, MsImportFix *fix) {
  MsPos end = in->tokens[in->at].end;
  MsStrBuild comments = ms_strbuild_new();
  uint32_t previous = in->item->pos.offset;
  for (size_t index = 0; index < in->count; index++) {
    const MsToken *token = &in->tokens[index];
    if (token->pos.offset < in->item->pos.offset) {
      continue;
    }
    const MsSpan trivia = text_between(in->source, previous, token->pos.offset);
    if (has_comment(trivia)) {
      ms_strbuild_append(&comments, trivia);
    }
    previous = token->end.offset;
    if (token->kind == MS_T_String) {
      end = token->end;
      break;
    }
  }
  const bool kept = ms_strbuild_length(&comments) != 0;
  *fix = (MsImportFix){.pos = in->item->pos, .end = end, .text = ms_strbuild_finish(&comments)};
  if (!kept) {
    take_line(in, fix);
  }
  return true;
}

bool ms_import_fix(MsArena *arena, const MsModule *tree, uint32_t index, MsSpan source, MsImportFix *fix) {
  MsLexed lexed = {0};
  MsDiag diag = {0};
  if (!ms_lex(arena, source, &lexed, &diag)) {
    return false;
  }
  FixInput in = {.source = source, .tokens = lexed.tokens, .count = lexed.ntokens, .tree = tree,
                 .item = &tree->imports[index]};
  while (in.at < in.count && in.tokens[in.at].pos.offset != in.item->name_pos.offset) {
    in.at++;
  }
  if (in.at == in.count) {
    return false;
  }
  uint32_t siblings = 0;
  for (uint32_t other = 0; other < tree->nimports; other++) {
    siblings += tree->imports[other].clause.offset == in.item->clause.offset;
  }
  if (siblings == 1 && in_group(&in)) {
    return fix_group(&in, fix);
  }
  return siblings > 1 ? fix_among(&in, fix) : fix_statement(&in, fix);
}
