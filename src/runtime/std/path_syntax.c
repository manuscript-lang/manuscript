/* runtime/std/path_syntax.c: the syntax tree of a glob segment and its parser: classes, extended groups,
 * literals and the alternatives inside a group. */
#include "runtime/std/path_internal.h"

void path_seq_free(MsSeq *seq) {
  for (size_t i = 0; i < seq->count; i++) {
    MsAtom *atom = &seq->atoms[i];
    ms_free(atom->ranges);
    for (size_t a = 0; a < atom->alternative_count; a++) {
      path_seq_free(&atom->alternatives[a]);
    }
    ms_free(atom->alternatives);
  }
  ms_free(seq->atoms);
  *seq = (MsSeq){0};
}

/* Appends a zeroed atom of `kind` and returns it; NULL when out of memory. */
static MsAtom *seq_push(MsSeq *seq, MsAtomKind kind) {
  if (!path_array_reserve((void **)&seq->atoms, &seq->capacity, seq->count, seq->count + 1, sizeof(MsAtom))) {
    return NULL;
  }
  MsAtom *atom = &seq->atoms[seq->count++];
  atom->kind = kind;
  return atom;
}

static MsChars chars_from(MsChars chars, size_t start) {
  return start <= chars.len ? (MsChars){.ptr = chars.ptr + start, .len = chars.len - start} : (MsChars){0};
}

/* One class member, escaped or plain (Go's path.getEsc): false for an end, `-` or `]`, or when nothing would
 * remain after it, since the class's closing `]` must. */
static bool class_member(MsChars chunk, uint32_t *member, MsChars *rest) {
  if (chunk.len == 0 || chunk.ptr[0] == '-' || chunk.ptr[0] == ']') {
    return false;
  }
  MsChars at = chunk;
  if (at.ptr[0] == '\\') {
    at = chars_from(at, 1);
    if (at.len == 0) {
      return false;
    }
  }
  *member = at.ptr[0];
  *rest = chars_from(at, 1);
  return rest->len != 0;
}

/* Parses the members of a class after its `[` (and `^`), through the closing `]`. */
static MsPathResult parse_class_members(MsChars chunk, MsAtom *atom) {
  size_t capacity = 0;
  for (;;) {
    if (chunk.len != 0 && chunk.ptr[0] == ']' && atom->range_count != 0) {
      return PATH_OK;
    }
    uint32_t low = 0;
    if (!class_member(chunk, &low, &chunk)) {
      return PATH_INVALID;
    }
    uint32_t high = low;
    if (chunk.len != 0 && chunk.ptr[0] == '-') {
      if (!class_member(chars_from(chunk, 1), &high, &chunk)) {
        return PATH_INVALID;
      }
    }
    if (!path_array_reserve((void **)&atom->ranges, &capacity, atom->range_count, atom->range_count + 1,
                            sizeof(MsRange))) {
      return PATH_NO_MEMORY;
    }
    atom->ranges[atom->range_count++] = (MsRange){.low = low, .high = high};
  }
}

/* Index of the `]` that closes the class opening at the start of `pattern`, skipping escaped characters. */
static bool class_end(MsChars pattern, size_t *end) {
  bool escaped = false;
  for (size_t i = 1; i < pattern.len; i++) {
    if (escaped) {
      escaped = false;
    } else if (pattern.ptr[i] == '\\') {
      escaped = true;
    } else if (pattern.ptr[i] == ']') {
      *end = i;
      return true;
    }
  }
  return false;
}

/* Parses the class at the start of `pattern`; `*length` is the characters it covers. */
static MsPathResult parse_class(MsChars pattern, MsSeq *seq, size_t *length) {
  size_t end = 0;
  if (!class_end(pattern, &end)) {
    return PATH_INVALID;
  }
  MsAtom *atom = seq_push(seq, ATOM_CLASS);
  if (atom == NULL) {
    return PATH_NO_MEMORY;
  }
  size_t members = 1;
  if (pattern.len > 1 && (pattern.ptr[1] == '^' || pattern.ptr[1] == '!')) {
    atom->negated = true;
    members = 2;
  }
  *length = end + 1;
  MsChars token = {.ptr = pattern.ptr, .len = end + 1};
  return parse_class_members(chars_from(token, members), atom);
}


static bool is_group_start(MsChars pattern, size_t at) {
  uint32_t c = pattern.ptr[at];
  bool kind = c == '@' || c == '+' || c == '?' || c == '!' || c == '*';
  return kind && at + 1 < pattern.len && pattern.ptr[at + 1] == '(';
}

/* Index of the `)` matching the group whose text starts at `start`. */
static bool group_end(MsChars pattern, size_t start, size_t *end) {
  size_t depth = 1;
  for (size_t i = start; i < pattern.len; i++) {
    if (pattern.ptr[i] == '(') {
      depth++;
    } else if (pattern.ptr[i] == ')' && --depth == 0) {
      *end = i;
      return true;
    }
  }
  return false;
}

/* The next `|` separated alternative of a group's text from `*cursor`; false after the last. */
static bool next_alternative(MsChars inside, size_t *cursor, MsChars *alternative) {
  if (*cursor > inside.len) {
    return false;
  }
  int64_t nested = 0;
  size_t i = *cursor;
  for (; i < inside.len; i++) {
    if (inside.ptr[i] == '(') {
      nested++;
    } else if (inside.ptr[i] == ')') {
      nested--;
    } else if (inside.ptr[i] == '|' && nested == 0) {
      break;
    }
  }
  *alternative = (MsChars){.ptr = inside.ptr + *cursor, .len = i - *cursor};
  *cursor = i + 1;
  return true;
}

/* Parses the group at the start of `pattern`; `*length` is the characters it covers. */
static MsPathResult parse_group(MsChars pattern, size_t depth, MsSeq *seq, size_t *length) {
  size_t end = 0;
  if (depth >= MAX_NESTING || !group_end(pattern, 2, &end)) {
    return PATH_INVALID;
  }
  MsChars inside = {.ptr = pattern.ptr + 2, .len = end - 2};
  size_t count = 0;
  size_t cursor = 0;
  MsChars alternative = {0};
  while (next_alternative(inside, &cursor, &alternative)) {
    count++;
  }
  MsAtom *atom = seq_push(seq, ATOM_GROUP);
  if (atom == NULL) {
    return PATH_NO_MEMORY;
  }
  atom->group_kind = pattern.ptr[0];
  atom->alternatives = path_array_new(count, sizeof(MsSeq));
  if (atom->alternatives == NULL) {
    return PATH_NO_MEMORY;
  }
  atom->alternative_count = count;
  cursor = 0;
  for (size_t i = 0; next_alternative(inside, &cursor, &alternative); i++) {
    MsPathResult result = path_parse_sequence(alternative, depth + 1, &atom->alternatives[i]);
    if (result != PATH_OK) {
      return result;
    }
  }
  *length = end + 1;
  return PATH_OK;
}

/* Parses one atom at the start of `pattern` into `seq`; `*length` is the characters it covers. */
static MsPathResult parse_atom(MsChars pattern, size_t depth, MsSeq *seq, size_t *length) {
  uint32_t c = pattern.ptr[0];
  *length = 1;
  if (is_group_start(pattern, 0)) {
    return parse_group(pattern, depth, seq, length);
  }
  if (c == '[') {
    return parse_class(pattern, seq, length);
  }
  MsAtom *atom = NULL;
  if (c == '*') {
    atom = seq_push(seq, ATOM_STAR);
  } else if (c == '?') {
    atom = seq_push(seq, ATOM_ANY);
  } else if (c == '\\') {
    if (pattern.len < 2) {
      return PATH_INVALID;
    }
    atom = seq_push(seq, ATOM_LITERAL);
    if (atom != NULL) {
      atom->literal = pattern.ptr[1];
    }
    *length = 2;
  } else {
    atom = seq_push(seq, ATOM_LITERAL);
    if (atom != NULL) {
      atom->literal = c;
    }
  }
  return atom == NULL ? PATH_NO_MEMORY : PATH_OK;
}

/* Parses `pattern` into `seq`, which the caller frees whatever the result. */
MsPathResult path_parse_sequence(MsChars pattern, size_t depth, MsSeq *seq) {
  size_t at = 0;
  while (at < pattern.len) {
    size_t length = 0;
    MsPathResult result = parse_atom(chars_from(pattern, at), depth, seq, &length);
    if (result != PATH_OK) {
      return result;
    }
    at += length;
  }
  return PATH_OK;
}

