/* The compiler's symbol tables and the walk from a fault back to source frames.
 *
 * The compiler emits, for each program, a table of functions and one of line ranges (both sorted by address),
 * a blob of NUL-terminated names, and, from ABI version 3, the inlined callees of each range. A return address
 * is turned into `file:line in function` frames by binary search; a frame whose callee was inlined into it
 * becomes several frames. Strings are never copied: a frame points into the blob, which lives as long as the
 * program.
 *
 * Generated code keeps a frame pointer, so the walk follows the chain of saved frame pointers, bounded by the
 * stack segment the task runs on (segments chain to the one below). Windows cannot follow the register: its
 * walk starts from native unwind data and then finds each frame's record by scanning (ms_frames_scan_record).
 */
#ifndef MS_RUNTIME_CORE_FRAMES_H
#define MS_RUNTIME_CORE_FRAMES_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "base/safe.h"

/* The layout is the ABI the compiler emits (crates/ms-rt-abi `FuncEntry`, `LineEntry`, `ScopeEntry`, `Tables`). */
typedef struct MsFuncEntry {
  uintptr_t address;
  uint32_t size;
  uint32_t name_offset; /* NUL-terminated source name in the blob */
  uint32_t file_offset; /* NUL-terminated path as shown in a trace */
  uint32_t line;        /* 1-based line of the declaration */
} MsFuncEntry;

/* The start of a code range, which extends to the next entry. A file offset of UINT32_MAX means the function's. */
typedef struct MsLineEntry {
  uintptr_t pc;
  uint32_t line;
  uint32_t file_offset;
} MsLineEntry;

/* An inlined callee, shown as a frame of its own. */
typedef struct MsScopeEntry {
  uint32_t name_offset;
  uint32_t file_offset; /* UINT32_MAX: unknown */
  uint32_t parent;      /* enclosing scope, 0 for the physical function */
  uint32_t call_line;   /* line of the inlined call inside the enclosing scope */
} MsScopeEntry;

typedef struct MsTables {
  uint32_t abi_version;
  uint32_t reserved;
  const MsFuncEntry *funcs; /* borrowed from the program image */
  size_t func_count;
  const MsLineEntry *lines;
  size_t line_count;
  const uint8_t *strings;
  size_t strings_len;
  const uint32_t *line_scopes; /* one per line entry, ABI 3 and later: 0 the function itself, else 1 + scope index */
  const MsScopeEntry *scopes;
  size_t scope_count;
} MsTables;

_Static_assert(sizeof(MsFuncEntry) == 24 && sizeof(MsLineEntry) == 16 && sizeof(MsScopeEntry) == 16,
         "the compiler emits these entry sizes");
_Static_assert(sizeof(MsTables) == 8 + 9 * sizeof(void *), "the compiler passes this table block");

/* ABI version 4: a program built in several units has one complete table block per unit (each with its own strings and
 * scopes), and passes the set instead. `ms_frames_install` joins them into one block. */
enum { MS_TABLES_SET = 4 };
typedef struct MsTableSet {
  uint32_t abi_version; /* MS_TABLES_SET: the same place as MsTables.abi_version */
  uint32_t count;
  const MsTables *parts[]; /* `count` blocks */
} MsTableSet;

enum {
  MS_TABLES_WITH_SCOPES = 3,
  MS_FRAMES_REPORT_MAX = 32,    /* frames a report names before it says the rest were omitted */
  MS_FRAMES_WALK_MAX = 1000000, /* logical frames one walk may visit, so a corrupt chain ends */
  MS_FRAMES_NATIVE_MAX = 64, /* addresses outside the tables a walk may pass, which cost no step */
};

/* One source frame of a report, innermost first. */
typedef struct MsFrame {
  const char *file;     /* borrowed from the tables' blob, valid for the life of the program */
  const char *function; /* likewise */
  uint32_t line;
  uint32_t repeated; /* further identical frames collapsed into this one (deep recursion) */
} MsFrame;

/* Source frames found by one walk. */
typedef struct MsFrameList {
  MsFrame frames[MS_FRAMES_REPORT_MAX];
  size_t count;
  bool truncated; /* more frames existed than the report keeps */
} MsFrameList;

/* The stack a walk may read: frames outside `low..high` end it unless the chain cell names the segment below.
 * `high == 0` means the bounds are unknown and any frame is accepted. */
typedef struct MsStackWindow {
  uintptr_t low;
  uintptr_t high;
  uintptr_t chain; /* the chain cell of the segment below (four words: low, high, chain, spare), or 0 */
} MsStackWindow;

/* Called with each return address, innermost first; false ends the walk. */
typedef bool (*MsFrameVisit)(uintptr_t return_address, void *context);

/* ---- tables ---- */

/* Installs the tables of the program, once at start (a block, or an MsTableSet when its abi_version is MS_TABLES_SET). The linker may order functions differently from the
 * compiler (macOS arm64 moves functions that only reach a noreturn call), and the lookups search by address, so
 * out-of-order tables are copied and sorted. A null pointer leaves reports without frames. The copy
 * is allocated with ms_alloc. */
void ms_frames_install(const MsTables *tables);
/* Forgets the tables and frees the sorted copy, if one was made. For a build that counts live blocks and for tests;
 * no frame may be collected afterwards. */
void ms_frames_release(void);
/* The installed tables, or NULL. */
const MsTables *ms_frames_tables(void);

/* ---- walking ---- */

/* Visits the return addresses up the frame-pointer chain starting at `fp`, within `window`. */
void ms_frames_walk_chain(uintptr_t fp, MsStackWindow window, MsFrameVisit visit, void *context);

/* Finds the frame record `[saved frame pointer, return address]` at or above `fp` (or `sp` when `fp` is not inside
 * the stack above it) whose return address `is_source` accepts, scanning at most 4 KiB up to `high`. A record
 * returning into native code (`is_native`) at `fp` itself ends the walk. Returns its address, or 0. For
 * Windows, where generated code does not keep its frame register at its own frame record; kept portable so
 * Linux tests cover it. */
uintptr_t ms_frames_scan_record(uintptr_t sp, uintptr_t fp, uintptr_t low, uintptr_t high,
                bool (*is_source)(uintptr_t, const void *), bool (*is_native)(uintptr_t, const void *),
                const void *context);

/* ---- reports ---- */

/* Collects source frames from a feed of return addresses: `ms_frames_collector_add` is the MsFrameVisit. */
typedef struct MsFrameCollector {
  const MsTables *tables;
  MsFrameList *list;
  size_t steps; /* logical frames left (an inlined frame costs one, like a physical one) */
  bool innermost;
  size_t native; /* addresses outside the tables passed so far */
} MsFrameCollector;

void ms_frames_collector_init(MsFrameCollector *collector, MsFrameList *list, size_t steps) MS_NONNULL;
/* An MsFrameVisit over a collector; false once the list is full or the budget is spent. */
bool ms_frames_collector_add(uintptr_t return_address, void *collector);

/* Visits the return addresses of the frames above the caller of the function `anchor` (the one that starts the
 * walk, whose frame pointer is `fp`). Linux and macOS follow the frame-pointer chain from `fp`; Windows ignores
 * `fp` and starts from native unwind data, finding `anchor` on the stack. */
void ms_frames_visit(uintptr_t fp, uintptr_t anchor, MsStackWindow window, MsFrameVisit visit, void *context);
/* Walks from `fp` and collects the source frames into `list`, which must be zeroed. */
void ms_frames_collect(uintptr_t fp, uintptr_t anchor, MsStackWindow window, MsFrameList *list) MS_NONNULL;
/* Collects the source frames of previously captured return addresses into `list`, which must be zeroed. */
void ms_frames_describe(const uintptr_t *addresses, size_t count, MsFrameList *list) MS_NONNULL;
/* Writes the return addresses up the chain from `fp` into `out` (at most `capacity`); returns how many. Nothing
 * is allocated. */
size_t ms_frames_capture(uintptr_t fp, uintptr_t anchor, MsStackWindow window, uintptr_t *out, size_t capacity)
  MS_NONNULL_ARGS(4);

/* ---- lookups (exposed for tests) ---- */

/* The function holding a return address, or NULL. */
const MsFuncEntry *ms_frames_find_function(const MsTables *tables, uintptr_t return_address);

#endif
