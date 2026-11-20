/* Sorting lists: a stable merge sort by a comparator closure, and a radix sort for Ints. Ported from
 * crates/ms-rt/src/vec.rs.
 *
 * A comparator is program code and can fault or be cancelled, which leaves by a jump and skips this code.
 * So a sort that moves slots through scratch memory registers a cleanup that puts the list back as it was
 * and frees the scratch, and a sort of a copy registers one that drops the unpublished copy.
 */
#include "list_ops.h"
#include "ms_rt/alloc.h"
#include "ms_rt/list.h"
#include "rt_calls.h"
#include "slot.h"

/* Runs of at most this many slots are insertion sorted. */
#define INSERTION_LIMIT 12
/* Int lists up to this long are insertion sorted; longer ones are radix sorted. */
#define RADIX_THRESHOLD 64
/* The digit of a counting pass is a byte. */
#define RADIX_BITS 8U
#define RADIX_BUCKETS ((size_t)1 << RADIX_BITS)

/* ---- merge sort of slots ---- */

typedef struct Comparator {
    MsCompareFn call;
    uint8_t *env;
} Comparator;

static bool less(const Comparator *cmp, const uint8_t *a, const uint8_t *b) {
    return cmp->call(cmp->env, a, b) < 0;
}

/* Stable insertion sort of `count` slots, holding the slot being placed in `spare`. */
static void insertion_sort(uint8_t *items, uint8_t *spare, size_t count, size_t size, const Comparator *cmp) {
    for (size_t i = 1; i < count; i++) {
        __builtin_memcpy(spare, items + i * size, size);
        size_t j = i;
        while (j > 0 && less(cmp, spare, items + (j - 1) * size)) {
            __builtin_memcpy(items + j * size, items + (j - 1) * size, size);
            j--;
        }
        __builtin_memcpy(items + j * size, spare, size);
    }
}

/* Merges the sorted halves items[0..mid) and items[mid..count) from both ends at once: two independent
 * chains hide the load-to-compare latency of a single merge. Every slot is consumed exactly once whatever
 * the comparator answers (each step takes from a cursor range that is still non-empty), so a comparator
 * that is not a total order only gives a poor order. `buf` holds `count` slots. */
static void merge_halves(uint8_t *items, uint8_t *buf, size_t count, size_t mid, size_t size, const Comparator *cmp) {
    __builtin_memcpy(buf, items, count * size);
    size_t left = 0;
    size_t left_end = mid;
    size_t right = mid;
    size_t right_end = count;
    for (size_t k = 0; k < count / 2; k++) {
        const bool take_right = left == left_end || (right < right_end && less(cmp, buf + right * size, buf + left * size));
        __builtin_memcpy(items + k * size, buf + (take_right ? right : left) * size, size);
        right += take_right;
        left += !take_right;
        const bool take_left =
            right_end == right || (left < left_end && less(cmp, buf + (right_end - 1) * size, buf + (left_end - 1) * size));
        __builtin_memcpy(items + (count - 1 - k) * size, buf + (take_left ? left_end - 1 : right_end - 1) * size, size);
        left_end -= take_left;
        right_end -= !take_left;
    }
    if (count % 2 == 1) {
        __builtin_memcpy(items + (count / 2) * size, buf + (left < left_end ? left : right) * size, size);
    }
}

static void merge_sort(uint8_t *items, uint8_t *buf, size_t count, size_t size, const Comparator *cmp) {
    if (count <= INSERTION_LIMIT) {
        insertion_sort(items, buf, count, size, cmp);
        return;
    }
    const size_t mid = count / 2;
    merge_sort(items, buf, mid, size, cmp);
    merge_sort(items + mid * size, buf + mid * size, count - mid, size, cmp);
    if (!less(cmp, items + mid * size, items + (mid - 1) * size)) { /* already in order */
        return;
    }
    merge_halves(items, buf, count, mid, size, cmp);
}

/* ---- the sort with its rollback ---- */

/* What a jump out of the comparator must undo: the list's slots go back to their original order (merging
 * moves slots through scratch, so mid-sort a slot can exist twice and another not at all) and the scratch
 * is freed. */
typedef struct SortRollback {
    uint8_t *items;
    uint8_t *scratch; /* `bytes` of merge space, then `bytes` of the original slots */
    size_t bytes;
} SortRollback;

static void restore_and_free(uint8_t *arg) {
    SortRollback *rollback = (SortRollback *)__builtin_assume_aligned(arg, _Alignof(SortRollback));
    __builtin_memcpy(rollback->items, rollback->scratch + rollback->bytes, rollback->bytes);
    msrt_free(rollback->scratch);
}

void msrt_list_sort_in_place(MsList *v, const MsTypeDesc *d, MsCompareFn cmp, uint8_t *env) {
    if (v->len < 2) {
        return;
    }
    const size_t bytes = v->len * d->size;
    /* The merge keeps a snapshot of the original slots only when a comparator that faults or is cancelled can
     * leave through a guard or a cleanup, which then needs a valid list back. */
    const bool rollback = msrt_rollback_needed() != 0;
    size_t storage = bytes;
    if (rollback && !ms_size_mul(bytes, 2, &storage)) {
        static const char message[] = "list size overflow";
        msfault_raise(MS_FAULT_OVERFLOW, (const uint8_t *)message, sizeof message - 1);
    }
    uint8_t *scratch = msrt_alloc(storage == 0 ? 1 : storage);
    SortRollback state = {.items = v->ptr, .scratch = scratch, .bytes = bytes};
    size_t handle = 0;
    if (rollback) {
        __builtin_memcpy(scratch + bytes, v->ptr, bytes);
        handle = msrt_cleanup_push(restore_and_free, (uint8_t *)&state);
    }
    const Comparator comparator = {.call = cmp, .env = env};
    merge_sort(v->ptr, scratch, v->len, d->size, &comparator);
    if (rollback) {
        msrt_cleanup_discard(handle);
    }
    msrt_free(scratch);
}

/* ---- Int lists ---- */

static int64_t load_int(const uint8_t *items, size_t index) {
    int64_t value = 0;
    __builtin_memcpy(&value, items + index * sizeof value, sizeof value);
    return value;
}

static void store_int(uint8_t *items, size_t index, int64_t value) {
    __builtin_memcpy(items + index * sizeof value, &value, sizeof value);
}

static void insertion_sort_ints(uint8_t *items, size_t count) {
    for (size_t i = 1; i < count; i++) {
        const int64_t held = load_int(items, i);
        size_t j = i;
        while (j > 0 && load_int(items, j - 1) > held) {
            store_int(items, j, load_int(items, j - 1));
            j--;
        }
        store_int(items, j, held);
    }
}

/* The key whose unsigned order is the signed order of `value`. */
static uint64_t order_key(int64_t value) { return (uint64_t)value ^ ((uint64_t)1 << 63); }

/* Sorts the first `count` Ints of the 8-aligned `items` by their order keys' bits `low` to `high` (the other
 * bits are equal in all of them), by one stable counting pass per byte of those bits, from `items` to `spare`
 * and back. Returns whichever of the two holds the result. A byte that is the same in every key costs only
 * its count. */
static int64_t *lsd_sort(int64_t *items, int64_t *spare, size_t count, unsigned low, unsigned high) {
    int64_t *from = items;
    int64_t *to = spare;
    for (unsigned shift = low; shift <= high; shift += RADIX_BITS) {
        const unsigned width = high - shift + 1 < RADIX_BITS ? high - shift + 1 : RADIX_BITS;
        const uint64_t mask = ((uint64_t)1 << width) - 1;
        size_t offsets[RADIX_BUCKETS] = {0};
        for (size_t i = 0; i < count; i++) {
            offsets[(order_key(from[i]) >> shift) & mask]++;
        }
        size_t running = 0;
        bool varies = true;
        for (size_t bucket = 0; bucket <= mask; bucket++) {
            varies = varies && offsets[bucket] != count;
            const size_t bucket_size = offsets[bucket];
            offsets[bucket] = running;
            running += bucket_size;
        }
        if (!varies) {
            continue;
        }
        for (size_t i = 0; i < count; i++) {
            const int64_t value = from[i];
            to[offsets[(order_key(value) >> shift) & mask]++] = value;
        }
        int64_t *swap = from;
        from = to;
        to = swap;
    }
    return from;
}

/* The bits in which the order keys of the Ints differ: the lowest and highest. False when they are all equal. */
static bool varying_bits(const int64_t *items, size_t count, unsigned *low, unsigned *high) {
    uint64_t any = 0;
    uint64_t all = ~(uint64_t)0;
    for (size_t i = 0; i < count; i++) {
        const uint64_t key = order_key(items[i]);
        any |= key;
        all &= key;
    }
    const uint64_t differ = any ^ all;
    if (differ == 0) {
        return false;
    }
    *low = (unsigned)__builtin_ctzll(differ);
    *high = 63U - (unsigned)__builtin_clzll(differ);
    return true;
}

/* A list of this many Ints or fewer is cheaper to sort in place with no first partition. */
/* Ints that sort without a heap buffer (16 KiB of stack). */
#define STACK_SPARE_ITEMS ((size_t)2048)
#define PARTITION_MIN ((size_t)1 << 13)

/* Sorts a long list by one partition on its top byte, then each part (a few thousand Ints, which stay in
 * cache) by counting passes on the bits below: one pass over memory instead of a pass per byte. */
static void partition_sort_ints(int64_t *items, int64_t *spare, size_t count, unsigned low, unsigned high) {
    const unsigned shift = high - (RADIX_BITS - 1);
    size_t starts[RADIX_BUCKETS + 1] = {0};
    for (size_t i = 0; i < count; i++) {
        starts[((order_key(items[i]) >> shift) & (RADIX_BUCKETS - 1)) + 1]++;
    }
    for (size_t bucket = 0; bucket < RADIX_BUCKETS; bucket++) {
        starts[bucket + 1] += starts[bucket];
    }
    size_t next[RADIX_BUCKETS];
    __builtin_memcpy(next, starts, sizeof next);
    for (size_t i = 0; i < count; i++) {
        const int64_t value = items[i];
        spare[next[(order_key(value) >> shift) & (RADIX_BUCKETS - 1)]++] = value;
    }
    for (size_t bucket = 0; bucket < RADIX_BUCKETS; bucket++) {
        const size_t start = starts[bucket];
        const size_t size = starts[bucket + 1] - start;
        int64_t *sorted = spare + start;
        if (size > 1 && shift > low) {
            sorted = lsd_sort(spare + start, items + start, size, low, shift - 1);
        }
        if (sorted != items + start) {
            __builtin_memcpy(items + start, sorted, size * sizeof(int64_t));
        }
    }
}

static void radix_sort_ints(MsList *list) {
    int64_t *items = (int64_t *)__builtin_assume_aligned(list->ptr, _Alignof(int64_t));
    unsigned low = 0;
    unsigned high = 0;
    if (!varying_bits(items, list->len, &low, &high)) {
        return;
    }
    /* A short list sorts in a stack buffer: no allocation, and nothing to unwind if the run is cancelled. */
    int64_t stack_spare[STACK_SPARE_ITEMS];
    const bool on_stack = list->len <= STACK_SPARE_ITEMS;
    int64_t *spare = on_stack ? stack_spare
                              : (int64_t *)__builtin_assume_aligned(msrt_alloc(list->len * sizeof(int64_t)), _Alignof(int64_t));
    if (list->len >= PARTITION_MIN && high - low >= RADIX_BITS * 2) {
        partition_sort_ints(items, spare, list->len, low, high);
    } else {
        int64_t *sorted = lsd_sort(items, spare, list->len, low, high);
        if (sorted != items) {
            __builtin_memcpy(items, sorted, list->len * sizeof(int64_t));
        }
    }
    if (!on_stack) {
        msrt_free(spare);
    }
}

static void reverse_ints(MsList *list) {
    for (size_t front = 0, back = list->len; front + 1 < back; front++) {
        back--;
        const int64_t held = load_int(list->ptr, front);
        store_int(list->ptr, front, load_int(list->ptr, back));
        store_int(list->ptr, back, held);
    }
}

/* Sorts a list of Ints in place, ascending or (when `desc` is not zero) descending. Equal Ints are
 * indistinguishable, so an unstable sort gives the same list as a stable one. */
void msrt_list_sort_ints(MsList *v, int64_t desc) {
    if (v->len < 2) {
        return;
    }
    if (v->len <= RADIX_THRESHOLD) {
        insertion_sort_ints(v->ptr, v->len);
    } else {
        radix_sort_ints(v);
    }
    if (desc != 0) {
        reverse_ints(v);
    }
}

/* ---- sorted copies ---- */

/* A sorted copy is not published until sorting returns: a jump out of the sort drops the copy. */
typedef struct SortedCopy {
    MsList *copy;
    const MsTypeDesc *d;
} SortedCopy;

static void drop_copy(uint8_t *arg) {
    SortedCopy *state = (SortedCopy *)__builtin_assume_aligned(arg, _Alignof(SortedCopy));
    ms_list_drop(state->copy, state->d);
}

/* Registers the cleanup that drops the unpublished copy, only when a jump can leave the sort (no guard or cleanup
 * is open: nothing to unwind to, so no handle). */
static size_t guard_copy(SortedCopy *state) {
    return msrt_rollback_needed() != 0 ? msrt_cleanup_push(drop_copy, (uint8_t *)state) : 0;
}

static void unguard_copy(size_t handle) {
    if (handle != 0) {
        msrt_cleanup_discard(handle);
    }
}

void msrt_list_sorted(const MsList *v, const MsTypeDesc *d, MsCompareFn cmp, uint8_t *env, MsList *out) {
    ms_list_clone(v, d, out);
    SortedCopy state = {.copy = out, .d = d};
    const size_t handle = guard_copy(&state);
    msrt_list_sort_in_place(out, d, cmp, env);
    unguard_copy(handle);
}

/* Whether hi - lo overflows an Int for the extremes of the list: then some pair differs by more than an
 * Int holds, and the comparator must run as written. */
static bool differences_overflow(const MsList *list) {
    int64_t lowest = INT64_MAX;
    int64_t highest = INT64_MIN;
    for (size_t i = 0; i < list->len; i++) {
        const int64_t value = load_int(list->ptr, i);
        lowest = value < lowest ? value : lowest;
        highest = value > highest ? value : highest;
    }
    int64_t spread = 0;
    return __builtin_sub_overflow(highest, lowest, &spread);
}

/* `sorted` over Ints by a comparator that returns `left - right` (or `right - left` when `desc` is not zero).
 * When no two elements differ by more than an Int holds, every difference has the sign of the integer order,
 * so this is the integer sort. Otherwise the comparator runs as written, faulting where a subtraction
 * overflows. */
void msrt_list_sorted_by_difference(const MsList *v, const MsTypeDesc *d, MsCompareFn cmp, uint8_t *env, int64_t desc,
                                    MsList *out) {
    ms_list_clone(v, d, out);
    SortedCopy state = {.copy = out, .d = d};
    const size_t handle = guard_copy(&state);
    if (out->len >= 2 && differences_overflow(out)) {
        msrt_list_sort_in_place(out, d, cmp, env);
    } else {
        msrt_list_sort_ints(out, desc);
    }
    unguard_copy(handle);
}
