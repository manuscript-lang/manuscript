/* Owns the debug metadata of source places (see emit_debug.h). */
#include "compiler/emit/emit_debug.h"

#include <string.h>

#include "base/alloc.h"

enum { MD_UNIT = 0, MD_FILE = 1, MD_FLAGS = 2, MD_NO_TYPES = 3, MD_TYPE = 4, MD_FIRST = 5 };

void emit_debug_init(EmitDebug *debug) {
  debug->nodes = ms_strbuild_new();
  debug->next = MD_FIRST;
  debug->subprogram = 0;
  debug->cached = 0;
  debug->cached_line = 0;
  debug->cached_column = 0;
  debug->cached_scope = 0;
  debug->file_nodes = NULL;
  debug->block_nodes = NULL;
  debug->nfiles = 0;
  debug->func_file = MIR_NONE;
}

void emit_debug_free(EmitDebug *debug) {
  ms_free(debug->file_nodes);
  ms_free(debug->block_nodes);
  ms_strbuild_free(&debug->nodes);
}

/* Appends `text` as the inside of an LLVM string. */
static void append_quoted(MsStrBuild *out, MsSpan text) {
  for (size_t index = 0; index < text.len; index++) {
    uint8_t byte = text.ptr[index];
    if (byte >= 0x20 && byte < 0x7f && byte != '"' && byte != '\\') {
      ms_strbuild_append_byte(out, byte);
      continue;
    }
    ms_strbuild_append_byte(out, '\\');
    if (byte < 16) {
      ms_strbuild_append_byte(out, '0');
    }
    ms_strbuild_append_u64_radix(out, byte, 16);
  }
}

/* The DIFile node of module file `file`, made on first use. */
static uint32_t file_node(const EmitCx *cx, uint32_t file) {
  EmitDebug *debug = cx->debug;
  if (file >= debug->nfiles) {
    return MD_FILE;
  }
  if (debug->file_nodes[file] == 0) {
    debug->file_nodes[file] = debug->next++;
    ms_strbuild_printf(&debug->nodes, "!%u = !DIFile(filename: \"", debug->file_nodes[file]);
    append_quoted(&debug->nodes, cx->module->files.ptr[file]);
    ms_strbuild_append_text(&debug->nodes, "\", directory: \"\")\n");
  }
  return debug->file_nodes[file];
}

/* The scope that puts a line of module file `file` in the function being written: the subprogram itself for its
 * own file, otherwise a block that names the other file. */
static uint32_t scope_node(const EmitCx *cx, uint32_t file) {
  EmitDebug *debug = cx->debug;
  if (file >= debug->nfiles || file == debug->func_file) {
    return debug->subprogram;
  }
  if (debug->block_nodes[file] == 0) {
    debug->block_nodes[file] = debug->next++;
    ms_strbuild_printf(&debug->nodes, "!%u = !DILexicalBlockFile(scope: !%u, file: !%u, discriminator: 0)\n",
                       debug->block_nodes[file], debug->subprogram, file_node(cx, file));
  }
  return debug->block_nodes[file];
}

uint32_t emit_debug_subprogram(EmitCx *cx, uint32_t index) {
  EmitDebug *debug = cx->debug;
  const MirFunc *func = &cx->module->funcs.ptr[index];
  if (debug->file_nodes == NULL) {
    debug->nfiles = (uint32_t)cx->module->files.len;
    debug->file_nodes = ms_realloc(NULL, (debug->nfiles + 1) * sizeof(uint32_t));
    debug->block_nodes = ms_realloc(NULL, (debug->nfiles + 1) * sizeof(uint32_t));
    memset(debug->file_nodes, 0, (debug->nfiles + 1) * sizeof(uint32_t));
  }
  memset(debug->block_nodes, 0, (debug->nfiles + 1) * sizeof(uint32_t));
  debug->subprogram = debug->next++;
  debug->cached = 0;
  debug->func_file = func->loc.file;
  const uint32_t file = file_node(cx, func->loc.file);
  ms_strbuild_printf(&debug->nodes, "!%u = distinct !DISubprogram(name: \"", debug->subprogram);
  append_quoted(&debug->nodes, ms_names_span(&cx->module->names, func->name));
  ms_strbuild_printf(&debug->nodes,
                     "\", scope: !%u, file: !%u, line: %u, type: !%u, scopeLine: %u, spFlags: DISPFlagDefinition, "
                     "unit: !%u)\n",
                     file, file, func->loc.line, MD_TYPE, func->loc.line, MD_UNIT);
  return debug->subprogram;
}

static uint32_t location_node(EmitDebug *debug, uint32_t line, uint32_t column, uint32_t scope) {
  if (debug->cached != 0 && debug->cached_line == line && debug->cached_column == column &&
      debug->cached_scope == scope) {
    return debug->cached;
  }
  debug->cached = debug->next++;
  debug->cached_line = line;
  debug->cached_column = column;
  debug->cached_scope = scope;
  ms_strbuild_printf(&debug->nodes, "!%u = !DILocation(line: %u, column: %u, scope: !%u)\n", debug->cached, line,
                     column, scope);
  return debug->cached;
}

/* The line of the first instruction of the function that has one of its own (not an inlined callee's), or the
 * function's own line when none does. */
static uint32_t body_line(EmitCx *cx) {
  if (cx->body_line == 0) {
    cx->body_line = UINT32_MAX;
    for (uint32_t block = 0; cx->body_line == UINT32_MAX && block < cx->func->blocks.len; block++) {
      const MirBlockData *data = &cx->func->blocks.ptr[block];
      for (uint32_t index = 0; index < data->insts.len; index++) {
        MirLoc at = data->insts.ptr[index].loc;
        if (!mir_loc_none(at) && at.line != 0 && at.scope == 0) {
          cx->body_line = at.line;
          break;
        }
      }
    }
  }
  return cx->body_line == UINT32_MAX ? cx->func->loc.line : cx->body_line;
}

/* Whether the line at `at` of `text` is an instruction: indented by two spaces and not the head of a `switch`
 * (which spans several lines, its closing bracket line takes the metadata). */
static bool is_instruction(MsSpan line) {
  return line.len > 2 && line.ptr[0] == ' ' && line.ptr[1] == ' ' && line.ptr[2] != ' ' &&
         line.ptr[line.len - 1] != '[';
}

/* Adds `, !dbg !<node>` to every instruction written since `from`. */
static void tag_text(MsStrBuild *out, size_t from, uint32_t node) {
  MsStrBuild tail = ms_strbuild_new();
  MsSpan written = ms_strbuild_span(out);
  ms_strbuild_append(&tail, ms_span_of(written.ptr + from, written.len - from));
  out->bytes.len = from;
  MsSpan text = ms_strbuild_span(&tail);
  size_t start = 0;
  while (start < text.len) {
    size_t end = start;
    while (end < text.len && text.ptr[end] != '\n') {
      end++;
    }
    MsSpan line = ms_span_of(text.ptr + start, end - start);
    ms_strbuild_append(out, line);
    if (is_instruction(line)) {
      ms_strbuild_printf(out, ", !dbg !%u", node);
    }
    if (end < text.len) {
      ms_strbuild_append_byte(out, '\n');
    }
    start = end + 1;
  }
  ms_strbuild_free(&tail);
}

void emit_debug_place(EmitCx *cx, size_t from, MirLoc loc) {
  if (cx->debug == NULL || ms_strbuild_length(cx->out) == from) {
    return;
  }
  bool known = !mir_loc_none(loc) && loc.line != 0;
  uint32_t line = known ? loc.line : body_line(cx);
  /* Scope 0 is the function itself; LLVM may inline it into another, so it gets a number of its own. */
  uint32_t scope = known && loc.scope != 0 ? cx->scope_base + loc.scope : cx->body_scope;
  const uint32_t file = known && loc.file != MIR_NONE ? loc.file : cx->debug->func_file;
  tag_text(cx->out, from, location_node(cx->debug, line, scope, scope_node(cx, file)));
}

void emit_debug_finish(const EmitCx *cx, MsSpan source) {
  EmitDebug *debug = cx->debug;
  MsStrBuild *out = cx->out;
  ms_strbuild_printf(out,
                     "\n!llvm.dbg.cu = !{!%u}\n!llvm.module.flags = !{!%u}\n"
                     "!%u = distinct !DICompileUnit(language: DW_LANG_C99, file: !%u, producer: \"ms\", "
                     "isOptimized: true, runtimeVersion: 0, emissionKind: LineTablesOnly)\n"
                     "!%u = !DIFile(filename: \"",
                     MD_UNIT, MD_FLAGS, MD_UNIT, MD_FILE, MD_FILE);
  append_quoted(out, source);
  ms_strbuild_printf(out,
                     "\", directory: \"\")\n!%u = !{i32 2, !\"Debug Info Version\", i32 3}\n!%u = !{}\n"
                     "!%u = !DISubroutineType(types: !%u)\n",
                     MD_FLAGS, MD_NO_TYPES, MD_TYPE, MD_NO_TYPES);
  ms_strbuild_append(out, ms_strbuild_span(&debug->nodes));
}
