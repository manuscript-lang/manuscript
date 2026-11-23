/* The sampling profiler (profile.h). The system's clock (sys/sampler.c) calls `on_sample` with the registers of the
 * thread that runs `main`; the sample is the pc and the return addresses up the frame chain, stored in a buffer made at
 * start (nothing is allocated while sampling). At the end of the process the addresses are named through the program's
 * function table and equal stacks are counted together into a folded-stacks file. */
#include "runtime/entry/profile.h"

#include <stdatomic.h>

#include "base/alloc.h"
#include "base/env.h"
#include "base/file.h"
#include "base/sort.h"
#include "runtime/core/frames.h"
#include "runtime/core/scheduler.h"
#include "runtime/sys/sys.h"

enum {
  MAX_SAMPLES = 32768,
  MAX_FRAMES = 128,
  SAMPLE_WORDS = MAX_FRAMES + 1, /* the frame count, then the pcs innermost first */
  DEFAULT_HZ = 1000,
  MAX_HZ = 10000,
  NATIVE_SCAN_BYTES = 4096, /* how far above the stack pointer a sample inside the runtime looks for its caller */
};

static uintptr_t *buffer;
static _Atomic size_t sample_count;
static _Atomic size_t dropped;
static _Atomic bool active; /* sampling is armed and the file not yet written */
static MsString out_path;
static uint32_t rate;

static const char *name_of(const MsTables *tables, const MsFuncEntry *function) {
  return function->name_offset < tables->strings_len ? (const char *)tables->strings + function->name_offset : "?";
}

/* ---- sampling: runs in a signal handler (Linux, macOS) or on the sampler thread (Windows) ---- */

typedef struct Walk {
  uintptr_t *frames;
  size_t count;
} Walk;

static bool add_frame(uintptr_t return_address, void *context) {
  Walk *const walk = context;
  if (walk->count >= MAX_FRAMES) {
    return false;
  }
  walk->frames[walk->count++] = return_address;
  return true;
}

static bool is_source_address(uintptr_t pc, const void *tables) { return ms_frames_find_function(tables, pc) != NULL; }

static bool is_native_address(uintptr_t pc, const void *unused) {
  (void)unused;
  return ms_sys_has_unwind_data(pc);
}

static uintptr_t read_word(uintptr_t address) {
  uintptr_t word = 0;
  __builtin_memcpy(&word, (const void *)address, sizeof word); // NOLINT(performance-no-int-to-ptr)
  return word;
}

/* The runtime does not keep a frame pointer, so a sample inside it holds the frame register of the generated function
 * that called it, and the walk would skip that function. The caller's own address is the first return address into
 * source code on the stack above the stack pointer. */
static void add_caller_of_native(const MsSysSample *sample, const MsTables *tables, const uintptr_t window[3], Walk *walk) {
  const uintptr_t end = sample->fp > sample->sp && sample->fp - sample->sp < NATIVE_SCAN_BYTES ? sample->fp : sample->sp;
  for (uintptr_t at = (sample->sp + 7) & ~(uintptr_t)7; at + sizeof(uintptr_t) <= end && at + sizeof(uintptr_t) <= window[1];
       at += sizeof(uintptr_t)) {
    if (at >= window[0] && is_source_address(read_word(at), tables)) {
      (void)add_frame(read_word(at), walk);
      return;
    }
  }
}

/* Windows: the frame register does not point at the frame record, so each record is found by scanning the stack. */
static void walk_by_scanning(const MsSysSample *sample, const MsTables *tables, const uintptr_t window[3], Walk *walk) {
  uintptr_t sp = sample->sp;
  uintptr_t fp = sample->fp;
  while (walk->count < MAX_FRAMES) {
    const uintptr_t at = ms_frames_scan_record(sp, fp, window[0], window[1], is_source_address, is_native_address, tables);
    if (at == 0) {
      return;
    }
    const uintptr_t record_fp = read_word(at);
    const uintptr_t return_address = read_word(at + sizeof(uintptr_t));
    if (!add_frame(return_address, walk)) {
      return;
    }
    fp = record_fp;
    sp = at + 2 * sizeof(uintptr_t);
  }
}

/* Writes the stack of `sample` into `slot`: the frame count, then the pcs innermost first. */
static void capture(const MsSysSample *sample, uintptr_t *slot) {
  Walk walk = {.frames = slot + 1};
  (void)add_frame(sample->pc, &walk);
  uintptr_t window[3];
  const MsTables *const tables = ms_frames_tables();
  /* Without a running task there is no stack to read: the sample is its pc alone. */
  if (tables != NULL && ms_sched_sample_window(window) && window[1] != 0) {
    if (!ms_sys_frame_pointer_chain()) {
      walk_by_scanning(sample, tables, window, &walk);
    } else {
      if (!is_source_address(sample->pc + 1, tables)) {
        add_caller_of_native(sample, tables, window, &walk);
      }
      const MsStackWindow stack = {.low = window[0], .high = window[1], .chain = window[2]};
      ms_frames_walk_chain(sample->fp, stack, add_frame, &walk);
    }
  }
  slot[0] = walk.count;
}

static void on_sample(const MsSysSample *sample) {
  const size_t index = atomic_load_explicit(&sample_count, memory_order_relaxed);
  if (index >= MAX_SAMPLES) {
    atomic_fetch_add_explicit(&dropped, 1, memory_order_relaxed);
    return;
  }
  capture(sample, buffer + index * SAMPLE_WORDS);
  atomic_store_explicit(&sample_count, index + 1, memory_order_release);
}

/* ---- allocation sampling: every `alloc_period`th allocation of the main thread is a sample ---- */

enum { DEFAULT_ALLOC_PERIOD = 128 };

static MsString alloc_path;
static uintptr_t *alloc_buffer;
static uint64_t *alloc_sizes;
static size_t alloc_samples;
static size_t alloc_dropped;
static uint32_t alloc_period;
static _Atomic bool alloc_active;
static _Thread_local bool main_thread;
static _Thread_local uint32_t alloc_tick;

/* Called by the allocator (base/alloc.h) with each request's size; the stack is the caller's, read as a signal sample
 * would read it: the frame register at the call is the generated function's, and the first return address into source
 * code above this frame is its caller. */
static __attribute__((noinline)) void on_alloc(size_t size) {
  if (!main_thread || !atomic_load_explicit(&alloc_active, memory_order_relaxed) || ++alloc_tick < alloc_period) {
    return;
  }
  alloc_tick = 0;
  if (alloc_samples >= MAX_SAMPLES) {
    alloc_dropped++;
    return;
  }
  const uintptr_t frame = (uintptr_t)__builtin_frame_address(0);
  const MsSysSample here = {.pc = (uintptr_t)&on_alloc, .sp = frame, .fp = read_word(frame)};
  capture(&here, alloc_buffer + alloc_samples * SAMPLE_WORDS);
  alloc_sizes[alloc_samples++] = size;
}

/* ---- control ---- */

static uint32_t configured_rate(void) {
  MsString value;
  uint64_t hz = 0;
  if (ms_env_get("MS_PROFILE_HZ", &value)) {
    const MsSpan text = ms_string_span(&value);
    for (size_t i = 0; i < text.len && text.ptr[i] >= '0' && text.ptr[i] <= '9' && hz <= MAX_HZ; i++) {
      hz = hz * 10 + (uint64_t)(text.ptr[i] - '0');
    }
    ms_string_release(&value);
  }
  return hz >= 1 && hz <= MAX_HZ ? (uint32_t)hz : DEFAULT_HZ;
}

/* MS_PROFILE_ALLOCS=<path> also samples allocations: counts go to <path>, bytes to <path>.bytes. */
static void start_allocs(void) {
  MsString path;
  if (!ms_env_get("MS_PROFILE_ALLOCS", &path)) {
    return;
  }
  if (ms_string_length(&path) == 0) {
    ms_string_release(&path);
    return;
  }
  alloc_path = path;
  alloc_period = DEFAULT_ALLOC_PERIOD;
  MsString value;
  if (ms_env_get("MS_PROFILE_ALLOC_PERIOD", &value)) {
    const MsSpan text = ms_string_span(&value);
    uint64_t period = 0;
    for (size_t i = 0; i < text.len && text.ptr[i] >= '0' && text.ptr[i] <= '9' && period <= UINT32_MAX; i++) {
      period = period * 10 + (uint64_t)(text.ptr[i] - '0');
    }
    ms_string_release(&value);
    alloc_period = period >= 1 && period <= UINT32_MAX ? (uint32_t)period : DEFAULT_ALLOC_PERIOD;
  }
  alloc_buffer = ms_alloc_zeroed(MAX_SAMPLES * SAMPLE_WORDS * sizeof *alloc_buffer);
  alloc_sizes = ms_alloc_zeroed(MAX_SAMPLES * sizeof *alloc_sizes);
}

void ms_profile_start(void) {
  MsString path;
  if (!ms_env_get("MS_PROFILE", &path)) {
    return;
  }
  if (ms_string_length(&path) == 0) {
    ms_string_release(&path);
    return;
  }
  out_path = path;
  rate = configured_rate();
  buffer = ms_alloc_zeroed(MAX_SAMPLES * SAMPLE_WORDS * sizeof *buffer);
  start_allocs();
  atomic_store(&active, true);
  ms_sys_sampler_exclude_thread();
}

#ifndef _WIN32
/* MS_PERF_MAP=1: the function table as /tmp/perf-<pid>.map, which `perf` reads to name the program's functions. */
static void write_perf_map(void) {
  MsString value;
  if (!ms_env_get("MS_PERF_MAP", &value)) {
    return;
  }
  const bool wanted = ms_span_is_text(ms_string_span(&value), "1");
  ms_string_release(&value);
  const MsTables *const tables = ms_frames_tables();
  if (!wanted || tables == NULL) {
    return;
  }
  MsStrBuild map = ms_strbuild_new();
  for (size_t i = 0; i < tables->func_count; i++) {
    const MsFuncEntry *const function = &tables->funcs[i];
    ms_strbuild_append_u64_radix(&map, function->address, 16);
    ms_strbuild_append_byte(&map, ' ');
    ms_strbuild_append_u64_radix(&map, function->size, 16);
    ms_strbuild_append_byte(&map, ' ');
    ms_strbuild_append_text(&map, name_of(tables, function));
    ms_strbuild_append_byte(&map, '\n');
  }
  MsStrBuild path = ms_strbuild_new();
  ms_strbuild_append_text(&path, "/tmp/perf-");
  ms_strbuild_append_u64(&path, ms_sys_process_id());
  ms_strbuild_append_text(&path, ".map");
  (void)ms_file_write(ms_strbuild_span(&path), ms_strbuild_span(&map));
  ms_strbuild_free(&path);
  ms_strbuild_free(&map);
}
#endif

void ms_profile_attach(void) {
#ifndef _WIN32
  write_perf_map();
#endif
  if (atomic_load(&active) && alloc_buffer != NULL) {
    main_thread = true;
    atomic_store(&alloc_active, true);
    ms_alloc_observe(on_alloc);
  }
  if (atomic_load(&active) && !ms_sys_sampler_start(rate, on_sample)) {
    atomic_store(&active, false);
  }
}

void ms_profile_exclude_thread(void) {
  if (atomic_load(&active)) {
    ms_sys_sampler_exclude_thread();
  }
}

/* ---- folding ---- */

typedef struct Key {
  size_t offset;
  size_t length;
  size_t sample; /* the sample the stack came from */
} Key;

/* Compares two folded stacks by their text. */
static int64_t compare_keys(uint8_t *text, const uint8_t *a, const uint8_t *b) {
  Key left;
  Key right;
  __builtin_memcpy(&left, a, sizeof left);
  __builtin_memcpy(&right, b, sizeof right);
  const size_t common = left.length < right.length ? left.length : right.length;
  const int order = __builtin_memcmp(text + left.offset, text + right.offset, common);
  if (order != 0) {
    return order;
  }
  return left.length < right.length ? -1 : left.length > right.length ? 1 : 0;
}

enum { RUNTIME_LABEL_LENGTH = 9 };
static const char RUNTIME_LABEL[] = "[runtime]";

/* The names of one sample, outermost first, joined with `;` onto `text`. False when nothing of the program remains. */
static bool fold_one(const MsTables *tables, const uintptr_t *sample, MsStrBuild *text) {
  const size_t frames = sample[0];
  const size_t start = ms_strbuild_length(text);
  bool in_program = false;
  bool last_was_runtime = false;
  /* The innermost frame holds an exact pc and the others return addresses, which name the instruction before them. */
  for (size_t i = frames; i > 0; i--) {
    const uintptr_t address = sample[i];
    const MsFuncEntry *const function = ms_frames_find_function(tables, i == 1 ? address + 1 : address);
    const bool runtime = function == NULL;
    /* Frames above the first of the program are the start shim, and runs of runtime frames are one. */
    if (!in_program && runtime) {
      continue;
    }
    if (runtime && last_was_runtime) {
      continue;
    }
    if (in_program) {
      ms_strbuild_append_byte(text, ';');
    }
    ms_strbuild_append_text(text, runtime ? RUNTIME_LABEL : name_of(tables, function));
    in_program = true;
    last_was_runtime = runtime;
  }
  return ms_strbuild_length(text) > start;
}

/* `weights[s]`, times `scale`, is what sample `s` counts for (1 each when `weights` is NULL). */
static void fold_weighted(const uintptr_t *samples, size_t count, size_t stride, const uint64_t *weights, uint64_t scale,
                          MsStrBuild *out) {
  const MsTables *const tables = ms_frames_tables();
  if (tables == NULL || count == 0) {
    return;
  }
  MsStrBuild text = ms_strbuild_new();
  Key *const keys = ms_alloc(count * sizeof *keys);
  size_t kept = 0;
  for (size_t s = 0; s < count; s++) {
    const size_t offset = ms_strbuild_length(&text);
    if (fold_one(tables, samples + s * stride, &text)) {
      keys[kept++] = (Key){.offset = offset, .length = ms_strbuild_length(&text) - offset, .sample = s};
    }
  }
  /* The buffer may move while it grows, so keys are offsets; the sort runs once it is final. */
  uint8_t *const bytes = text.bytes.ptr;
  if (kept > 0) {
    ms_sort((uint8_t *)keys, kept, sizeof *keys, compare_keys, bytes);
  }
  for (size_t i = 0; i < kept;) {
    uint64_t weight = (weights != NULL ? weights[keys[i].sample] : 1) * scale;
    size_t next = i + 1;
    while (next < kept && compare_keys(bytes, (const uint8_t *)&keys[i], (const uint8_t *)&keys[next]) == 0) {
      weight += (weights != NULL ? weights[keys[next].sample] : 1) * scale;
      next++;
    }
    ms_strbuild_append(out, ms_span_of(bytes + keys[i].offset, keys[i].length));
    ms_strbuild_append_byte(out, ' ');
    ms_strbuild_append_u64(out, weight);
    ms_strbuild_append_byte(out, '\n');
    i = next;
  }
  ms_free(keys);
  ms_strbuild_free(&text);
}

void ms_profile_fold(const uintptr_t *samples, size_t count, size_t stride, MsStrBuild *out) {
  fold_weighted(samples, count, stride, NULL, 1, out);
}

/* The sum of `weights[0..count)`. */
static uint64_t total_of(const uint64_t *weights, size_t count) {
  uint64_t total = 0;
  for (size_t i = 0; i < count; i++) {
    total += weights[i];
  }
  return total;
}

/* Writes the allocation profile: <path> holds the stacks weighted by allocation count, <path>.bytes by bytes, each sample
 * standing for `alloc_period` allocations. */
static void finish_allocs(void) {
  if (!atomic_exchange(&alloc_active, false)) {
    return;
  }
  ms_alloc_observe(NULL);
  const size_t count = alloc_samples;
  MsStrBuild counts = ms_strbuild_new();
  MsStrBuild bytes = ms_strbuild_new();
  ms_strbuild_append_text(&counts, "# period ");
  ms_strbuild_append_u64(&counts, alloc_period);
  ms_strbuild_append_text(&counts, "\n# allocs ");
  ms_strbuild_append_u64(&counts, (uint64_t)count * alloc_period);
  ms_strbuild_append_text(&counts, "\n");
  ms_strbuild_append_text(&bytes, "# period ");
  ms_strbuild_append_u64(&bytes, alloc_period);
  ms_strbuild_append_text(&bytes, "\n# bytes ");
  ms_strbuild_append_u64(&bytes, total_of(alloc_sizes, count) * alloc_period);
  ms_strbuild_append_text(&bytes, "\n");
  fold_weighted(alloc_buffer, count, SAMPLE_WORDS, NULL, alloc_period, &counts);
  fold_weighted(alloc_buffer, count, SAMPLE_WORDS, alloc_sizes, alloc_period, &bytes);
  MsStrBuild bytes_path = ms_strbuild_new();
  ms_strbuild_append(&bytes_path, ms_string_span(&alloc_path));
  ms_strbuild_append_text(&bytes_path, ".bytes");
  (void)ms_file_write(ms_string_span(&alloc_path), ms_strbuild_span(&counts));
  (void)ms_file_write(ms_strbuild_span(&bytes_path), ms_strbuild_span(&bytes));
  ms_strbuild_free(&bytes_path);
  ms_strbuild_free(&counts);
  ms_strbuild_free(&bytes);
}

/* The rate the samples really came at: the kernel delivers the timer on its own tick, so a program profiled at 1000 Hz on
 * a 250 Hz kernel gets about 250 samples a second, and the report's seconds follow from what was measured. */
static uint32_t effective_rate(size_t samples, uint64_t span_ns) {
  if (samples == 0 || span_ns == 0) {
    return rate;
  }
  const uint64_t measured = (samples * UINT64_C(1000000000) + span_ns / 2) / span_ns;
  return measured < 1 ? 1 : (measured > MAX_HZ ? MAX_HZ : (uint32_t)measured);
}

void ms_profile_finish(void) {
  if (!atomic_exchange(&active, false)) {
    return;
  }
  finish_allocs();
  ms_sys_sampler_stop();
  const uint64_t span_ns = ms_sys_sampler_span_ns();
  const size_t count = atomic_load_explicit(&sample_count, memory_order_acquire);
  MsStrBuild out = ms_strbuild_new();
  ms_strbuild_append_text(&out, "# hz=");
  ms_strbuild_append_u64(&out, effective_rate(count + atomic_load(&dropped), span_ns));
  ms_strbuild_append_byte(&out, '\n');
  ms_profile_fold(buffer, count < MAX_SAMPLES ? count : MAX_SAMPLES, SAMPLE_WORDS, &out);
  ms_strbuild_append_text(&out, "# dropped ");
  ms_strbuild_append_u64(&out, atomic_load(&dropped));
  ms_strbuild_append_byte(&out, '\n');
  (void)ms_file_write(ms_string_span(&out_path), ms_strbuild_span(&out));
  ms_strbuild_free(&out);
}
