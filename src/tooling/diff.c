/* Owns diff.h. */
#include "tooling/diff.h"

#include "base/chars.h"

static MsSpan text(const char *literal) {
  return ms_span_of_text(literal);
}

MsSpan ms_diff_path(const MsDiffFile *file) {
  return file->new.len == 0 ? file->old : file->new;
}

void ms_diff_touched(MsArena *arena, const MsDiffFile *file, int64_t **lines, size_t *count) {
  size_t total = 0;
  for (size_t h = 0; h < file->hunks.len; h++) {
    total += file->hunks.ptr[h].lines.len;
  }
  int64_t *out = MS_ARENA_NEW_ARRAY(arena, int64_t, total + 1);
  size_t n = 0;
  for (size_t h = 0; h < file->hunks.len; h++) {
    const MsDiffHunk *hunk = &file->hunks.ptr[h];
    int64_t line = hunk->new_start + (hunk->new_len == 0 ? 1 : 0);
    for (size_t i = 0; i < hunk->lines.len; i++) {
      const uint8_t first = hunk->lines.ptr[i].ptr[0];
      if (first == '+' || first == '-') {
        out[n++] = line;
      }
      line += first != '-' ? 1 : 0;
    }
  }
  *lines = out;
  *count = n;
}

/* ---- lines ---- */

/* The lines of `text` split at `\n`, a final terminator ending the last line (Rust `split_terminator`). */
static MsSpans split_terminator(MsArena *arena, MsSpan source) {
  MsSpans lines = {0};
  size_t start = 0;
  for (size_t i = 0; i < source.len; i++) {
    if (source.ptr[i] == '\n') {
      ms_spans_push(arena, &lines, ms_span_of(source.ptr + start, i - start));
      start = i + 1;
    }
  }
  if (start < source.len) {
    ms_spans_push(arena, &lines, ms_span_of(source.ptr + start, source.len - start));
  }
  return lines;
}

static bool starts(MsSpan line, const char *prefix) {
  return ms_span_starts_with(line, ms_span_of_text(prefix));
}

static MsSpan rest(MsSpan line, size_t from) {
  return ms_span_of(line.ptr + from, line.len - from);
}

/* ---- paths ---- */

static bool quoted_path(MsArena *arena, MsSpan path, MsSpan *out, MsSpan *error) {
  const MsSpan malformed = text("malformed Git quoted path");
  if (path.len < 2 || path.ptr[0] != '"' || path.ptr[path.len - 1] != '"') {
    *error = malformed;
    return false;
  }
  const MsSpan body = ms_span_of(path.ptr + 1, path.len - 2);
  uint8_t *bytes = MS_ARENA_NEW_ARRAY(arena, uint8_t, body.len + 1);
  size_t n = 0;
  for (size_t i = 0; i < body.len; i++) {
    const uint8_t b = body.ptr[i];
    if (b == '"') {
      *error = malformed;
      return false;
    }
    if (b != '\\') {
      bytes[n++] = b;
      continue;
    }
    if (++i >= body.len) {
      *error = malformed;
      return false;
    }
    const uint8_t e = body.ptr[i];
    uint8_t value = 0;
    switch (e) {
    case '"': case '\\': value = e; break;
    case 'a': value = 7; break;
    case 'b': value = 8; break;
    case 't': value = '\t'; break;
    case 'n': value = '\n'; break;
    case 'v': value = 11; break;
    case 'f': value = 12; break;
    case 'r': value = '\r'; break;
    case '0': case '1': case '2': case '3': {
      if (i + 2 >= body.len || body.ptr[i + 1] < '0' || body.ptr[i + 1] > '7' || body.ptr[i + 2] < '0' || body.ptr[i + 2] > '7') {
        *error = malformed;
        return false;
      }
      value = (uint8_t)((e - '0') * 64 + (body.ptr[i + 1] - '0') * 8 + (body.ptr[i + 2] - '0'));
      i += 2;
      break;
    }
    default: *error = malformed; return false;
    }
    bytes[n++] = value;
  }
  for (size_t i = 0; i < n; i++) {
    if (bytes[i] == 0) {
      *error = text("Git path contains a NUL byte");
      return false;
    }
  }
  *out = ms_span_of(bytes, n);
  return true;
}

/* The path of a `---` or `+++` header field. */
static bool diff_path(MsArena *arena, MsSpan field, const char *prefix, bool git, MsSpan *out, MsSpan *error) {
  MsSpan path = field;
  for (size_t i = 0; i < field.len; i++) {
    if (field.ptr[i] == '\t') {
      path = ms_span_of(field.ptr, i);
      break;
    }
  }
  if (!git) {
    path = ms_span_trim(path);
  }
  if (ms_span_is_text(path, "/dev/null")) {
    *out = (MsSpan){0};
    return true;
  }
  if (!git) {
    *out = path;
    return true;
  }
  if (path.len > 0 && path.ptr[0] == '"' && !quoted_path(arena, path, &path, error)) {
    return false;
  }
  const char *other = prefix[0] == 'a' ? "b/" : "a/";
  if (starts(path, prefix)) {
    *out = rest(path, 2);
  } else if (starts(path, other)) {
    *out = rest(path, 2);
  } else {
    *out = path;
  }
  return true;
}

/* A non-renamed Git section repeats the same path with a/ and b/ prefixes. */
static bool git_section_path(MsArena *arena, MsSpan fields, MsSpan *out) {
  const size_t half = fields.len / 2;
  const MsSpan old = ms_span_of(fields.ptr, half);
  MsSpan new = rest(fields, half);
  if (new.len == 0 || new.ptr[0] != ' ') {
    return false;
  }
  new = rest(new, 1);
  MsSpan a = {0};
  MsSpan b = {0};
  MsSpan ignored = {0};
  if (!diff_path(arena, old, "a/", true, &a, &ignored) || !diff_path(arena, new, "b/", true, &b, &ignored) ||
      !ms_span_equal(a, b)) {
    return false;
  }
  *out = a;
  return true;
}

/* ---- hunks ---- */

static bool parse_number(MsSpan s, int64_t *out) {
  if (s.len == 0 || s.len > 17) {
    return false;
  }
  int64_t value = 0;
  for (size_t i = 0; i < s.len; i++) {
    if (s.ptr[i] < '0' || s.ptr[i] > '9') {
      return false;
    }
    value = value * 10 + (s.ptr[i] - '0');
  }
  *out = value;
  return true;
}

static bool parse_range(MsArena *arena, MsSpan range, int64_t *start, int64_t *length, MsSpan *error) {
  size_t comma = 0;
  const bool has_length = ms_span_find(range, text(","), &comma);
  const MsSpan first = has_length ? ms_span_of(range.ptr, comma) : range;
  const MsSpan second = has_length ? rest(range, comma + 1) : (MsSpan){0};
  if (!parse_number(first, start) || (has_length && !parse_number(second, length))) {
    *error = ms_message_format(arena, "malformed hunk range \"%S\"", range);
    return false;
  }
  if (!has_length) {
    *length = 1;
  }
  if (*start == 0 && *length != 0) {
    *error = ms_message_format(arena, "malformed hunk range \"%S\"", range);
    return false;
  }
  return true;
}

static bool record_no_newline(MsDiffHunk *hunk, int64_t old_left, int64_t new_left) {
  if (hunk->lines.len == 0) {
    return false;
  }
  const uint8_t last = hunk->lines.ptr[hunk->lines.len - 1].ptr[0];
  const bool old = last != '+';
  const bool new = last != '-';
  if ((old && old_left != 0) || (new && new_left != 0)) {
    return false;
  }
  hunk->old_no_newline = hunk->old_no_newline || old;
  hunk->new_no_newline = hunk->new_no_newline || new;
  return true;
}

static bool fail(MsArena *arena, MsSpan *error, const char *format, size_t line) {
  *error = ms_message_format(arena, format, line);
  return false;
}

static bool parse_hunk(MsArena *arena, const MsSpans *lines, size_t start, MsDiffHunk *h, size_t *next, MsSpan *error) {
  const MsSpan header = lines->ptr[start];
  const MsSpan body = rest(header, 3);
  size_t end = 0;
  size_t space = 0;
  if (!ms_span_find(body, text(" @@"), &end)) {
    return fail(arena, error, "diff line %z: malformed hunk header", start + 1);
  }
  const MsSpan ranges = ms_span_of(body.ptr, end);
  if (!ms_span_find(ranges, text(" "), &space) || ranges.ptr[0] != '-' || ranges.ptr[space + 1] != '+') {
    return fail(arena, error, "diff line %z: malformed hunk header", start + 1);
  }
  MsSpan reason = {0};
  if (!parse_range(arena, ms_span_of(ranges.ptr + 1, space - 1), &h->old_start, &h->old_len, &reason) ||
      !parse_range(arena, rest(ranges, space + 2), &h->new_start, &h->new_len, &reason)) {
    *error = ms_message_format(arena, "diff line %z: %S", start + 1, reason);
    return false;
  }
  int64_t old_left = h->old_len;
  int64_t new_left = h->new_len;
  size_t i = start + 1;
  while (i < lines->len && (old_left > 0 || new_left > 0)) {
    MsSpan line = lines->ptr[i];
    if (line.len > 0 && line.ptr[0] == '\\') {
      if (!record_no_newline(h, old_left, new_left)) {
        return fail(arena, error, "diff line %z: no-newline marker is not after the final line of its side", i + 1);
      }
      i++;
      continue;
    }
    if (line.len == 0) {
      line = text(" ");
    }
    switch (line.ptr[0]) {
    case ' ': old_left--; new_left--; break;
    case '-': old_left--; break;
    case '+': new_left--; break;
    default: return fail(arena, error, "diff line %z: hunk ends before its declared length", i + 1);
    }
    ms_spans_push(arena, &h->lines, line);
    i++;
  }
  if (old_left != 0 || new_left != 0) {
    return fail(arena, error, "diff line %z: hunk is shorter than its header declares", start + 1);
  }
  while (i < lines->len && lines->ptr[i].len > 0 && lines->ptr[i].ptr[0] == '\\') {
    if (!record_no_newline(h, 0, 0)) {
      return fail(arena, error, "diff line %z: no-newline marker is not after the final line of its side", i + 1);
    }
    i++;
  }
  while (i < lines->len && lines->ptr[i].len == 0) {
    i++;
  }
  if (i < lines->len) {
    const MsSpan line = lines->ptr[i];
    const bool marker = line.len > 0 && (line.ptr[0] == ' ' || line.ptr[0] == '+' || line.ptr[0] == '-');
    const bool text_header = starts(line, "--- ") && i + 1 < lines->len && starts(lines->ptr[i + 1], "+++ ");
    if (!ms_span_is_text(line, "-- ") && marker && !text_header) {
      return fail(arena, error, "diff line %z: hunk is longer than its header declares", i + 1);
    }
  }
  *next = i;
  return true;
}

/* ---- parse ---- */

static MsSpan replace_crlf(MsArena *arena, MsSpan source) {
  uint8_t *out = MS_ARENA_NEW_ARRAY(arena, uint8_t, source.len + 1);
  size_t n = 0;
  for (size_t i = 0; i < source.len; i++) {
    if (source.ptr[i] == '\r' && i + 1 < source.len && source.ptr[i + 1] == '\n') {
      continue;
    }
    out[n++] = source.ptr[i];
  }
  return ms_span_of(out, n);
}

bool ms_diff_parse(MsArena *arena, MsSpan input, MsDiffFiles *files, MsSpan *error) {
  const MsSpan source = replace_crlf(arena, input);
  const MsSpans lines = split_terminator(arena, source);
  bool have_current = false;
  bool git = false;
  MsSpan git_header = {0};
  bool has_header = false;
  size_t i = 0;
  while (i < lines.len) {
    const MsSpan line = lines.ptr[i];
    if (starts(line, "diff --git ")) {
      git_header = rest(line, 11);
      has_header = true;
      ms_diff_files_push(arena, files, (MsDiffFile){0});
      have_current = true;
      git = true;
    } else if (starts(line, "rename from ") || starts(line, "rename to ")) {
      *error = text("renamed files are not supported; produce the diff with git diff --no-renames");
      return false;
    } else if (starts(line, "--- ") && i + 1 < lines.len && starts(lines.ptr[i + 1], "+++ ")) {
      if (!have_current || !git) {
        ms_diff_files_push(arena, files, (MsDiffFile){0});
        have_current = true;
      }
      MsDiffFile *current = &files->ptr[files->len - 1];
      if (git && current->hunks.len > 0) {
        return fail(arena, error, "diff line %z: multiple text headers in one Git file section", i + 1);
      }
      MsSpan reason = {0};
      if (!diff_path(arena, rest(line, 4), "a/", git, &current->old, &reason)) {
        *error = ms_message_format(arena, "diff line %z: %S", i + 1, reason);
        return false;
      }
      if (!diff_path(arena, rest(lines.ptr[i + 1], 4), "b/", git, &current->new, &reason)) {
        *error = ms_message_format(arena, "diff line %z: %S", i + 2, reason);
        return false;
      }
      if (!git && starts(current->old, "a/") && starts(current->new, "b/") &&
          ms_span_equal(rest(current->old, 2), rest(current->new, 2))) {
        current->old = rest(current->old, 2);
        current->new = rest(current->new, 2);
      }
      i++;
    } else if (starts(line, "@@ ")) {
      if (!have_current) {
        return fail(arena, error, "diff line %z: hunk before any file header", i + 1);
      }
      MsDiffHunk hunk = {0};
      size_t next = 0;
      if (!parse_hunk(arena, &lines, i, &hunk, &next, error)) {
        return false;
      }
      ms_diff_hunks_push(arena, &files->ptr[files->len - 1].hunks, hunk);
      i = next;
      continue;
    } else if (git && have_current &&
               (starts(line, "old mode ") || starts(line, "new mode ") || starts(line, "new file mode ") ||
                starts(line, "deleted file mode ") || starts(line, "Binary files ") ||
                ms_span_is_text(line, "GIT binary patch"))) {
      if (starts(line, "Binary files ") || ms_span_is_text(line, "GIT binary patch")) {
        *error = text("binary diff cannot reconstruct the base; produce a text diff with git diff --text --no-renames");
        return false;
      }
      MsDiffFile *current = &files->ptr[files->len - 1];
      MsSpan path = {0};
      if (current->old.len == 0 && current->new.len == 0 && has_header && git_section_path(arena, git_header, &path)) {
        has_header = false;
        current->old = path;
        current->new = path;
      }
      if (starts(line, "new file mode ")) {
        current->old = (MsSpan){0};
      } else if (starts(line, "deleted file mode ")) {
        current->new = (MsSpan){0};
      }
    }
    i++;
  }
  if (files->len == 0 && ms_span_trim(source).len > 0) {
    *error = text("input is not a unified diff; pipe in git diff --no-renames");
    return false;
  }
  for (size_t f = 0; f < files->len; f++) {
    const MsDiffFile *file = &files->ptr[f];
    if (file->old.len == 0 && file->new.len == 0) {
      *error = text("diff has a file header with no paths");
      return false;
    }
    if (file->old.len > 0 && file->new.len > 0 && !ms_span_equal(file->old, file->new)) {
      *error = ms_message_format(arena, "renamed files are not supported (%S -> %S); produce the diff with git diff --no-renames",
                                 file->old, file->new);
      return false;
    }
  }
  return true;
}

/* ---- reverse application ---- */

static bool same(MsSpan a, MsSpan b) {
  while (a.len > 0 && a.ptr[a.len - 1] == '\r') {
    a.len--;
  }
  while (b.len > 0 && b.ptr[b.len - 1] == '\r') {
    b.len--;
  }
  return ms_span_equal(a, b);
}

bool ms_diff_reverse_apply(MsArena *arena, MsSpan head, const MsDiffHunks *hunks, MsSpan *result, MsSpan *error) {
  const MsSpans source = split_terminator(arena, head);
  const bool head_newline = head.len > 0 && head.ptr[head.len - 1] == '\n';
  bool trailing_newline = head_newline;
  bool has_old_eof = false;
  size_t old_eof = 0;
  MsSpans out = {0};
  size_t position = 0;
  for (size_t h = 0; h < hunks->len; h++) {
    const MsDiffHunk *hunk = &hunks->ptr[h];
    int64_t index = hunk->new_len == 0 ? hunk->new_start : hunk->new_start - 1;
    if (index < (int64_t)position || index > (int64_t)source.len) {
      *error = ms_message_format(arena, "hunks overlap or fall outside the file at line %z", (size_t)hunk->new_start);
      return false;
    }
    size_t at = (size_t)index;
    for (size_t k = position; k < at; k++) {
      ms_spans_push(arena, &out, source.ptr[k]);
    }
    if (hunk->old_start - (hunk->old_len > 0 ? 1 : 0) != (int64_t)out.len) {
      *error = ms_message_format(arena, "old hunk position %z does not match the reconstructed base", (size_t)hunk->old_start);
      return false;
    }
    for (size_t l = 0; l < hunk->lines.len; l++) {
      const MsSpan line = hunk->lines.ptr[l];
      const MsSpan body = rest(line, 1);
      if (line.ptr[0] == '-') {
        ms_spans_push(arena, &out, body);
        continue;
      }
      if (at >= source.len || !same(source.ptr[at], body)) {
        *error = ms_message_format(arena, "line %z does not match the diff", at + 1);
        return false;
      }
      if (line.ptr[0] == ' ') {
        ms_spans_push(arena, &out, source.ptr[at]);
      }
      at++;
    }
    if (has_old_eof && old_eof != out.len) {
      *error = text("no-newline marker appears before the end of the base file");
      return false;
    }
    if (hunk->old_no_newline) {
      has_old_eof = true;
      old_eof = out.len;
    }
    if (hunk->new_no_newline && at != source.len) {
      *error = text("no-newline marker appears before the end of the file");
      return false;
    }
    if (at == source.len) {
      if (hunk->new_len > 0 && hunk->new_no_newline == head_newline) {
        *error = text("final newline does not match the diff");
        return false;
      }
      trailing_newline = !has_old_eof;
    }
    position = at;
  }
  for (size_t k = position; k < source.len; k++) {
    ms_spans_push(arena, &out, source.ptr[k]);
  }
  if (has_old_eof && old_eof != out.len) {
    *error = text("no-newline marker appears before the end of the base file");
    return false;
  }
  MsStrBuild joined = ms_strbuild_new();
  for (size_t k = 0; k < out.len; k++) {
    ms_strbuild_append_text(&joined, k == 0 ? "" : "\n");
    ms_strbuild_append(&joined, out.ptr[k]);
  }
  if (out.len > 0 && trailing_newline) {
    ms_strbuild_append_text(&joined, "\n");
  }
  *result = ms_arena_copy(arena, ms_strbuild_span(&joined));
  ms_strbuild_free(&joined);
  return true;
}
