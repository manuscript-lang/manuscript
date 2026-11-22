/* Owns reading the assembly and placing labels (see asm_scan.h). */
#include "compiler/link/asm_scan.h"

const char *asm_local_prefix(AsmFormat format) {
  return format == ASM_MACHO ? "L" : ".L";
}

void asm_scan_init(AsmScan *scan, MsArena *arena, AsmFormat format, const MirModule *module,
                   const EmitTableInfo *info) {
  *scan = (AsmScan){.format = format, .module = module, .info = info, .arena = arena, .current = UINT32_MAX};
  scan->out = ms_strbuild_new();
  scan->next_label = 1;
  ms_names_init(&scan->symbols);
  uint32_t count = (uint32_t)module->funcs.len;
  scan->funcs = MS_ARENA_NEW_ARRAY(arena, AsmFunc, count);
  for (uint32_t index = 0; index < count; index++) {
    (void)ms_names_intern(&scan->symbols, ms_names_span(&module->names, module->funcs.ptr[index].name));
  }
  scan->by_symbol = MS_ARENA_NEW_ARRAY(arena, uint32_t, ms_names_count(&scan->symbols));
  for (uint32_t index = 0; index < count; index++) {
    MsName name = ms_names_intern(&scan->symbols, ms_names_span(&module->names, module->funcs.ptr[index].name));
    scan->by_symbol[name] = index + 1;
  }
}

void asm_scan_free(AsmScan *scan) {
  ms_names_free(&scan->symbols);
  asm_range_list_free(&scan->ranges);
  asm_order_list_free(&scan->order);
  ms_strbuild_free(&scan->out);
}

/* The symbol a label line at column 0 defines, without quotes or the Mach-O underscore; empty for a line that
 * is not a label. `exact` gets the text as written. */
static MsSpan label_symbol(const AsmScan *scan, MsSpan line, MsSpan *exact) {
  size_t end = 0;
  bool quoted = false;
  while (end < line.len && (quoted || line.ptr[end] != ':')) {
    quoted = line.ptr[end] == '"' ? !quoted : quoted;
    end++;
  }
  if (end >= line.len || end == 0) {
    return ms_span_of(NULL, 0);
  }
  *exact = ms_span_of(line.ptr, end);
  MsSpan symbol = *exact;
  if (symbol.len >= 2 && symbol.ptr[0] == '"') {
    symbol = ms_span_of(symbol.ptr + 1, symbol.len - 2);
  }
  if (scan->format == ASM_MACHO && symbol.len > 0 && symbol.ptr[0] == '_') {
    symbol = ms_span_of(symbol.ptr + 1, symbol.len - 1);
  }
  return symbol;
}

static void start_function(AsmScan *scan, uint32_t index, MsSpan exact) {
  AsmFunc *func = &scan->funcs[index];
  if (func->found) {
    return;
  }
  func->found = true;
  func->label = ms_arena_copy(scan->arena, exact);
  func->first = (uint32_t)scan->ranges.len;
  scan->current = index;
  asm_order_list_push(&scan->order, index);
  /* The start of the function is a range of its own until a `.loc` says otherwise. */
  uint32_t label = scan->next_label++;
  asm_range_list_push(&scan->ranges, (MirCodeRange){label, MIR_NONE, scan->module->funcs.ptr[index].loc.line, 0});
  func->count = 1;
  func->fresh = true;
  ms_strbuild_printf(&scan->out, "%sms_loc_%u:\n", asm_local_prefix(scan->format), label);
}

static void end_function(AsmScan *scan) {
  AsmFunc *func = &scan->funcs[scan->current];
  if (!func->ended) {
    func->ended = true;
    ms_strbuild_printf(&scan->out, "%sms_end_%u:\n", asm_local_prefix(scan->format), scan->current);
  }
  scan->current = UINT32_MAX;
}

static bool parse_number(MsSpan line, size_t *at, uint32_t *out) {
  while (*at < line.len && (line.ptr[*at] == ' ' || line.ptr[*at] == '\t')) {
    (*at)++;
  }
  if (*at >= line.len || line.ptr[*at] < '0' || line.ptr[*at] > '9') {
    return false;
  }
  uint64_t value = 0;
  while (*at < line.len && line.ptr[*at] >= '0' && line.ptr[*at] <= '9') {
    value = value * 10 + (uint64_t)(line.ptr[*at] - '0');
    (*at)++;
  }
  *out = value > UINT32_MAX ? UINT32_MAX : (uint32_t)value;
  return true;
}

/* A `.loc file line column ...` (COFF: `.cv_loc function file line column`). */
static void place_loc(AsmScan *scan, MsSpan line, size_t at) {
  uint32_t numbers[4];
  uint32_t want = scan->format == ASM_COFF ? 4 : 3;
  for (uint32_t index = 0; index < want; index++) {
    if (!parse_number(line, &at, &numbers[index])) {
      return;
    }
  }
  uint32_t source_line = numbers[want - 2];
  uint32_t column = numbers[want - 1];
  AsmFunc *func = &scan->funcs[scan->current];
  uint32_t funcs = (uint32_t)scan->module->funcs.len;
  /* The column is a scope number; the function's own body is scope 0 of the tables. */
  uint32_t body = scan->info->nscopes - funcs + scan->current + 1;
  uint32_t scope = column == body ? 0 : column;
  MirCodeRange *last = &scan->ranges.ptr[func->first + func->count - 1];
  if (last->line == source_line && last->scope == scope) {
    return;
  }
  if (func->fresh) {
    last->line = source_line;
    last->scope = scope;
    return;
  }
  uint32_t label = scan->next_label++;
  asm_range_list_push(&scan->ranges, (MirCodeRange){label, MIR_NONE, source_line, scope});
  func->count++;
  func->fresh = true;
  ms_strbuild_printf(&scan->out, "%sms_loc_%u:\n", asm_local_prefix(scan->format), label);
}

static bool starts(MsSpan line, const char *text) {
  return ms_span_starts_with(line, ms_span_of_text(text));
}

/* Whether `line` (after its tab) names directive `name` followed by blank or the end. */
static bool is_directive(MsSpan line, const char *name) {
  MsSpan text = ms_span_of_text(name);
  if (!ms_span_starts_with(line, text)) {
    return false;
  }
  return line.len == text.len || line.ptr[text.len] == ' ' || line.ptr[text.len] == '\t';
}

/* One indented line: a directive or an instruction. True when the line is dropped. */
static bool indented(AsmScan *scan, MsSpan line) {
  MsSpan text = ms_span_of(line.ptr + 1, line.len - 1);
  if (scan->format == ASM_COFF && (starts(text, ".def\t@feat.00") || is_directive(text, ".set\t@feat.00,"))) {
    scan->skipping = starts(text, ".def");
    return true;
  }
  if (scan->skipping) {
    scan->skipping = !is_directive(text, ".endef");
    return true;
  }
  if (scan->current == UINT32_MAX) {
    return false;
  }
  if (is_directive(text, scan->format == ASM_COFF ? ".cv_loc" : ".loc")) {
    place_loc(scan, text, scan->format == ASM_COFF ? 7 : 4);
    return true;
  }
  if (is_directive(text, ".size") || is_directive(text, ".cfi_endproc") || is_directive(text, ".seh_endproc")) {
    end_function(scan);
    return false;
  }
  uint8_t first = text.len > 0 ? text.ptr[0] : '.';
  if (first != '.' && first != '#' && first != '/' && first != ';' && first != '@') {
    scan->funcs[scan->current].fresh = false;
  }
  return false;
}

static void scan_line(AsmScan *scan, MsSpan line) {
  bool drop = false;
  /* A COFF function that needs no unwind info has no `.seh_endproc`: the `.Lfunc_end` label closes it. */
  if (scan->format == ASM_COFF && scan->current != UINT32_MAX && starts(line, ".Lfunc_end") &&
      line.ptr[line.len - 1] == ':') {
    ms_strbuild_append(&scan->out, line);
    ms_strbuild_append_byte(&scan->out, '\n');
    end_function(scan);
    return;
  }
  if (line.len > 0 && line.ptr[0] == '\t') {
    drop = indented(scan, line);
  } else if (line.len > 0 && line.ptr[0] != '.' && line.ptr[0] != '#' && line.ptr[0] != ' ') {
    MsSpan exact = ms_span_of(NULL, 0);
    MsSpan symbol = label_symbol(scan, line, &exact);
    MsName name = MS_NAME_EMPTY;
    if (symbol.len > 0 && ms_names_find(&scan->symbols, symbol, &name) && scan->by_symbol[name] != 0) {
      ms_strbuild_append(&scan->out, line);
      ms_strbuild_append_byte(&scan->out, '\n');
      start_function(scan, scan->by_symbol[name] - 1, exact);
      return;
    }
  }
  if (!drop) {
    ms_strbuild_append(&scan->out, line);
    ms_strbuild_append_byte(&scan->out, '\n');
  }
}

bool asm_scan(AsmScan *scan, MsSpan text, MsStrBuild *why) {
  size_t start = 0;
  while (start < text.len) {
    size_t end = start;
    while (end < text.len && text.ptr[end] != '\n') {
      end++;
    }
    scan_line(scan, ms_span_of(text.ptr + start, end - start));
    start = end + 1;
  }
  for (uint32_t index = 0; index < scan->order.len; index++) {
    uint32_t func = scan->order.ptr[index];
    if (!scan->funcs[func].ended) {
      ms_strbuild_append_text(why, "the assembly of a function has no end: ");
      ms_strbuild_append(why, scan->funcs[func].label);
      return false;
    }
  }
  return true;
}
