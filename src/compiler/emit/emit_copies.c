/* compiler/emit/emit_copies.c: forwards the identity copies, constants, address round trips and trivial phis the
 * emitter writes as instructions.
 *
 * Reading a field, a leaf or a whole value into a new MIR value is written `%d = or i64 %s, 0` (`or i1 %s, false`
 * for a bool, `fadd double %s, -0.0` for a double) and a constant `%d = add i64 5, 0` (`or i1 false, true`,
 * `fadd double 0.0, 0.0`). The fast register allocator of `llc -O0` gives every value that lives across a block
 * its own stack slot, so each such value cost a frame slot (over a third of the slots of the larger functions of
 * the TOML parser). Such a line defines nothing new: its users name the source register or write the constant,
 * and the line is dropped. So are `inttoptr` of a `ptrtoint` (the address of a slot, held as an integer) and a
 * `phi` whose incoming values are all one value (a block parameter every edge passes the same value to). Static
 * single assignment makes that safe wherever the line dominated its users. */
#include "compiler/emit/emit_func.h"

#include <string.h>

#include "base/alloc.h"
#include "base/hash.h"

/* A line `  %name = <operation> <type> <first>, <second>` that equals `<first>`; text offsets in the body. */
typedef enum Kind {
  KIND_COPY,    /* equals `value`, always */
  KIND_ADDRESS, /* `ptrtoint ptr %value to i64`: kept, but an `inttoptr` of it is `value` */
  KIND_CAST,    /* `inttoptr i64 %value to ptr`: equals the address `value` was made from, when it was made */
  KIND_PHI      /* a `phi`: equals its one incoming value, when there is only one */
} Kind;

typedef struct Copy {
  size_t name, name_len;
  size_t value, value_len; /* what it equals: a register name (no `%`) or a constant */
  size_t line;             /* the offset of the line of a cast or phi */
  Kind kind;
  bool constant;
  bool resolved; /* a cast or phi that is forwarded: its line is dropped */
} Copy;

typedef struct Table {
  Copy *copies;
  size_t len;
  size_t *index; /* open addressing over `copies`, by name; SIZE_MAX empty */
  size_t mask;
} Table;

typedef struct Line {
  const uint8_t *text;
  size_t at, end;
} Line;

static bool is_name_byte(uint8_t byte) {
  return (byte >= 'a' && byte <= 'z') || (byte >= 'A' && byte <= 'Z') || (byte >= '0' && byte <= '9') ||
         byte == '_' || byte == '.';
}

static size_t name_end(const uint8_t *text, size_t at, size_t limit) {
  while (at < limit && is_name_byte(text[at])) {
    at++;
  }
  return at;
}

static bool has(const Line *line, size_t at, const char *prefix) {
  const size_t length = strlen(prefix);
  return at + length <= line->end && memcmp(line->text + at, prefix, length) == 0;
}

/* Whether the line continues at `at` with `, <second>` and then its end or a comma. */
static bool second_is(const Line *line, size_t at, const char *second) {
  const size_t end = at + 2 + strlen(second);
  return has(line, at, ", ") && has(line, at + 2, second) && (end == line->end || line->text[end] == ',');
}

static bool is_integer(const uint8_t *text, size_t at, size_t length) {
  size_t digits = 0;
  for (size_t index = 0; index < length; index++) {
    const bool digit = text[at + index] >= '0' && text[at + index] <= '9';
    if (!digit && !(index == 0 && text[at + index] == '-')) {
      return false;
    }
    digits += digit ? 1 : 0;
  }
  return digits != 0;
}

/* The operand after `<operation> <type> ` at `at`: its end, as a register or constant of `copy`. */
static size_t read_first(const Line *line, size_t at, Copy *copy) {
  copy->constant = line->text[at] != '%';
  copy->value = copy->constant ? at : at + 1;
  size_t stop = copy->constant ? at : at + 1;
  while (stop < line->end && (is_name_byte(line->text[stop]) || line->text[stop] == '-')) {
    stop++;
  }
  copy->value_len = stop - copy->value;
  return stop;
}

/* The copy or constant the line writes; false for any other line. */
static bool parse_copy(const Line *line, Copy *copy) {
  if (!has(line, line->at, "  %")) {
    return false;
  }
  copy->name = line->at + 3;
  copy->name_len = name_end(line->text, copy->name, line->end) - copy->name;
  copy->kind = KIND_COPY;
  copy->resolved = true;
  copy->line = line->at;
  size_t at = copy->name + copy->name_len;
  static const char *const integer_types[] = {"i64", "i32", "i16", "i8"};
  for (size_t type = 0; type < 4; type++) {
    char head[24];
    const size_t length = strlen(integer_types[type]);
    for (int operation = 0; operation < 2; operation++) { /* `or` copies a register, `add` writes a constant */
      memcpy(head, operation == 0 ? " = or " : " = add ", operation == 0 ? 6 : 7);
      const size_t used = operation == 0 ? 6 : 7;
      memcpy(head + used, integer_types[type], length);
      memcpy(head + used + length, " ", 2);
      if (!has(line, at, head)) {
        continue;
      }
      const size_t first = at + used + length + 1;
      const size_t stop = read_first(line, first, copy);
      if (copy->value_len == 0 || !second_is(line, stop, "0")) {
        return false;
      }
      return operation == 0 ? !copy->constant : (copy->constant && is_integer(line->text, copy->value, copy->value_len));
    }
  }
  if (has(line, at, " = or i1 ")) {
    const size_t stop = read_first(line, at + 9, copy);
    if (copy->value_len == 0) {
      return false;
    }
    if (!copy->constant) {
      return second_is(line, stop, "false");
    }
    /* `or i1 false, true` is `true`. */
    if (copy->value_len != 5 || memcmp(line->text + copy->value, "false", 5) != 0) {
      return false;
    }
    const bool one = second_is(line, stop, "true");
    copy->value = stop + 2;
    copy->value_len = one ? 4 : 5;
    return one || second_is(line, stop, "false");
  }
  if (has(line, at, " = fadd double ")) {
    const size_t stop = read_first(line, at + 15, copy);
    if (copy->value_len == 0) {
      return false;
    }
    if (!copy->constant) {
      return second_is(line, stop, "-0.0");
    }
    const bool zero = copy->value_len == 3 && memcmp(line->text + copy->value, "0.0", 3) == 0;
    return zero ? second_is(line, stop, "0.0") : (line->text[copy->value] != '-' && second_is(line, stop, "-0.0"));
  }
  return false;
}

/* `  %d = ptrtoint ptr %s to i64`, `  %d = inttoptr i64 %v to ptr` or a phi line: the entry it makes, or false. */
static bool parse_other(const Line *line, Copy *copy) {
  if (!has(line, line->at, "  %")) {
    return false;
  }
  copy->name = line->at + 3;
  copy->name_len = name_end(line->text, copy->name, line->end) - copy->name;
  const size_t at = copy->name + copy->name_len;
  copy->line = line->at;
  copy->resolved = false;
  copy->constant = false;
  if (copy->name_len != 0 && has(line, at, " = ptrtoint ptr %")) {
    copy->kind = KIND_ADDRESS;
    copy->value = at + 17;
    copy->value_len = name_end(line->text, copy->value, line->end) - copy->value;
    return copy->value_len != 0 && has(line, copy->value + copy->value_len, " to i64");
  }
  if (copy->name_len != 0 && has(line, at, " = inttoptr i64 %")) {
    copy->kind = KIND_CAST;
    copy->value = at + 17;
    copy->value_len = name_end(line->text, copy->value, line->end) - copy->value;
    return copy->value_len != 0 && has(line, copy->value + copy->value_len, " to ptr");
  }
  if (copy->name_len != 0 && has(line, at, " = phi ")) {
    copy->kind = KIND_PHI;
    return true;
  }
  return false;
}

static size_t line_end(const uint8_t *text, size_t at, size_t limit) {
  while (at < limit && text[at] != '\n') {
    at++;
  }
  return at;
}

static size_t slot_of(const Table *table, const uint8_t *text, size_t at, size_t length) {
  return ms_hash_span(ms_span_of(text + at, length)) & table->mask;
}

static void insert(Table *table, const uint8_t *text, const Copy *copy) {
  size_t slot = slot_of(table, text, copy->name, copy->name_len);
  while (table->index[slot] != SIZE_MAX) {
    slot = (slot + 1) & table->mask;
  }
  table->copies[table->len] = *copy;
  table->index[slot] = table->len++;
}

/* The entry defining the register `at..at+length`, or NULL when there is none. */
static Copy *find_entry(const Table *table, const uint8_t *text, size_t at, size_t length) {
  size_t slot = slot_of(table, text, at, length);
  while (table->index[slot] != SIZE_MAX) {
    Copy *copy = &table->copies[table->index[slot]];
    if (copy->name_len == length && memcmp(text + copy->name, text + at, length) == 0) {
      return copy;
    }
    slot = (slot + 1) & table->mask;
  }
  return NULL;
}

/* What a use of the register `at..at+length` names after its chain of forwarded lines: a register or a
 * constant. */
static Copy resolve(const Table *table, const uint8_t *text, size_t at, size_t length) {
  Copy result = {.value = at, .value_len = length, .constant = false};
  for (size_t hops = 0; hops <= table->len && !result.constant; hops++) {
    const Copy *copy = find_entry(table, text, result.value, result.value_len);
    if (copy == NULL || copy->kind == KIND_ADDRESS || !copy->resolved) {
      break;
    }
    result.value = copy->value;
    result.value_len = copy->value_len;
    result.constant = copy->constant;
  }
  return result;
}

static bool same_operand(const uint8_t *text, const Copy *a, const Copy *b) {
  return a->constant == b->constant && a->value_len == b->value_len &&
         memcmp(text + a->value, text + b->value, a->value_len) == 0;
}

/* Reads the operands of a phi line and sets `copy->value` to the one value they all resolve to, ignoring the
 * phi itself; false when they differ or there is none. */
static bool single_incoming(const Table *table, const Line *line, Copy *self) {
  const uint8_t *text = line->text;
  size_t at = self->name + self->name_len;
  while (at < line->end && text[at] != '[') {
    at++;
  }
  Copy only = {0};
  bool found = false;
  while (at < line->end && text[at] == '[') {
    at += 2; /* "[ " */
    Copy operand = {.value = at, .constant = text[at] != '%'};
    size_t stop = at;
    if (!operand.constant) {
      operand.value = ++at;
      stop = name_end(text, at, line->end);
      operand.value_len = stop - at;
      operand = resolve(table, text, operand.value, operand.value_len);
    } else {
      while (stop < line->end && text[stop] != ',') {
        stop++;
      }
      operand.value_len = stop - at;
    }
    const bool is_self = !operand.constant && operand.value_len == self->name_len &&
                         memcmp(text + operand.value, text + self->name, self->name_len) == 0;
    if (!is_self) {
      if (found && !same_operand(text, &only, &operand)) {
        return false;
      }
      only = operand;
      found = true;
    }
    while (stop < line->end && text[stop] != ']') {
      stop++;
    }
    at = stop + 1;
    if (has(line, at, ", [")) {
      at += 2;
    } else {
      break;
    }
  }
  if (!found) {
    return false;
  }
  self->value = only.value;
  self->value_len = only.value_len;
  self->constant = only.constant;
  return true;
}

/* One round over the casts and phis: true when one more was forwarded. */
static bool forward_round(Table *table, const uint8_t *text, size_t size) {
  bool changed = false;
  for (size_t entry = 0; entry < table->len; entry++) {
    Copy *copy = &table->copies[entry];
    if (copy->resolved || copy->kind == KIND_COPY || copy->kind == KIND_ADDRESS) {
      continue;
    }
    if (copy->kind == KIND_CAST) {
      const Copy source = resolve(table, text, copy->value, copy->value_len);
      const Copy *address = source.constant ? NULL : find_entry(table, text, source.value, source.value_len);
      if (address != NULL && address->kind == KIND_ADDRESS) {
        copy->value = address->value;
        copy->value_len = address->value_len;
        copy->resolved = changed = true;
      }
      continue;
    }
    const Line line = {text, copy->line, line_end(text, copy->line, size)};
    Copy single = *copy;
    if (single_incoming(table, &line, &single)) {
      copy->value = single.value;
      copy->value_len = single.value_len;
      copy->constant = single.constant;
      copy->resolved = changed = true;
    }
  }
  return changed;
}

static void copy_line(MsStrBuild *out, const Table *table, const Line *line) {
  for (size_t pos = line->at; pos < line->end;) {
    if (line->text[pos] != '%') {
      ms_strbuild_append_byte(out, line->text[pos++]);
      continue;
    }
    const size_t length = name_end(line->text, pos + 1, line->end) - (pos + 1);
    const Copy target = resolve(table, line->text, pos + 1, length);
    if (!target.constant) {
      ms_strbuild_append_byte(out, '%');
    }
    ms_strbuild_append(out, ms_span_of(line->text + target.value, target.value_len));
    pos += 1 + length;
  }
  ms_strbuild_append_byte(out, '\n');
}

/* Whether the line is one that was forwarded. */
static bool is_forwarded(const Table *table, const Line *line) {
  if (!has(line, line->at, "  %")) {
    return false;
  }
  const size_t name = line->at + 3;
  const size_t length = name_end(line->text, name, line->end) - name;
  const Copy *copy = find_entry(table, line->text, name, length);
  return copy != NULL && copy->line == line->at && copy->kind != KIND_ADDRESS && copy->resolved;
}

void emit_forward_copies(MsStrBuild *body) {
  const MsSpan span = ms_strbuild_span(body);
  const uint8_t *text = span.ptr;
  size_t lines = 1;
  for (size_t at = 0; at < span.len; at++) {
    lines += text[at] == '\n' ? 1 : 0;
  }
  Table table = {.copies = ms_alloc(lines * sizeof(Copy)), .mask = 1};
  while (table.mask < lines * 2) {
    table.mask <<= 1;
  }
  table.index = ms_alloc(table.mask * sizeof(size_t));
  memset(table.index, 0xff, table.mask * sizeof(size_t));
  table.mask -= 1;
  for (size_t at = 0; at < span.len;) {
    const Line line = {text, at, line_end(text, at, span.len)};
    Copy copy;
    if (parse_copy(&line, &copy) || parse_other(&line, &copy)) {
      insert(&table, text, &copy);
    }
    at = line.end + 1;
  }
  for (int round = 0; round < 16 && forward_round(&table, text, span.len); round++) {
  }
  MsStrBuild out = ms_strbuild_new();
  for (size_t at = 0; at < span.len;) {
    const Line line = {text, at, line_end(text, at, span.len)};
    if (!is_forwarded(&table, &line)) {
      copy_line(&out, &table, &line);
    }
    at = line.end + 1;
  }
  ms_strbuild_free(body);
  *body = out;
  ms_free(table.copies);
  ms_free(table.index);
}
