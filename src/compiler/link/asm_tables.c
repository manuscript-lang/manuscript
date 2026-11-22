/* Owns writing the fault tables as assembly data (see asm_tables.h). */
#include "compiler/link/asm_tables.h"

AsmFormat asm_host_format(void) {
#if defined(__APPLE__)
  return ASM_MACHO;
#elif defined(_WIN32)
  return ASM_COFF;
#else
  return ASM_ELF;
#endif
}

/* What a word of the blob stands for. */
typedef enum SlotKind { SLOT_BYTES, SLOT_SELF, SLOT_FUNC, SLOT_LABEL, SLOT_SIZE, SLOT_SECOND } SlotKind;

typedef struct Slots {
  uint8_t *kind;  /* per 4 bytes of the blob */
  uint32_t *arg;  /* SELF: offset in the blob; FUNC: index in the scan order; LABEL: label number */
} Slots;

static void mark_word(Slots *slots, size_t at, SlotKind kind, uint32_t arg) {
  slots->kind[at / 4] = (uint8_t)kind;
  slots->arg[at / 4] = arg;
  if (kind != SLOT_SIZE) {
    slots->kind[at / 4 + 1] = SLOT_SECOND;
  }
}

static Slots make_slots(MsArena *arena, const MirTables *tables) {
  size_t count = tables->size / 4 + 2;
  Slots slots = {MS_ARENA_NEW_ARRAY(arena, uint8_t, count), MS_ARENA_NEW_ARRAY(arena, uint32_t, count)};
  for (size_t index = 0; index < MIR_TABLE_POINTERS; index++) {
    mark_word(&slots, tables->pointers[index].at, SLOT_SELF, (uint32_t)tables->pointers[index].to);
  }
  for (size_t index = 0; index < tables->npcs; index++) {
    const MirTablePc *pc = &tables->pcs[index];
    if (pc->off == 0) {
      mark_word(&slots, pc->at, SLOT_FUNC, (uint32_t)pc->func);
      mark_word(&slots, pc->at + 8, SLOT_SIZE, (uint32_t)pc->func);
    } else {
      mark_word(&slots, pc->at, SLOT_LABEL, pc->off);
    }
  }
  return slots;
}

static void write_section(const AsmScan *scan, MsStrBuild *out) {
  switch (scan->format) {
  case ASM_MACHO:
    ms_strbuild_append_text(out, "\t.section\t__DATA,__const\n\t.globl\t_ms_tables\n\t.p2align\t3\n_ms_tables:\n");
    break;
  case ASM_COFF:
    ms_strbuild_append_text(out, "\t.section\t.rdata,\"dr\"\n\t.globl\tms_tables\n\t.p2align\t3\nms_tables:\n");
    break;
  default:
    ms_strbuild_append_text(out,
                            "\t.section\t.data.rel.ro.ms_tables,\"aw\",@progbits\n\t.globl\tms_tables\n"
                            "\t.type\tms_tables,@object\n\t.p2align\t3\nms_tables:\n");
    break;
  }
}

static void write_word(const AsmScan *scan, MsStrBuild *out, SlotKind kind, uint32_t arg, const uint32_t *module_of) {
  const char *prefix = asm_local_prefix(scan->format);
  const char *table = scan->format == ASM_MACHO ? "_ms_tables" : "ms_tables";
  if (kind == SLOT_SELF) {
    ms_strbuild_printf(out, "\t.quad\t%s+%u\n", table, arg);
  } else if (kind == SLOT_FUNC) {
    ms_strbuild_append_text(out, "\t.quad\t");
    ms_strbuild_append(out, scan->funcs[module_of[arg]].label);
    ms_strbuild_append_byte(out, '\n');
  } else if (kind == SLOT_LABEL) {
    ms_strbuild_printf(out, "\t.quad\t%sms_loc_%u\n", prefix, arg);
  } else {
    ms_strbuild_printf(out, "\t.long\t%sms_end_%u-", prefix, module_of[arg]);
    ms_strbuild_append(out, scan->funcs[module_of[arg]].label);
    ms_strbuild_append_byte(out, '\n');
  }
}

/* Writes the blob: events as symbol expressions, the rest as bytes. */
static void write_blob(const AsmScan *scan, const MirTables *tables, const Slots *slots, const uint32_t *module_of,
                       MsStrBuild *out) {
  size_t at = 0;
  while (at < tables->size) {
    SlotKind kind = at % 4 == 0 ? (SlotKind)slots->kind[at / 4] : SLOT_BYTES;
    if (kind == SLOT_SECOND) {
      at += 4;
      continue;
    }
    if (kind != SLOT_BYTES) {
      write_word(scan, out, kind, slots->arg[at / 4], module_of);
      at += kind == SLOT_SIZE ? 4 : 8;
      continue;
    }
    ms_strbuild_append_text(out, "\t.byte\t");
    for (uint32_t count = 0; count < 16 && at < tables->size; count++) {
      ms_strbuild_append_u64(out, tables->blob[at++]);
      bool more = count < 15 && at < tables->size && !(at % 4 == 0 && slots->kind[at / 4] != SLOT_BYTES);
      if (!more) {
        break;
      }
      ms_strbuild_append_byte(out, ',');
    }
    ms_strbuild_append_byte(out, '\n');
  }
}

/* LLVM inlines function bodies into one another, and the assembly names only the body a place belongs to. A run
 * of ranges of another function's body (scope numbers from `first_body` up) is such an inlined body: it gets a
 * scope of its own, called from the place of the range before it, so a trace shows the caller too. The new scopes
 * follow `info->scopes`. */
static void attribute_inlined_bodies(MsArena *arena, AsmScan *scan, const EmitTableInfo *info, EmitTableInfo *out) {
  const uint32_t first_body = info->nscopes - (uint32_t)scan->module->funcs.len + 1;
  MirScope *scopes = MS_ARENA_NEW_ARRAY(arena, MirScope, (size_t)info->nscopes + scan->ranges.len + 1);
  for (uint32_t index = 0; index < info->nscopes; index++) {
    scopes[index] = info->scopes[index];
  }
  uint32_t total = info->nscopes;
  for (size_t at = 0; at < scan->order.len; at++) {
    const AsmFunc *found = &scan->funcs[scan->order.ptr[at]];
    uint32_t previous_scope = 0;
    uint32_t previous_line = 0;
    uint32_t previous_original = 0;
    for (uint32_t index = found->first; index < found->first + found->count; index++) {
      MirCodeRange *range = &scan->ranges.ptr[index];
      const uint32_t original = range->scope;
      if (original >= first_body && original <= info->nscopes) {
        if (original != previous_original) {
          MirScope entry = info->scopes[original - 1];
          entry.parent = previous_scope;
          entry.call_line = previous_line;
          scopes[total++] = entry;
        }
        range->scope = total;
      }
      previous_original = original;
      previous_scope = range->scope;
      previous_line = range->line;
    }
  }
  *out = (EmitTableInfo){.display = info->display, .scopes = scopes, .nscopes = total};
}

bool link_asm_tables(MsArena *arena, const MirModule *module, const EmitTableInfo *info, MsSpan assembly,
                     MsStrBuild *out, MsStrBuild *why) {
  AsmScan scan;
  asm_scan_init(&scan, arena, asm_host_format(), module, info);
  bool ok = asm_scan(&scan, assembly, why);
  EmitTableInfo grown = *info;
  if (ok) {
    attribute_inlined_bodies(arena, &scan, info, &grown);
    uint32_t count = (uint32_t)scan.order.len;
    MirFuncTable *funcs = MS_ARENA_NEW_ARRAY(arena, MirFuncTable, count);
    for (uint32_t index = 0; index < count; index++) {
      uint32_t func = scan.order.ptr[index];
      const AsmFunc *found = &scan.funcs[func];
      funcs[index] = (MirFuncTable){.name = info->display[func],
                                    .file = module->funcs.ptr[func].loc.file,
                                    .line = module->funcs.ptr[func].loc.line,
                                    .ranges = scan.ranges.ptr + found->first,
                                    .nranges = found->count};
    }
    MirTables tables;
    mir_fault_tables(arena, module, funcs, count, grown.scopes, grown.nscopes, &tables);
    Slots slots = make_slots(arena, &tables);
    ms_strbuild_append(out, ms_strbuild_span(&scan.out));
    write_section(&scan, out);
    write_blob(&scan, &tables, &slots, scan.order.ptr, out);
  }
  asm_scan_free(&scan);
  return ok;
}
