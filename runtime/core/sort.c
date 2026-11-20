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
/* One radix pass per byte of an Int. */
#define RADIX_PASSES 8

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
    size_t storage = 0;
    if (!ms_size_mul(bytes, 2, &storage)) {
        static const char message[] = "list size overflow";
        msfault_raise(MS_FAULT_OVERFLOW, (const uint8_t *)message, sizeof message - 1);
    }
    uint8_t *scratch = msrt_alloc(storage == 0 ? 1 : storage);
    __builtin_memcpy(scratch + bytes, v->ptr, bytes);
    SortRollback rollback = {.items = v->ptr, .scratch = scratch, .bytes = bytes};
    const size_t handle = msrt_cleanup_push(restore_and_free, (uint8_t *)&rollback);
    const Comparator comparator = {.call = cmp, .env = env};
    merge_sort(v->ptr, scratch, v->len, d->size, &comparator);
    msrt_cleanup_discard(handle);
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

/* How many keys have each value of each byte, counted for all eight bytes in one scan of the list. */
typedef struct ByteCounts {
    size_t of[RADIX_PASSES][256];
} ByteCounts;

static void count_bytes(const uint8_t *items, size_t count, ByteCounts *counts) {
    for (size_t i = 0; i < count; i++) {
        const uint64_t key = order_key(load_int(items, i));
        for (unsigned pass = 0; pass < RADIX_PASSES; pass++) {
            counts->of[pass][(key >> (pass * 8)) & 0xff]++;
        }
    }
}

/* Turns the counts of one byte into start offsets. False when every key has the same byte, so the pass
 * would change nothing. */
static bool start_offsets(size_t counts[256], size_t total) {
    size_t running = 0;
    for (size_t bucket = 0; bucket < 256; bucket++) {
        if (counts[bucket] == total) {
            return false;
        }
        const size_t bucket_size = counts[bucket];
        counts[bucket] = running;
        running += bucket_size;
    }
    return true;
}

/* One stable pass on byte `pass` of the keys, from `source` to `target`. */
static void scatter(const uint8_t *source, uint8_t *target, size_t count, unsigned pass, size_t offsets[256]) {
    for (size_t i = 0; i < count; i++) {
        const int64_t value = load_int(source, i);
        store_int(target, offsets[(order_key(value) >> (pass * 8)) & 0xff]++, value);
    }
}

static void radix_sort_ints(MsList *list) {
    ByteCounts counts = {0};
    count_bytes(list->ptr, list->len, &counts);
    uint8_t *scratch = msrt_alloc(list->len * sizeof(int64_t));
    uint8_t *from = list->ptr;
    uint8_t *to = scratch;
    for (unsigned pass = 0; pass < RADIX_PASSES; pass++) {
        if (!start_offsets(counts.of[pass], list->len)) {
            continue;
        }
        scatter(from, to, list->len, pass, counts.of[pass]);
        uint8_t *swap = from;
        from = to;
        to = swap;
    }
    if (from != list->ptr) {
        __builtin_memcpy(list->ptr, from, list->len * sizeof(int64_t));
    }
    msrt_free(scratch);
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

void msrt_list_sorted(const MsList *v, const MsTypeDesc *d, MsCompareFn cmp, uint8_t *env, MsList *out) {
    ms_list_clone(v, d, out);
    SortedCopy state = {.copy = out, .d = d};
    const size_t handle = msrt_cleanup_push(drop_copy, (uint8_t *)&state);
    msrt_list_sort_in_place(out, d, cmp, env);
    msrt_cleanup_discard(handle);
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
    const size_t handle = msrt_cleanup_push(drop_copy, (uint8_t *)&state);
    if (out->len >= 2 && differences_overflow(out)) {
        msrt_list_sort_in_place(out, d, cmp, env);
    } else {
        msrt_list_sort_ints(out, desc);
    }
    msrt_cleanup_discard(handle);
}
