/* Symbol tables and frame walking for fault reports. See frames.h. */
#include "runtime/core/frames.h"

#include <stdatomic.h>

#include "base/alloc.h"
#include "base/cstr.h"
#include "base/fatal.h"
#include "runtime/sys/sys.h"

static _Atomic(const MsTables *) installed_tables; /* set once at start; read by any thread that faults */
typedef struct SortedTables SortedTables;
static SortedTables *owned_copy;                   /* the sorted copy installed_tables points at, or NULL */

const MsTables *ms_frames_tables(void) { return atomic_load_explicit(&installed_tables, memory_order_acquire); }

/* ---- tables in address order ---- */

typedef struct SortKey {
  uintptr_t address;
  uint32_t index;
} SortKey;

/* Stable bottom-up merge sort of `keys` by address, using `spare` of the same length. */
static void sort_keys(SortKey *keys, SortKey *spare, size_t count) {
  for (size_t width = 1; width < count; width *= 2) {
    for (size_t start = 0; start < count; start += 2 * width) {
      const size_t middle = start + width < count ? start + width : count;
      const size_t end = start + 2 * width < count ? start + 2 * width : count;
      size_t left = start;
      size_t right = middle;
      for (size_t out = start; out < end; out++) {
        const bool take_left = right >= end || (left < middle && keys[left].address <= keys[right].address);
        spare[out] = take_left ? keys[left++] : keys[right++];
      }
    }
    for (size_t i = 0; i < count; i++) {
      keys[i] = spare[i];
    }
  }
}

static bool funcs_sorted(const MsTables *tables) {
  for (size_t i = 1; i < tables->func_count; i++) {
    if (tables->funcs[i].address < tables->funcs[i - 1].address) {
      return false;
    }
  }
  return true;
}

/* Fills `order` with the indices of `count` keys in address order. `keys` and `spare` are scratch of `count`. */
static void order_by_address(SortKey *keys, SortKey *spare, size_t count, uint32_t *order) {
  sort_keys(keys, spare, count);
  for (size_t i = 0; i < count; i++) {
    order[i] = keys[i].index;
  }
}

/* The sorted copy: the tables block plus the three arrays it points at, which it owns. */
struct SortedTables {
  MsTables tables;
  MsFuncEntry *funcs;
  MsLineEntry *lines;
  uint32_t *scopes;
};

/* Bytes of `count` elements of `size`; a table whose size overflows is corrupt. */
static size_t array_bytes(size_t count, size_t size) {
  size_t bytes = 0;
  if (!ms_size_mul(count, size, &bytes)) {
    ms_fatal(MS_FATAL_OVERFLOW, "symbol table size overflows");
  }
  return bytes;
}

/* The copy of `tables` with functions and lines in address order. */
static SortedTables *sorted_copy(const MsTables *tables) {
  const bool scoped = tables->abi_version >= MS_TABLES_WITH_SCOPES && tables->line_scopes != NULL;
  const size_t longest = tables->func_count > tables->line_count ? tables->func_count : tables->line_count;
  SortedTables *const copy = ms_alloc(sizeof *copy);
  SortKey *const keys = ms_alloc(array_bytes(longest, 2 * sizeof(SortKey)));
  uint32_t *const order = ms_alloc(array_bytes(longest, sizeof(uint32_t)));
  copy->funcs = ms_alloc(array_bytes(tables->func_count, sizeof(MsFuncEntry)));
  copy->lines = ms_alloc(array_bytes(tables->line_count, sizeof(MsLineEntry)));
  copy->scopes = ms_alloc(array_bytes(tables->line_count, sizeof(uint32_t)));
  for (size_t i = 0; i < tables->func_count; i++) {
    keys[i] = (SortKey){.address = tables->funcs[i].address, .index = (uint32_t)i};
  }
  order_by_address(keys, keys + longest, tables->func_count, order);
  for (size_t i = 0; i < tables->func_count; i++) {
    copy->funcs[i] = tables->funcs[order[i]];
  }
  for (size_t i = 0; i < tables->line_count; i++) {
    keys[i] = (SortKey){.address = tables->lines[i].pc, .index = (uint32_t)i};
  }
  order_by_address(keys, keys + longest, tables->line_count, order);
  for (size_t i = 0; i < tables->line_count; i++) {
    copy->lines[i] = tables->lines[order[i]];
    copy->scopes[i] = scoped ? tables->line_scopes[order[i]] : 0;
  }
  ms_free(keys);
  ms_free(order);
  copy->tables = *tables;
  copy->tables.funcs = copy->funcs;
  copy->tables.lines = copy->lines;
  copy->tables.line_scopes = scoped ? copy->scopes : NULL;
  return copy;
}

void ms_frames_release(void) {
  atomic_store_explicit(&installed_tables, NULL, memory_order_release);
  if (owned_copy != NULL) {
    ms_free(owned_copy->funcs);
    ms_free(owned_copy->lines);
    ms_free(owned_copy->scopes);
    ms_free(owned_copy);
    owned_copy = NULL;
  }
}

void ms_frames_install(const MsTables *tables) {
  SortedTables *copy = NULL;
  if (tables != NULL && tables->funcs != NULL && !funcs_sorted(tables)) {
    copy = sorted_copy(tables);
  }
  ms_frames_release();
  owned_copy = copy;
  atomic_store_explicit(&installed_tables, copy != NULL ? &copy->tables : tables, memory_order_release);
}
/* ---- lookups ---- */

/* The NUL-terminated name at `offset` of the blob, or "?" when it is out of range or has no end inside the blob. */
static const char *checked_name(const MsTables *tables, uint32_t offset) {
  if (offset == UINT32_MAX || offset >= tables->strings_len) {
    return "?";
  }
  for (size_t at = offset; at < tables->strings_len; at++) {
    if (tables->strings[at] == 0) {
      return (const char *)tables->strings + offset;
    }
  }
  return "?";
}

const MsFuncEntry *ms_frames_find_function(const MsTables *tables, uintptr_t return_address) {
  if (tables->funcs == NULL || tables->func_count == 0) {
    return NULL;
  }
  /* The call instruction lies in the range ending just before the return address. */
  const uintptr_t probe = return_address - 1;
  size_t low = 0;
  size_t high = tables->func_count;
  while (low < high) {
    const size_t middle = low + (high - low) / 2;
    if (tables->funcs[middle].address <= probe) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  if (low == 0) {
    return NULL;
  }
  const MsFuncEntry *const entry = &tables->funcs[low - 1];
  return probe - entry->address < entry->size ? entry : NULL;
}

/* A resolved position: where the instruction at a return address came from. */
typedef struct Position {
  uint32_t line;
  uint32_t file_offset;
  uint32_t scope; /* 0: the function itself */
} Position;

static Position position_of(const MsTables *tables, const MsFuncEntry *function, size_t line_index) {
  const MsLineEntry *const entry = &tables->lines[line_index];
  const bool scoped = tables->abi_version >= MS_TABLES_WITH_SCOPES && tables->line_scopes != NULL;
  return (Position){.line = entry->line,
            .file_offset = entry->file_offset == UINT32_MAX ? function->file_offset : entry->file_offset,
            .scope = scoped ? tables->line_scopes[line_index] : 0};
}

/* The number of line entries starting at or before the call instruction of `return_address`. */
static size_t lines_through(const MsTables *tables, uintptr_t return_address) {
  const uintptr_t probe = return_address - 1;
  size_t low = 0;
  size_t high = tables->line_count;
  while (low < high) {
    const size_t middle = low + (high - low) / 2;
    if (tables->lines[middle].pc <= probe) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return low;
}

static Position function_position(const MsFuncEntry *function) {
  return (Position){.line = function->line, .file_offset = function->file_offset, .scope = 0};
}

static Position find_line(const MsTables *tables, const MsFuncEntry *function, uintptr_t return_address) {
  if (tables->lines != NULL && tables->line_count > 0) {
    const size_t through = lines_through(tables, return_address);
    if (through > 0 && tables->lines[through - 1].pc >= function->address) {
      return position_of(tables, function, through - 1);
    }
  }
  return function_position(function);
}

/* Like find_line, but skips back over ranges with no position to the nearest earlier one. */
static Position find_line_before(const MsTables *tables, const MsFuncEntry *function, uintptr_t return_address) {
  if (tables->lines == NULL || tables->line_count == 0) {
    return function_position(function);
  }
  size_t through = lines_through(tables, return_address);
  while (through > 0 && tables->lines[through - 1].pc >= function->address) {
    if (tables->lines[through - 1].line != 0) {
      return position_of(tables, function, through - 1);
    }
    through--;
  }
  return function_position(function);
}

/* The inlined-callee scope `id` (1-based), or NULL. */
static const MsScopeEntry *scope_entry(const MsTables *tables, uint32_t id) {
  if (tables->abi_version < MS_TABLES_WITH_SCOPES || tables->scopes == NULL || id == 0 || id > tables->scope_count) {
    return NULL;
  }
  return &tables->scopes[id - 1];
}

/* ---- the frame-pointer chain ---- */

/* Copies `count` words from the stack address `address`, which the caller has checked lies inside a live stack. */
static void read_words(uintptr_t address, uintptr_t *out, size_t count) {
  // NOLINTNEXTLINE(performance-no-int-to-ptr): a stack walk reads memory at addresses it computed
  __builtin_memcpy(out, (const void *)address, count * sizeof *out);
}

/* Bounds of the segment holding the frame record at `fp`, following the chain cells down when `fp` is outside
 * the current one. False when no segment holds it. */
static bool segment_holding(uintptr_t fp, MsStackWindow *window) {
  for (;;) {
    if (window->high == 0 || (fp >= window->low && fp <= UINTPTR_MAX - 16 && fp + 16 <= window->high)) {
      return true;
    }
    if (window->chain == 0) {
      return false;
    }
    /* A chain cell is written before frames exist on its segment and stays until the segment is given back,
     * after the frames above it are gone. */
    uintptr_t cell[3] = {0};
    read_words(window->chain, cell, MS_COUNT_OF(cell));
    *window = (MsStackWindow){.low = cell[0], .high = cell[1], .chain = cell[2]};
  }
}

void ms_frames_walk_chain(uintptr_t fp, MsStackWindow window, MsFrameVisit visit, void *context) {
  for (size_t steps = 0; fp != 0 && fp % sizeof(uintptr_t) == 0 && steps < MS_FRAMES_WALK_MAX + MS_FRAMES_NATIVE_MAX; steps++) {
    if (!segment_holding(fp, &window)) {
      return;
    }
    uintptr_t record[2] = {0};
    read_words(fp, record, MS_COUNT_OF(record));
    const uintptr_t next = record[0];
    const uintptr_t return_address = record[1];
    if (return_address == 0 || !visit(return_address, context)) {
      return;
    }
    /* Frames go up within a segment; the segment below may lie anywhere. */
    if (next <= fp && (window.high == 0 || next >= window.low)) {
      return;
    }
    fp = next;
  }
}

enum { SCAN_BYTES = 4096 };

uintptr_t ms_frames_scan_record(uintptr_t sp, uintptr_t fp, uintptr_t low, uintptr_t high,
                bool (*is_source)(uintptr_t, const void *), bool (*is_native)(uintptr_t, const void *),
                                const void *context) {
  const bool from_fp = fp >= sp && fp < high && fp % sizeof(uintptr_t) == 0;
  uintptr_t first = fp;
  if (!from_fp) {
    if (sp > UINTPTR_MAX - 7) {
      return 0;
    }
    first = (sp + 7) & ~(uintptr_t)7;
  }
  if (high < 16 || first > UINTPTR_MAX - SCAN_BYTES) {
    return 0;
  }
  uintptr_t last = first + SCAN_BYTES;
  if (last > high - 16) {
    last = high - 16;
  }
  for (uintptr_t at = first; at <= last; at += sizeof(uintptr_t)) {
    if (at < low) {
      continue;
    }
    uintptr_t record[2] = {0};
    read_words(at, record, MS_COUNT_OF(record));
    if (record[0] <= at || record[0] % sizeof(uintptr_t) != 0 || record[0] >= high) {
      continue;
    }
    if (is_source(record[1], context)) {
      return at;
    }
    if (from_fp && at == fp && is_native(record[1], context)) {
      return 0;
    }
  }
  return 0;
}

/* ---- source frames ---- */

void ms_frames_collector_init(MsFrameCollector *collector, MsFrameList *list, size_t steps) {
  *collector = (MsFrameCollector){.tables = ms_frames_tables(), .list = list, .steps = steps, .innermost = true};
}

static bool spend_step(MsFrameCollector *collector) {
  if (collector->steps > 0) {
    collector->steps--;
  }
  return collector->steps > 0;
}

/* Whether the frame just built repeats the last one in the list, by text: an inlined copy of a function names
 * itself by another table offset. */
static bool repeats_last(const MsFrameList *list, const MsFrame *frame) {
  if (list->count == 0) {
    return false;
  }
  const MsFrame *const last = &list->frames[list->count - 1];
  return last->line == frame->line && ms_cstr_equal(last->function, frame->function) &&
         ms_cstr_equal(last->file, frame->file);
}

/* Appends one frame, or counts it into the previous one. False once the list is full. */
static bool append_frame(MsFrameList *list, const MsFrame *frame) {
  if (repeats_last(list, frame)) {
    list->frames[list->count - 1].repeated++;
    return true;
  }
  if (list->count == MS_FRAMES_REPORT_MAX) {
    list->truncated = true;
    return false;
  }
  list->frames[list->count++] = *frame;
  return true;
}

/* Whether a frame belongs to the standard library, whose frames a report leaves out: the user's call into it
 * is the frame that matters (`@std/core.ms` and the like). */
static bool is_standard_frame(const MsFrame *frame) {
  return frame->file[0] == '@' && frame->file[1] == 's' && frame->file[2] == 't' && frame->file[3] == 'd' &&
         frame->file[4] == '/';
}

/* Adds the frames of one return address: the inlined callees innermost first, then the physical function. */
static bool add_scoped_frames(MsFrameCollector *collector, const MsFuncEntry *function, Position position) {
  const MsTables *const tables = collector->tables;
  uint32_t name_offset = function->name_offset;
  uint32_t file_offset = position.file_offset;
  uint32_t line = position.line;
  uint32_t scope = position.scope;
  for (;;) {
    if (collector->steps == 0) {
      return false;
    }
    collector->steps--;
    const MsScopeEntry *const inlined = scope_entry(tables, scope);
    if (inlined != NULL) {
      name_offset = inlined->name_offset;
      file_offset = inlined->file_offset != UINT32_MAX ? inlined->file_offset : file_offset;
    }
    /* A thunk inlined into its caller has no position of its own. */
    const MsFrame frame = {.file = checked_name(tables, file_offset),
                 .function = checked_name(tables, name_offset),
                 .line = line};
    if (line != 0 && !is_standard_frame(&frame) && !append_frame(collector->list, &frame)) {
      return false;
    }
    if (inlined == NULL) {
      return true;
    }
    line = inlined->call_line;
    scope = inlined->parent;
    /* A wrapper without a position of its own has no frame once its callee is shown. */
    if (line == 0 && scope == 0) {
      return true;
    }
    name_offset = function->name_offset;
    file_offset = function->file_offset;
  }
}

bool ms_frames_collector_add(uintptr_t return_address, void *context) {
  MsFrameCollector *const collector = context;
  const MsTables *const tables = collector->tables;
  if (tables == NULL) {
    return false;
  }
  const MsFuncEntry *const function = ms_frames_find_function(tables, return_address);
  if (function == NULL) {
    /* The runtime's own frames above the first one of source cost no step, so the count of frames shown does
     * not depend on how many the fault path has. */
    return ++collector->native <= MS_FRAMES_NATIVE_MAX;
  }
  Position position = find_line(tables, function, return_address);
  /* The frame that raised the fault may sit in a call without a position of its own; it takes the nearest
   * earlier line. */
  if (position.line == 0 && collector->innermost) {
    position = find_line_before(tables, function, return_address);
  }
  collector->innermost = false;
  /* Compiler-generated glue (function-value thunks) has no source position. */
  if (position.line == 0) {
    return spend_step(collector);
  }
  return add_scoped_frames(collector, function, position);
}

static bool is_source_address(uintptr_t pc, const void *tables) { return ms_frames_find_function(tables, pc) != NULL; }

static bool is_native_address(uintptr_t pc, const void *unused) {
  (void)unused;
  return ms_sys_has_unwind_data(pc);
}

/* Windows: the system's unwind data leads from the runtime's frames to the first frame of generated code; from
 * there each frame's record is found by scanning, since the frame register does not point at it. */
static void visit_native(uintptr_t anchor, MsFrameVisit visit, void *context) {
  const MsTables *const tables = ms_frames_tables();
  MsSysNativeStart start = {0};
  if (tables == NULL || !ms_sys_native_start(anchor, is_source_address, tables, MS_FRAMES_WALK_MAX, &start)) {
    return;
  }
  uintptr_t low = 0;
  uintptr_t high = 0;
  ms_sys_stack_bounds(&low, &high);
  uintptr_t pc = start.pc;
  for (size_t step = 0; step < start.budget; step++) {
    if (ms_frames_find_function(tables, pc) == NULL || !visit(pc, context)) {
      return;
    }
    const uintptr_t at = ms_frames_scan_record(start.sp, start.fp, low, high, is_source_address, is_native_address,
                           tables);
    if (at == 0) {
      return;
    }
    uintptr_t record[2] = {0};
    read_words(at, record, MS_COUNT_OF(record));
    start.fp = record[0];
    pc = record[1];
    start.sp = at + 2 * sizeof(uintptr_t);
  }
}

void ms_frames_visit(uintptr_t fp, uintptr_t anchor, MsStackWindow window, MsFrameVisit visit, void *context) {
  if (ms_sys_frame_pointer_chain()) {
    ms_frames_walk_chain(fp, window, visit, context);
    return;
  }
  visit_native(anchor, visit, context);
}

void ms_frames_collect(uintptr_t fp, uintptr_t anchor, MsStackWindow window, MsFrameList *list) {
  MsFrameCollector collector;
  ms_frames_collector_init(&collector, list, MS_FRAMES_WALK_MAX);
  ms_frames_visit(fp, anchor, window, ms_frames_collector_add, &collector);
}

void ms_frames_describe(const uintptr_t *addresses, size_t count, MsFrameList *list) {
  MsFrameCollector collector;
  ms_frames_collector_init(&collector, list, MS_FRAMES_WALK_MAX);
  for (size_t i = 0; i < count; i++) {
    if (!ms_frames_collector_add(addresses[i], &collector)) {
      return;
    }
  }
}

typedef struct Capture {
  uintptr_t *out;
  size_t capacity;
  size_t count;
} Capture;

static bool capture_one(uintptr_t return_address, void *context) {
  Capture *const capture = context;
  capture->out[capture->count++] = return_address;
  return capture->count < capture->capacity;
}

size_t ms_frames_capture(uintptr_t fp, uintptr_t anchor, MsStackWindow window, uintptr_t *out, size_t capacity) {
  if (capacity == 0) {
    return 0;
  }
  Capture capture = {.out = out, .capacity = capacity};
  ms_frames_visit(fp, anchor, window, capture_one, &capture);
  return capture.count;
}
