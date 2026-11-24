/* compiler/emit/emit.h: MIR to LLVM IR text.
 *
 * The emitter reads a finished MirModule and writes one LLVM module as text, which the object step hands to the
 * pinned `opt` and `llc`. A function it cannot write is reported by name and reason in `why`. */
#ifndef MS_COMPILER_EMIT_EMIT_H
#define MS_COMPILER_EMIT_EMIT_H

#include "base/strbuild.h"
#include "compiler/mir/mir.h"
#include "compiler/mir/mir_data.h"

typedef struct EmitOptions {
  bool export_all; /* every function gets an external symbol (needed when fault tables name them) */
  bool places;     /* tag each instruction with its source line for the fault tables */
  uint32_t wide_leaves; /* a value of more leaves than this lives in a stack cell; 0 for never */
  bool wide_hide;       /* keep those cells out of LLVM's reach (volatile leaf loads, an opaque `asm`) */
  bool poison_slots;    /* fill a shared stack cell with 0xDD where its occupant is last read (MS_POISON_SLOTS) */
  uint32_t units;       /* the most modules to write (at least 1; at most EMIT_MAX_UNITS) */
  size_t unit_bytes;    /* with `units` above 1: function text each module has at least, so a small program stays one */
} EmitOptions;

enum { EMIT_MAX_UNITS = 16 };

/* The symbol of the entry function once renamed; the user's `main` cannot keep its own name, which the C entry
 * point takes. */
#define EMIT_ENTRY_SYMBOL "ms_entry"

/* Gives functions symbols that cannot clash with each other, the runtime or libc (a user function may be called
 * `main`, `write` or `cleanup.thunk`): the entry function is renamed to EMIT_ENTRY_SYMBOL and every
 * non-exported function gets its id as a suffix. Call it once, before emit_module. */
void emit_name_symbols(MirModule *module);

/* The LLVM target triple of the machine the emitter runs on (the one the program is built for); empty when this
 * host is not supported. */
MsSpan emit_host_triple(void);

/* Writes the module's functions, its static data (`data`, NULL for none), its declarations and its debug metadata
 * into `out[0]` (a new builder). With `options->units` above 1 and enough function text, the functions are cut into
 * consecutive runs of about equal size, one LLVM module each: `out[1]` and up are new builders the caller frees, `*units`
 * says how many there are. Every function has a hidden or exported symbol, so a module declares what another
 * defines; unit 0 holds the static data and the others declare it. False when some function could not be written;
 * `why` then lists one `name: reason` line per function. */
bool emit_module(const MirModule *module, const MirData *data, const MirGlue *glue, const EmitOptions *options,
                 MsStrBuild *out, uint32_t *units, MsStrBuild *why);

/* Appends the C `main(argc, argv)` that hands the entry function to the runtime (`msrt_start`). With `tables`
 * the runtime gets `@ms_tables`, the block the asm tables step appends to the assembly; without it, null and
 * traces have no function or line names. */
void emit_entry_main(const MirModule *module, bool tables, MsStrBuild *out);

#endif
