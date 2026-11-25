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

#include "base/alloc.h"
#include "base/hash.h"

/* A line `  %name = <operation> <type> <first>, <second>` that equals `<first>`; text offsets in the body. */
typedef enum Kind {
  KIND_COPY,    /* equals `value`, always */
  KIND_ADDRESS, /* `ptrtoint ptr %value to i64`: kept, but an `inttoptr` of it is `value` */
  KIND_CAST,    /* `inttoptr i64 %value to ptr`: equals the address `value` was made from, when it was made */
  KIND_PHI,     /* a `phi`: equals its one incoming value, when there is only one */
  KIND_OFFSET   /* `add i64 %value, <second>`: an address plus a constant, when `value` is an address */
} Kind;

typedef struct Copy {
  size_t name, name_len;
  size_t value, value_len; /* what it equals: a register name (no `%`) or a constant */
  size_t line;             /* the offset of the line of a cast or phi */
  Kind kind;
  bool constant;
  bool resolved; /* a cast or phi that is forwarded: its line is dropped */
  size_t second, second_len; /* an offset's other operand: a register name (`second_reg`) or a number */
  bool second_reg;
  bool gep; /* a cast of an address plus constants: written as `getelementptr i8, ptr %gep_base, i64 gep_offset` */
  size_t gep_base, gep_base_len;
  int64_t gep_offset;
} Copy;

typedef struct Table {
  Copy *copies;
  size_t len;
  uint32_t *index; /* open addressing over `copies`, by name; UINT32_MAX empty */
  size_t mask;
} Table;

typedef struct Line {
  const uint8_t *text;
  size_t at, end;
  size_t full; /* the end including a `, !dbg !N` suffix that debug info adds to an instruction */
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

static MsSpan view(const uint8_t *text, size_t at, size_t length) { return ms_span_of(text + at, length); }

static bool has(const Line *line, size_t at, const char *prefix) {
  return at <= line->end && ms_span_starts_with_text(view(line->text, at, line->end - at), prefix);
}

static bool same_text(const uint8_t *text, size_t a, size_t a_len, size_t b, size_t b_len) {
  return ms_span_equal(view(text, a, a_len), view(text, b, b_len));
}

/* Whether the line continues at `at` with `, <second>` and then its end or a comma. */
static bool second_is(const Line *line, size_t at, const char *second) {
  const size_t end = at + 2 + ms_span_of_text(second).len;
  return has(line, at, ", ") && has(line, at + 2, second) && (end == line->end || line->text[end] == ',');
}

static bool same_text_literal(const Line *line, const Copy *copy, const char *literal) {
  return ms_span_equal(view(line->text, copy->value, copy->value_len), ms_span_of_text(literal));
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
  static const char *const or_heads[] = {" = or i64 ", " = or i32 ", " = or i16 ", " = or i8 "};
  static const char *const add_heads[] = {" = add i64 ", " = add i32 ", " = add i16 ", " = add i8 "};
  for (size_t type = 0; type < 4; type++) {
    for (int operation = 0; operation < 2; operation++) { /* `or` copies a register, `add` writes a constant */
      const char *head = operation == 0 ? or_heads[type] : add_heads[type];
      if (!has(line, at, head)) {
        continue;
      }
      const size_t stop = read_first(line, at + ms_span_of_text(head).len, copy);
      if (operation == 1 && copy->constant && copy->value_len == 1 && line->text[copy->value] == '0' &&
          has(line, stop, ", ")) {
        /* `add i64 0, 8` writes the constant 8 as well (an offset the emitter added to an address). */
        size_t end = stop + 2;
        while (end < line->end && (is_name_byte(line->text[end]) || line->text[end] == '-')) {
          end++;
        }
        if (end == line->end && is_integer(line->text, stop + 2, end - stop - 2)) {
          copy->value = stop + 2;
          copy->value_len = end - stop - 2;
          return true;
        }
      }
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
    if (!same_text_literal(line, copy, "false")) {
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
    const bool zero = same_text_literal(line, copy, "0.0");
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
  if (copy->name_len != 0 && has(line, at, " = add i64 %")) {
    copy->kind = KIND_OFFSET;
    copy->value = at + 12;
    copy->value_len = name_end(line->text, copy->value, line->end) - copy->value;
    size_t stop = copy->value + copy->value_len;
    if (copy->value_len == 0 || !has(line, stop, ", ")) {
      return false;
    }
    stop += 2;
    copy->second_reg = stop < line->end && line->text[stop] == '%';
    copy->second = copy->second_reg ? stop + 1 : stop;
    size_t end = copy->second;
    while (end < line->end && (is_name_byte(line->text[end]) || line->text[end] == '-')) {
      end++;
    }
    copy->second_len = end - copy->second;
    return copy->second_len != 0 && end == line->end;
  }
  return false;
}

static size_t line_end(const uint8_t *text, size_t at, size_t limit) {
  const uint8_t *newline = __builtin_memchr(text + at, '\n', limit - at);
  return newline == NULL ? limit : (size_t)(newline - text);
}

/* The line at `at`: `end` is before a trailing `, !dbg !<digits>`, so a line with debug info reads as one without. */
static Line line_at(const uint8_t *text, size_t at, size_t limit) {
  Line line = {text, at, line_end(text, at, limit), 0};
  line.full = line.end;
  size_t digits = line.end;
  while (digits > at && text[digits - 1] >= '0' && text[digits - 1] <= '9') {
    digits--;
  }
  static const char suffix[] = ", !dbg !";
  const size_t size = sizeof suffix - 1;
  if (digits < line.end && digits >= at + size && __builtin_memcmp(text + digits - size, suffix, size) == 0) {
    line.end = digits - size;
  }
  return line;
}

static void append_tail(MsStrBuild *out, const Line *line) {
  ms_strbuild_append(out, ms_span_of(line->text + line->end, line->full - line->end));
}

/* Whether the line is `  %name = <operation> ...` for an operation that starts with one of `o a f p i` (or, add, fadd,
 * ptrtoint, phi, inttoptr): every line the pass reads or forwards does, and most lines (calls, loads, stores, compares)
 * do not, so they are told apart by one byte. */
static bool may_define(const Line *line) {
  if (!has(line, line->at, "  %")) {
    return false;
  }
  const size_t at = name_end(line->text, line->at + 3, line->end);
  if (!has(line, at, " = ") || at + 3 >= line->end) {
    return false;
  }
  const uint8_t operation = line->text[at + 3];
  return operation == 'o' || operation == 'a' || operation == 'f' || operation == 'p' || operation == 'i';
}

static size_t slot_of(const Table *table, const uint8_t *text, size_t at, size_t length) {
  return ms_hash_span(ms_span_of(text + at, length)) & table->mask;
}

static void insert(Table *table, const uint8_t *text, const Copy *copy) {
  size_t slot = slot_of(table, text, copy->name, copy->name_len);
  while (table->index[slot] != UINT32_MAX) {
    slot = (slot + 1) & table->mask;
  }
  table->copies[table->len] = *copy;
  table->index[slot] = (uint32_t)table->len++;
}

/* The entry defining the register `at..at+length`, or NULL when there is none. */
static Copy *find_entry(const Table *table, const uint8_t *text, size_t at, size_t length) {
  size_t slot = slot_of(table, text, at, length);
  while (table->index[slot] != UINT32_MAX) {
    Copy *copy = &table->copies[table->index[slot]];
    if (copy->name_len == length && same_text(text, copy->name, length, at, length)) {
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
  return a->constant == b->constant && same_text(text, a->value, a->value_len, b->value, b->value_len);
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
                         same_text(text, operand.value, operand.value_len, self->name, self->name_len);
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

static bool parse_offset(const uint8_t *text, size_t at, size_t length, int64_t *out) {
  if (!is_integer(text, at, length)) {
    return false;
  }
  int64_t value = 0;
  const bool negative = text[at] == '-';
  for (size_t index = negative ? 1 : 0; index < length; index++) {
    if (value > INT64_MAX / 10 - 1) {
      return false;
    }
    value = value * 10 + (text[at + index] - '0');
  }
  *out = negative ? -value : value;
  return true;
}

/* Follows `add` lines of constants down to the address of a slot: the register the address was made from and the
 * bytes added. */
static bool address_plus(const Table *table, const uint8_t *text, Copy *cast) {
  Copy at = resolve(table, text, cast->value, cast->value_len);
  int64_t total = 0;
  for (int hops = 0; hops < 16 && !at.constant; hops++) {
    const Copy *entry = find_entry(table, text, at.value, at.value_len);
    if (entry == NULL) {
      return false;
    }
    if (entry->kind == KIND_ADDRESS) {
      cast->gep_base = entry->value;
      cast->gep_base_len = entry->value_len;
      cast->gep_offset = total;
      return true;
    }
    if (entry->kind != KIND_OFFSET) {
      return false;
    }
    int64_t step = 0;
    if (entry->second_reg) {
      const Copy second = resolve(table, text, entry->second, entry->second_len);
      if (!second.constant || !parse_offset(text, second.value, second.value_len, &step)) {
        return false;
      }
    } else if (!parse_offset(text, entry->second, entry->second_len, &step)) {
      return false;
    }
    total += step;
    at = resolve(table, text, entry->value, entry->value_len);
  }
  return false;
}

/* One round over the casts and phis: true when one more was forwarded. */
static bool forward_round(Table *table, const uint8_t *text, size_t size) {
  bool changed = false;
  for (size_t entry = 0; entry < table->len; entry++) {
    Copy *copy = &table->copies[entry];
    if (copy->resolved || copy->kind == KIND_COPY || copy->kind == KIND_ADDRESS || copy->kind == KIND_OFFSET) {
      continue;
    }
    if (copy->kind == KIND_CAST) {
      const Copy source = resolve(table, text, copy->value, copy->value_len);
      const Copy *address = source.constant ? NULL : find_entry(table, text, source.value, source.value_len);
      if (address != NULL && address->kind == KIND_ADDRESS) {
        copy->value = address->value;
        copy->value_len = address->value_len;
        copy->resolved = changed = true;
      } else if (!copy->gep && address_plus(table, text, copy)) {
        copy->gep = true; /* the line stays, written as an address of the slot so LLVM sees what it points into */
      }
      continue;
    }
    const Line line = line_at(text, copy->line, size);
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
      const size_t start = pos;
      while (pos < line->end && line->text[pos] != '%') {
        pos++;
      }
      ms_strbuild_append(out, ms_span_of(line->text + start, pos - start));
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
  append_tail(out, line);
  ms_strbuild_append_byte(out, '\n');
}

/* Whether the line is one that was forwarded. */
static bool is_forwarded(const Table *table, const Line *line) {
  if (!may_define(line)) {
    return false;
  }
  const size_t name = line->at + 3;
  const size_t length = name_end(line->text, name, line->end) - name;
  const Copy *copy = find_entry(table, line->text, name, length);
  return copy != NULL && copy->line == line->at && copy->kind != KIND_ADDRESS && copy->resolved;
}

/* The cast this line writes, when it is one made into an address of a slot plus constants. */
static const Copy *written_as_address(const Table *table, const Line *line) {
  if (!may_define(line)) {
    return NULL;
  }
  const size_t name = line->at + 3;
  const size_t length = name_end(line->text, name, line->end) - name;
  const Copy *copy = find_entry(table, line->text, name, length);
  return copy != NULL && copy->line == line->at && copy->kind == KIND_CAST && copy->gep ? copy : NULL;
}

static void write_address(MsStrBuild *out, const Table *table, const uint8_t *text, const Copy *cast, const Line *line) {
  const Copy base = resolve(table, text, cast->gep_base, cast->gep_base_len);
  ms_strbuild_printf(out, "  %%%.*s = getelementptr i8, ptr %%%.*s, i64 %lld", (int)cast->name_len, text + cast->name,
                     (int)base.value_len, text + base.value, (long long)cast->gep_offset);
  append_tail(out, line);
  ms_strbuild_append_byte(out, '\n');
}

void emit_forward_copies(MsStrBuild *body) {
  const MsSpan span = ms_strbuild_span(body);
  const uint8_t *text = span.ptr;
  size_t lines = 1;
  for (const uint8_t *newline = __builtin_memchr(text, '\n', span.len); newline != NULL;
       newline = __builtin_memchr(newline + 1, '\n', span.len - (size_t)(newline + 1 - text))) {
    lines++;
  }
  Table table = {.copies = ms_alloc(lines * sizeof(Copy)), .mask = 1};
  while (table.mask < lines * 2) {
    table.mask <<= 1;
  }
  table.index = ms_alloc(table.mask * sizeof(uint32_t));
  __builtin_memset(table.index, 0xff, table.mask * sizeof(uint32_t));
  table.mask -= 1;
  for (size_t at = 0; at < span.len;) {
    const Line line = line_at(text, at, span.len);
    Copy copy = {0};
    if (may_define(&line) && (parse_copy(&line, &copy) || parse_other(&line, &copy))) {
      insert(&table, text, &copy);
    }
    at = line.full + 1;
  }
  for (int round = 0; round < 16 && forward_round(&table, text, span.len); round++) {
  }
  MsStrBuild out = ms_strbuild_new();
  for (size_t at = 0; at < span.len;) {
    const Line line = line_at(text, at, span.len);
    if (!is_forwarded(&table, &line)) {
      const Copy *cast = written_as_address(&table, &line);
      if (cast != NULL) {
        write_address(&out, &table, text, cast, &line);
      } else {
        copy_line(&out, &table, &line);
      }
    }
    at = line.full + 1;
  }
  ms_strbuild_free(body);
  *body = out;
  ms_free(table.copies);
  ms_free(table.index);
}
