/* profile.c: the sampling profiler. MS_PROFILE=<path> writes folded stacks at exit; MS_PROFILE_ALLOCS=<path> writes the
 * allocation profile; MS_PERF_MAP=1 writes /tmp/perf-<pid>.map for perf.
 *
 * A sample is the frame count followed by the return addresses, innermost first, in a preallocated ring: taking one
 * allocates nothing, so it may run in a signal handler. Linux and macOS arm ITIMER_PROF, whose SIGPROF lands on any
 * thread; the handler reads the program counter and frame pointer from the signal context and walks the frame-pointer
 * chain inside the stack window of the running task (ms_sched_sample_window). Windows has no profiling signal: a
 * sampler thread suspends the runtime thread at the sampling rate and reads its context. At exit the addresses are
 * resolved through the program's function table and folded into `stack weight` lines.
 *
 * The allocation profile takes every MS_PROFILE_ALLOC_PERIOD-th allocation of the runtime thread (default 128), through
 * the allocator's sample hook, and weights stacks by count and, in `<path>.bytes`, by requested size.
 */
#define _GNU_SOURCE
#define _DARWIN_C_SOURCE
#define _XOPEN_SOURCE 700 /* macOS <ucontext.h> is an error without it; _DARWIN_C_SOURCE keeps the rest visible */

#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <signal.h>
#include <sys/time.h>
#include <ucontext.h>
#include <unistd.h>
#endif

#include "../core/frames.h"
#include "../core/scheduler.h"
#include "entry.h"
#include "ms_rt/alloc.h"
#include "ms_rt/array.h"
#include "ms_rt/safe.h"
#include "ms_rt/sys.h"

enum {
    MAX_SAMPLES = 65536,
    MAX_FRAMES = 128,
    SAMPLE_WORDS = MAX_FRAMES + 1, /* the count, then the addresses */
    ALLOC_WORDS = SAMPLE_WORDS + 1, /* a sample, then the requested size */
    DEFAULT_HZ = 1000,
    MAX_HZ = 10000,
    DEFAULT_ALLOC_PERIOD = 128,
    MICROSECONDS_PER_SECOND = 1000000,
    HEX_LABEL_BYTES = 24,
    FOLD_START_BYTES = 256,
    PATH_BYTES = 64,
};

/* One buffer of samples: `words` per sample. The writer is the sampled thread, the reader the exit path. */
typedef struct SampleRing {
    uintptr_t *buffer;
    size_t words;
    _Atomic size_t count;
    _Atomic size_t dropped;
} SampleRing;

static SampleRing time_ring = {.words = SAMPLE_WORDS};
static SampleRing alloc_ring = {.words = ALLOC_WORDS};
static _Atomic bool sampling;
static _Atomic int64_t alloc_period; /* 0 when allocations are not profiled */
static const char *time_path;
static const char *alloc_path;

/* ---- environment ---- */

static int64_t env_int(const char *name, int64_t fallback, int64_t low, int64_t high) {
    const char *const text = getenv(name);
    if (text == NULL) {
        return fallback;
    }
    char *end = NULL;
    const long long value = strtoll(text, &end, 10);
    return (end != text && *end == '\0' && value >= low && value <= high) ? value : fallback;
}

static const char *env_path(const char *name) {
    const char *const value = getenv(name);
    return (value != NULL && value[0] != '\0') ? value : NULL;
}

/* ---- taking samples ---- */

MS_NODISCARD static bool ring_open(SampleRing *ring) {
    const size_t bytes = MAX_SAMPLES * ring->words * sizeof(uintptr_t);
    void *const memory = ms_sys_map_anon(bytes);
    if (memory == NULL) {
        return false;
    }
    if (!ms_sys_commit(memory, bytes)) {
        ms_sys_unmap(memory, bytes);
        return false;
    }
    ring->buffer = memory;
    return true;
}

typedef struct Walk {
    uintptr_t *slot; /* the sample being written: slot[0] is the count */
    size_t count;
} Walk;

static bool walk_visit(uintptr_t address, void *context) {
    Walk *const walk = context;
    walk->slot[1 + walk->count++] = address;
    return walk->count < MAX_FRAMES;
}

/* Writes the sample for `pc` and the chain from `fp` into `slot`. A window of zeros means the bounds are unknown. */
static void walk_into(uintptr_t *slot, uintptr_t pc, uintptr_t fp, const uintptr_t window[3]) {
    Walk walk = {.slot = slot, .count = 1};
    slot[1] = pc;
    if (window[1] != 0) {
        const MsStackWindow bounds = {.low = window[0], .high = window[1], .chain = window[2]};
        ms_frames_walk_chain(fp, bounds, walk_visit, &walk);
    }
    slot[0] = walk.count;
}

/* The next slot of `ring`, or NULL (counted as dropped) when it is full. The caller publishes it with ring_commit. */
static uintptr_t *ring_next(SampleRing *ring) {
    const size_t used = atomic_load_explicit(&ring->count, memory_order_relaxed);
    if (used >= MAX_SAMPLES) {
        atomic_fetch_add_explicit(&ring->dropped, 1, memory_order_relaxed);
        return NULL;
    }
    return ring->buffer + used * ring->words;
}

static void ring_commit(SampleRing *ring) { atomic_fetch_add_explicit(&ring->count, 1, memory_order_release); }

static void record_sample(uintptr_t pc, uintptr_t fp) {
    uintptr_t window[3] = {0, 0, 0};
    if (!ms_sched_sample_window(window)) {
        window[1] = 0;
    }
    uintptr_t *const slot = ring_next(&time_ring);
    if (slot == NULL) {
        return;
    }
    walk_into(slot, pc, fp, window);
    ring_commit(&time_ring);
}

/* The allocator's hook (msrt_heap_sample_every): stores the stack and size, returns the allocations until the next. */
static int64_t on_alloc_sample(size_t size) {
    const int64_t period = atomic_load(&alloc_period);
    if (period == 0) {
        return INT64_MAX;
    }
    uintptr_t *const slot = ring_next(&alloc_ring);
    if (slot == NULL) {
        return period;
    }
    uintptr_t window[3] = {0, 0, 0};
    uintptr_t frames[MAX_FRAMES];
    size_t count = 0;
    if (ms_sched_sample_window(window)) {
        const MsStackWindow bounds = {.low = window[0], .high = window[1], .chain = window[2]};
        count = ms_frames_capture((uintptr_t)__builtin_frame_address(0), (uintptr_t)on_alloc_sample, bounds, frames,
                                  MAX_FRAMES);
    }
    memcpy(slot + 1, frames, count * sizeof frames[0]);
    slot[0] = count;
    slot[ALLOC_WORDS - 1] = size;
    ring_commit(&alloc_ring);
    return period;
}

/* ---- the sampler: a timer signal on Linux and macOS, a suspending thread on Windows ---- */

#ifdef _WIN32

static HANDLE target_thread;
static MsSysThread *sampler_thread;
static DWORD sample_ms;

static bool read_context(uintptr_t *pc, uintptr_t *fp) {
    CONTEXT context;
    memset(&context, 0, sizeof context);
    context.ContextFlags = CONTEXT_CONTROL | CONTEXT_INTEGER;
    if (SuspendThread(target_thread) == (DWORD)-1) {
        return false;
    }
    const bool got = GetThreadContext(target_thread, &context) != 0;
    (void)ResumeThread(target_thread);
    if (!got) {
        return false;
    }
#if defined(_M_ARM64) || defined(__aarch64__)
    *pc = (uintptr_t)context.Pc;
    *fp = (uintptr_t)context.Fp;
#else
    *pc = (uintptr_t)context.Rip;
    *fp = (uintptr_t)context.Rbp;
#endif
    return true;
}

static void sampler_main(void *argument) {
    (void)argument;
    while (atomic_load(&sampling)) {
        Sleep(sample_ms);
        uintptr_t pc = 0;
        uintptr_t fp = 0;
        if (atomic_load(&sampling) && read_context(&pc, &fp)) {
            record_sample(pc, fp);
        }
    }
}

static void arm_timer(int64_t hz) { sample_ms = (DWORD)(1000 / hz > 0 ? 1000 / hz : 1); }

/* The sampler needs the runtime thread to exist, so it starts there. */
static void attach_sampler(void) {
    if (!atomic_load(&sampling)) {
        return;
    }
    HANDLE target = NULL;
    if (!DuplicateHandle(GetCurrentProcess(), GetCurrentThread(), GetCurrentProcess(), &target, THREAD_SUSPEND_RESUME | THREAD_GET_CONTEXT, FALSE, 0)) {
        return;
    }
    target_thread = target;
    sampler_thread = ms_sys_thread_spawn(0, sampler_main, NULL);
}

static void disarm_timer(void) {
    if (sampler_thread != NULL) {
        ms_sys_thread_join(sampler_thread);
        sampler_thread = NULL;
    }
    if (target_thread != NULL) {
        (void)CloseHandle(target_thread);
        target_thread = NULL;
    }
}

#else

static void registers_of(const ucontext_t *context, uintptr_t *pc, uintptr_t *fp) {
#if defined(__linux__) && defined(__x86_64__)
    *pc = (uintptr_t)context->uc_mcontext.gregs[REG_RIP];
    *fp = (uintptr_t)context->uc_mcontext.gregs[REG_RBP];
#elif defined(__linux__) && defined(__aarch64__)
    *pc = (uintptr_t)context->uc_mcontext.pc;
    *fp = (uintptr_t)context->uc_mcontext.regs[29];
#elif defined(__APPLE__) && defined(__x86_64__)
    *pc = (uintptr_t)context->uc_mcontext->__ss.__rip;
    *fp = (uintptr_t)context->uc_mcontext->__ss.__rbp;
#elif defined(__APPLE__) && defined(__aarch64__)
    *pc = (uintptr_t)__darwin_arm_thread_state64_get_pc(context->uc_mcontext->__ss);
    *fp = (uintptr_t)__darwin_arm_thread_state64_get_fp(context->uc_mcontext->__ss);
#else
#error "the profiler does not know this target's signal context"
#endif
}

static void on_signal(int number, siginfo_t *info, void *context) {
    (void)number;
    (void)info;
    if (!atomic_load_explicit(&sampling, memory_order_relaxed)) {
        return;
    }
    uintptr_t pc = 0;
    uintptr_t fp = 0;
    registers_of(context, &pc, &fp);
    record_sample(pc, fp);
}

static void arm_timer(int64_t hz) {
    struct sigaction action;
    memset(&action, 0, sizeof action);
    action.sa_sigaction = on_signal;
    action.sa_flags = SA_SIGINFO | SA_RESTART;
    sigemptyset(&action.sa_mask);
    (void)sigaction(SIGPROF, &action, NULL);
    const long interval = (long)(MICROSECONDS_PER_SECOND / hz);
    const struct timeval tick = {.tv_sec = interval / MICROSECONDS_PER_SECOND, .tv_usec = interval % MICROSECONDS_PER_SECOND};
    const struct itimerval timer = {.it_interval = tick, .it_value = tick};
    (void)setitimer(ITIMER_PROF, &timer, NULL);
}

static void attach_sampler(void) {}

static void disarm_timer(void) {
    const struct itimerval off = {{0, 0}, {0, 0}};
    (void)setitimer(ITIMER_PROF, &off, NULL);
}

#endif

/* ---- output ---- */

/* The text of the frame at `address`: the function's name, or "[runtime]" outside the program. `top` marks an exact
 * program counter; callers are return addresses, one past the call. */
static const char *frame_label(const MsTables *tables, uintptr_t address, bool top, char *hex) {
    if (tables == NULL) {
        (void)snprintf(hex, HEX_LABEL_BYTES, "0x%llx", (unsigned long long)address);
        return hex;
    }
    const MsFuncEntry *const function = ms_frames_find_function(tables, top ? address + 1 : address);
    if (function == NULL || function->name_offset >= tables->strings_len) {
        return "[runtime]";
    }
    return (const char *)tables->strings + function->name_offset;
}

typedef struct Folded {
    char *key;
    uint64_t weight;
} Folded;

typedef struct FoldSet {
    Folded *items;
    size_t count;
    size_t capacity;
} FoldSet;

typedef struct KeyBuffer {
    char *text;
    size_t length;
    size_t capacity;
} KeyBuffer;

MS_NODISCARD static bool key_append(KeyBuffer *key, const char *text, size_t length) {
    void *grown = key->text;
    if (!ms_array_reserve(&grown, &key->capacity, key->length + length + 1, 1)) {
        return false;
    }
    key->text = grown;
    memcpy(key->text + key->length, text, length);
    key->length += length;
    key->text[key->length] = '\0';
    return true;
}

MS_NODISCARD static bool fold_add(FoldSet *set, const KeyBuffer *key, uint64_t weight) {
    void *grown = set->items;
    if (!ms_array_reserve(&grown, &set->capacity, set->count + 1, sizeof set->items[0])) {
        return false;
    }
    set->items = grown;
    char *const copy = malloc(key->length + 1);
    if (copy == NULL) {
        return false;
    }
    memcpy(copy, key->text, key->length + 1);
    set->items[set->count++] = (Folded){.key = copy, .weight = weight};
    return true;
}

static int compare_folded(const void *left, const void *right) {
    return strcmp(((const Folded *)left)->key, ((const Folded *)right)->key);
}

/* Merges equal keys of a sorted set, summing their weights. */
static void fold_merge(FoldSet *set) {
    size_t kept = 0;
    for (size_t i = 0; i < set->count; i++) {
        if (kept > 0 && strcmp(set->items[kept - 1].key, set->items[i].key) == 0) {
            set->items[kept - 1].weight += set->items[i].weight;
            free(set->items[i].key);
        } else {
            set->items[kept++] = set->items[i];
        }
    }
    set->count = kept;
}

static void fold_free(FoldSet *set) {
    for (size_t i = 0; i < set->count; i++) {
        free(set->items[i].key);
    }
    msrt_free(set->items);
    *set = (FoldSet){0};
}

typedef enum Weight { WEIGHT_SAMPLE, WEIGHT_ALLOCATION, WEIGHT_BYTES } Weight;

/* The folded key of one sample, outermost frame first: callers of a repeated runtime frame are dropped, and so are the
 * runtime frames at the root (the program's start shim: left in, `[runtime]` would look like the total of every
 * stack). An empty key is a sample without frames. */
MS_NODISCARD static bool build_key(const MsTables *tables, const uintptr_t *sample, KeyBuffer *key) {
    const char *labels[MAX_FRAMES];
    char hex[MAX_FRAMES][HEX_LABEL_BYTES];
    size_t count = 0;
    for (size_t i = 0; i < sample[0] && i < MAX_FRAMES; i++) {
        const char *const label = frame_label(tables, sample[1 + i], i == 0, hex[i]);
        const bool repeat = count > 0 && strcmp(labels[count - 1], "[runtime]") == 0 && strcmp(label, "[runtime]") == 0;
        if (!repeat) {
            labels[count++] = label;
        }
    }
    key->length = 0;
    while (count > 0 && strcmp(labels[count - 1], "[runtime]") == 0) {
        count--;
    }
    bool wrote = false;
    for (size_t i = count; i > 0; i--) {
        if (wrote && !key_append(key, ";", 1)) {
            return false;
        }
        const char *const label = labels[i - 1];
        if (!key_append(key, label, strlen(label))) {
            return false;
        }
        wrote = true;
    }
    return true;
}

/* Folds the first `n` samples of `ring` into `stack -> total weight`, sorted by stack. */
static bool fold_ring(const MsTables *tables, const SampleRing *ring, size_t n, Weight weight, uint64_t period,
                      FoldSet *out) {
    KeyBuffer key = {0};
    bool ok = true;
    for (size_t s = 0; ok && s < n; s++) {
        const uintptr_t *const sample = ring->buffer + s * ring->words;
        ok = build_key(tables, sample, &key);
        if (!ok || key.length == 0) {
            continue;
        }
        uint64_t amount = 1;
        if (weight == WEIGHT_ALLOCATION) {
            amount = period;
        } else if (weight == WEIGHT_BYTES) {
            amount = (uint64_t)sample[ALLOC_WORDS - 1] * period;
        }
        ok = fold_add(out, &key, amount);
    }
    msrt_free(key.text);
    if (out->count > 0) {
        qsort(out->items, out->count, sizeof out->items[0], compare_folded);
        fold_merge(out);
    }
    return ok;
}

typedef struct Note {
    const char *name;
    uint64_t value;
} Note;

/* Writes `stack weight` lines, then `# name value` comments. */
static void write_folded(const char *path, const FoldSet *set, const Note *notes, size_t note_count) {
    FILE *const file = fopen(path, "wb");
    if (file == NULL) {
        return;
    }
    for (size_t i = 0; i < set->count; i++) {
        (void)fprintf(file, "%s %llu\n", set->items[i].key, (unsigned long long)set->items[i].weight);
    }
    for (size_t i = 0; i < note_count; i++) {
        (void)fprintf(file, "# %s %llu\n", notes[i].name, (unsigned long long)notes[i].value);
    }
    (void)fclose(file);
}

static uint64_t total_weight(const FoldSet *set) {
    uint64_t total = 0;
    for (size_t i = 0; i < set->count; i++) {
        total += set->items[i].weight;
    }
    return total;
}

static void finish_allocs(const MsTables *tables) {
    const int64_t period = atomic_exchange(&alloc_period, 0);
    if (period == 0 || alloc_ring.buffer == NULL) {
        return;
    }
    size_t n = atomic_load(&alloc_ring.count);
    n = n < MAX_SAMPLES ? n : MAX_SAMPLES;
    FoldSet counts = {0};
    FoldSet bytes = {0};
    const bool folded = fold_ring(tables, &alloc_ring, n, WEIGHT_ALLOCATION, (uint64_t)period, &counts) &&
                        fold_ring(tables, &alloc_ring, n, WEIGHT_BYTES, (uint64_t)period, &bytes);
    if (folded) {
        const Note count_notes[] = {{"period", (uint64_t)period},
                                    {"allocs", total_weight(&counts)},
                                    {"dropped", atomic_load(&alloc_ring.dropped)}};
        write_folded(alloc_path, &counts, count_notes, MS_COUNT_OF(count_notes));
        const size_t path_length = strlen(alloc_path);
        char *const bytes_path = malloc(path_length + sizeof ".bytes");
        if (bytes_path != NULL) {
            memcpy(bytes_path, alloc_path, path_length);
            memcpy(bytes_path + path_length, ".bytes", sizeof ".bytes");
            const Note byte_notes[] = {{"period", (uint64_t)period}, {"bytes", total_weight(&bytes)}};
            write_folded(bytes_path, &bytes, byte_notes, MS_COUNT_OF(byte_notes));
            free(bytes_path);
        }
    }
    fold_free(&counts);
    fold_free(&bytes);
}

#ifndef _WIN32
/* The program's functions as `address size name` lines, the format perf reads for JIT-style symbols. */
static void write_perf_map(void) {
    const MsTables *const tables = ms_frames_tables();
    if (tables == NULL) {
        return;
    }
    char path[PATH_BYTES];
    (void)snprintf(path, sizeof path, "/tmp/perf-%d.map", (int)getpid());
    FILE *const file = fopen(path, "wb");
    if (file == NULL) {
        return;
    }
    for (size_t i = 0; tables->funcs != NULL && i < tables->func_count; i++) {
        const MsFuncEntry *const function = &tables->funcs[i];
        const char *const name = function->name_offset < tables->strings_len
                                     ? (const char *)tables->strings + function->name_offset
                                     : "?";
        (void)fprintf(file, "%llx %x %s\n", (unsigned long long)function->address, function->size, name);
    }
    (void)fclose(file);
}
#endif

/* ---- the entry points ---- */

/* Prepares the allocation profile when MS_PROFILE_ALLOCS names a file. */
static void start_allocs(void) {
    alloc_path = env_path("MS_PROFILE_ALLOCS");
    if (alloc_path == NULL || !ring_open(&alloc_ring)) {
        return;
    }
    atomic_store(&alloc_period, env_int("MS_PROFILE_ALLOC_PERIOD", DEFAULT_ALLOC_PERIOD, 1, INT64_MAX / 2));
}

void ms_profile_start(void) {
    start_allocs();
    time_path = env_path("MS_PROFILE");
    if (time_path == NULL || !ring_open(&time_ring)) {
        return;
    }
#ifndef _WIN32
    const char *const perf_map = getenv("MS_PERF_MAP");
    if (perf_map != NULL && strcmp(perf_map, "1") == 0) {
        write_perf_map();
    }
#endif
    atomic_store(&sampling, true);
    arm_timer(env_int("MS_PROFILE_HZ", DEFAULT_HZ, 1, MAX_HZ));
}

void ms_profile_attach_runtime_thread(void) {
    attach_sampler();
    const int64_t period = atomic_load(&alloc_period);
    if (period != 0) {
        msrt_heap_sample_every(period, (void *)on_alloc_sample);
    }
}

void ms_profile_finish(void) {
    const MsTables *const tables = ms_frames_tables();
    finish_allocs(tables);
    if (!atomic_exchange(&sampling, false)) {
        return;
    }
    disarm_timer();
    size_t n = atomic_load(&time_ring.count);
    n = n < MAX_SAMPLES ? n : MAX_SAMPLES;
    FoldSet folded = {0};
    if (fold_ring(tables, &time_ring, n, WEIGHT_SAMPLE, 1, &folded)) {
        const Note notes[] = {{"dropped", atomic_load(&time_ring.dropped)}};
        write_folded(time_path, &folded, notes, MS_COUNT_OF(notes));
    }
    fold_free(&folded);
}
