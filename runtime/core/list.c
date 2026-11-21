/* Lists: `List[T]` values of three words (buffer, length, capacity) whose elements sit inline, `size` bytes
 * apart, and the natives that read and change them. Ported from crates/ms-rt/src/vec.rs.
 *
 * Every function takes the descriptor of the element type and trusts it. A mutator changes the list in place;
 * the slot of a stored element is consumed (ownership moves into the list); lent arguments are copied.
 * A view (`cap == 0` with a buffer) borrows its elements: nothing frees, drops or grows it in place.
 */
#include "hash.h"
#include "index.h"
#include "list_ops.h"
#include "ms_rt/alloc.h"
#include "ms_rt/list.h"
#include "rt_calls.h"
#include "slot.h"
#include "text.h"

#include <stdatomic.h>

#define FIRST_CAPACITY 4
#define FIRST_BYTE_CAPACITY 32
#define INLINE_COPY_BYTES 64
#define DISTINCT_HASH_THRESHOLD 16

static const MsList empty_list = {0};

/* ---- sizes and faults ---- */

static MS_NORETURN void fault_list_overflow(void) {
    static const char message[] = "list size overflow";
    msfault_raise(MS_FAULT_OVERFLOW, (const uint8_t *)message, sizeof message - 1);
}

static MS_NORETURN void fault_literal(const char *message) {
    msrt_fault((const uint8_t *)message, __builtin_strlen(message));
}

/* count * size of a slot (a zero-sized slot still takes one byte, so the buffer is never zero bytes). */
static size_t buffer_bytes(size_t count, size_t slot_size) {
    size_t bytes = 0;
    if (!ms_size_mul(count, slot_size == 0 ? 1 : slot_size, &bytes)) {
        fault_list_overflow();
    }
    return bytes;
}

static size_t checked_add(size_t a, size_t b) {
    size_t sum = 0;
    if (!ms_size_add(a, b, &sum)) {
        fault_list_overflow();
    }
    return sum;
}

/* How many elements `take` and `drop` split at: a count of zero or below is zero. */
static size_t split_count(int64_t count, size_t len) {
    if (count <= 0) {
        return 0;
    }
    return (uint64_t)count < len ? (size_t)count : len;
}

static MsList view_of(const MsList *list, const MsTypeDesc *d, size_t start, size_t count) {
    return (MsList){.ptr = count == 0 ? NULL : ms_list_at(list, d, start), .len = count, .cap = count};
}

/* ---- construction, growth and lifetime ---- */

void ms_list_reserve(MsList *list, const MsTypeDesc *d, size_t extra) {
    const size_t need = checked_add(list->len, extra);
    if (need <= list->cap) {
        return;
    }
    /* A byte buffer (a string builder) starts at one small-text allocation, not four doublings. */
    size_t capacity = d->size == 1 ? FIRST_BYTE_CAPACITY : FIRST_CAPACITY;
    if (list->cap != 0 && !ms_size_mul(list->cap, 2, &capacity)) {
        fault_list_overflow();
    }
    if (capacity < need) {
        capacity = need;
    }
    const size_t bytes = buffer_bytes(capacity, d->size);
    if (list->cap == 0) { /* empty, or a view: a fresh buffer takes its elements */
        uint8_t *buffer = msrt_alloc(bytes);
        if (list->len != 0) {
            __builtin_memcpy(buffer, list->ptr, list->len * d->size);
        }
        list->ptr = buffer;
    } else {
        list->ptr = msrt_realloc(list->ptr, bytes);
    }
    list->cap = capacity;
}

void ms_list_drop(MsList *list, const MsTypeDesc *d) {
    if (list->ptr == NULL || list->cap == 0) { /* empty, or a view that borrows its elements */
        return;
    }
    if (!ms_desc_drop_is_noop(d)) {
        for (size_t i = 0; i < list->len; i++) {
            ms_slot_drop(d, ms_list_at(list, d, i));
        }
    }
    msrt_free(list->ptr);
    *list = empty_list;
}

/* Copies `count` borrowed slots into the disjoint, uninitialised slots at `dst`, in order. */
static void copy_range(const MsTypeDesc *d, const uint8_t *src, uint8_t *dst, size_t count) {
    if (count == 0) {
        return;
    }
    if (ms_desc_is_plain(d)) {
        if (d->size != 0) {
            __builtin_memcpy(dst, src, count * d->size);
        }
        return;
    }
    for (size_t i = 0; i < count; i++) {
        ms_slot_copy(d, src + i * d->size, dst + i * d->size);
    }
}

/* The counting runtime (MS_ALLOC_STATS) tallies deep copies: [list copies, list bytes, string clones, string
 * bytes]. The exit report and `ms test --counts` read them through msrt_copy_counts. */
#ifdef MS_ALLOC_STATS
static _Atomic uint64_t copy_counts[4];

void msrt_count_copy(int64_t kind, uint64_t bytes) {
    atomic_fetch_add_explicit(&copy_counts[kind * 2], 1, memory_order_relaxed);
    atomic_fetch_add_explicit(&copy_counts[kind * 2 + 1], bytes, memory_order_relaxed);
}

void msrt_copy_counts(uint64_t *out) {
    for (size_t i = 0; i < 4; i++) {
        out[i] = atomic_load_explicit(&copy_counts[i], memory_order_relaxed);
    }
}
#else
void msrt_count_copy(int64_t kind, uint64_t bytes) {
    (void)kind;
    (void)bytes;
}

void msrt_copy_counts(uint64_t *out) {
    for (size_t i = 0; i < 4; i++) {
        out[i] = 0;
    }
}
#endif

void ms_list_clone(const MsList *src, const MsTypeDesc *d, MsList *out) {
    if (src->len == 0) {
        *out = empty_list;
        return;
    }
    msrt_count_copy(0, (uint64_t)src->len * d->size);
    uint8_t *buffer = msrt_alloc(buffer_bytes(src->len, d->size));
    copy_range(d, src->ptr, buffer, src->len);
    *out = (MsList){.ptr = buffer, .len = src->len, .cap = src->len};
}

void ms_bytes_clone(const MsList *src, MsList *out) {
    if (src->len == 0) {
        *out = empty_list;
        return;
    }
    uint8_t *buffer = msrt_alloc(src->len);
    __builtin_memcpy(buffer, src->ptr, src->len);
    *out = (MsList){.ptr = buffer, .len = src->len, .cap = src->len};
}

bool ms_list_eq(const MsList *a, const MsList *b, const MsTypeDesc *d) {
    if (a->len != b->len) {
        return false;
    }
    for (size_t i = 0; i < a->len; i++) {
        if (!ms_slot_eq(d, ms_list_at(a, d, i), ms_list_at(b, d, i))) {
            return false;
        }
    }
    return true;
}

void ms_list_push(MsList *list, const MsTypeDesc *d, const uint8_t *element) {
    if (list->len == list->cap) {
        ms_list_reserve(list, d, 1);
    }
    __builtin_memcpy(ms_list_at(list, d, list->len), element, d->size);
    list->len++;
}

void msrt_list_new(MsList *out) { *out = empty_list; }

void msrt_list_with_capacity(const MsTypeDesc *d, int64_t cap, MsList *out) {
    MsList list = empty_list;
    if (cap > 0) {
        ms_list_reserve(&list, d, (size_t)cap);
    }
    *out = list;
}

void msrt_list_drop(MsList *v, const MsTypeDesc *d) { ms_list_drop(v, d); }

void msrt_list_copy(const MsList *v, const MsTypeDesc *d, MsList *out) { ms_list_clone(v, d, out); }

/* A bitwise copy of `v` in a fresh buffer that owns nothing: the generated sort permutes its slots (moves
 * only), so a comparator that exits early leaves the original list intact and at worst leaks the scratch
 * bytes. Pair it with msrt_list_free_raw; never drop it as a list. */
void msrt_list_shadow(const MsList *v, const MsTypeDesc *d, MsList *out) {
    if (v->len == 0) {
        *out = empty_list;
        return;
    }
    const size_t bytes = buffer_bytes(v->len, d->size);
    uint8_t *buffer = msrt_alloc(bytes);
    __builtin_memcpy(buffer, v->ptr, v->len * d->size);
    *out = (MsList){.ptr = buffer, .len = v->len, .cap = v->len};
}

/* Frees the buffer of a shadow without touching its slots. */
void msrt_list_free_raw(MsList *v) {
    if (v->ptr != NULL) {
        msrt_free(v->ptr);
    }
}

void msrt_list_push(MsList *v, const MsTypeDesc *d, const uint8_t *e) { ms_list_push(v, d, e); }
int64_t msrt_list_length(const MsList *v) { return (int64_t)v->len; }
void msrt_list_append(MsList *v, const MsTypeDesc *d, const uint8_t *e) { ms_list_push(v, d, e); }

void msrt_list_reserve(MsList *v, const MsTypeDesc *d, int64_t extra) {
    ms_list_reserve(v, d, extra > 0 ? (size_t)extra : 0);
}

/* ---- reads ---- */

/* The element at a possibly negative index, borrowed; `default_value` (may be NULL) when out of range. */
const uint8_t *msrt_list_at(const MsList *v, const MsTypeDesc *d, int64_t index, const uint8_t *default_value) {
    size_t position = 0;
    if (ms_resolve_index(v->len, index, &position)) {
        return ms_list_at(v, d, position);
    }
    if (default_value == NULL) {
        msrt_index_fault(index, (int64_t)v->len);
    }
    return default_value;
}

void msrt_list_get(const MsList *v, const MsTypeDesc *d, int64_t index, const uint8_t *default_value, uint8_t *out) {
    ms_slot_copy(d, msrt_list_at(v, d, index, default_value), out);
}

static int64_t load_i64(const uint8_t *slot) {
    int64_t value = 0;
    __builtin_memcpy(&value, slot, sizeof value);
    return value;
}

/* Position of the first `target` among `count` Ints: eight at a time, so the scan vectorizes. */
static bool find_int(const uint8_t *items, size_t count, int64_t target, size_t *out) {
    enum { CHUNK = 8 };
    size_t start = 0;
    for (; start + CHUNK <= count; start += CHUNK) {
        bool hit = false;
        for (size_t k = 0; k < CHUNK; k++) {
            hit |= load_i64(items + (start + k) * sizeof(int64_t)) == target;
        }
        if (hit) {
            break;
        }
    }
    for (size_t i = start; i < count; i++) {
        if (load_i64(items + i * sizeof(int64_t)) == target) {
            *out = i;
            return true;
        }
    }
    return false;
}

static bool index_of(const MsList *list, const MsTypeDesc *d, const uint8_t *probe, size_t *out) {
    if (d->kind == MS_KIND_INT && list->len > 0) {
        return find_int(list->ptr, list->len, load_i64(probe), out);
    }
    for (size_t i = 0; i < list->len; i++) {
        if (ms_slot_eq(d, ms_list_at(list, d, i), probe)) {
            *out = i;
            return true;
        }
    }
    return false;
}

uint8_t msrt_list_index_of(const MsList *v, const MsTypeDesc *d, const uint8_t *probe, int64_t *out) {
    size_t position = 0;
    if (!index_of(v, d, probe, &position)) {
        return 0;
    }
    *out = (int64_t)position;
    return 1;
}

uint8_t msrt_list_last_index_of(const MsList *v, const MsTypeDesc *d, const uint8_t *probe, int64_t *out) {
    for (size_t i = v->len; i > 0; i--) {
        if (ms_slot_eq(d, ms_list_at(v, d, i - 1), probe)) {
            *out = (int64_t)(i - 1);
            return 1;
        }
    }
    return 0;
}

uint8_t msrt_list_contains(const MsList *v, const MsTypeDesc *d, const uint8_t *probe) {
    size_t position = 0;
    return index_of(v, d, probe, &position);
}

/* ---- element mutators ---- */

void msrt_list_insert(MsList *v, const MsTypeDesc *d, int64_t index, const uint8_t *e) {
    size_t position = 0;
    if (!ms_resolve_insert_index(v->len, index, &position)) {
        msrt_list_index_fault(0, index, (int64_t)v->len);
    }
    ms_list_reserve(v, d, 1);
    uint8_t *slot = ms_list_at(v, d, position);
    __builtin_memmove(slot + d->size, slot, (v->len - position) * d->size);
    __builtin_memcpy(slot, e, d->size);
    v->len++;
}

void msrt_list_prepend(MsList *v, const MsTypeDesc *d, const uint8_t *e) { msrt_list_insert(v, d, 0, e); }

/* `insert` of a lent element: the list stores its own copy, and the caller keeps `e`. */
void msrt_list_insert_copy(MsList *v, const MsTypeDesc *d, int64_t index, const uint8_t *e) {
    _Alignas(16) uint8_t scratch[INLINE_COPY_BYTES];
    const bool on_stack = d->size <= sizeof scratch;
    uint8_t *copy = on_stack ? scratch : msrt_alloc(d->size);
    ms_slot_copy(d, e, copy);
    msrt_list_insert(v, d, index, copy);
    if (!on_stack) {
        msrt_free(copy);
    }
}

/* Moves the last element into `out`; 0 when the list is empty. */
uint8_t msrt_list_pop(MsList *v, const MsTypeDesc *d, uint8_t *out) {
    if (v->len == 0) {
        return 0;
    }
    v->len--;
    __builtin_memcpy(out, ms_list_at(v, d, v->len), d->size);
    return 1;
}

/* Replaces the element at `index` with `e` (consumed); the old element is dropped. */
void msrt_list_set(MsList *v, const MsTypeDesc *d, int64_t index, const uint8_t *e) {
    size_t position = 0;
    if (!ms_resolve_index(v->len, index, &position)) {
        msrt_list_index_fault(2, index, (int64_t)v->len);
    }
    uint8_t *slot = ms_list_at(v, d, position);
    ms_slot_drop(d, slot);
    __builtin_memcpy(slot, e, d->size);
}

/* Moves the element at `index` into `out` and stores `e` (consumed) in its place; nothing is copied or dropped. */
void msrt_list_replace(MsList *v, const MsTypeDesc *d, int64_t index, uint8_t *e, uint8_t *out) {
    size_t position = 0;
    if (!ms_resolve_index(v->len, index, &position)) {
        msrt_list_index_fault(4, index, (int64_t)v->len);
    }
    uint8_t *slot = ms_list_at(v, d, position);
    __builtin_memcpy(out, slot, d->size);
    __builtin_memcpy(slot, e, d->size);
}

/* Exchanges two distinct slots of `size` bytes through a small buffer. */
static void swap_slots(uint8_t *a, uint8_t *b, size_t size) {
    uint8_t scratch[INLINE_COPY_BYTES];
    while (size != 0) {
        const size_t step = size < sizeof scratch ? size : sizeof scratch;
        __builtin_memcpy(scratch, a, step);
        __builtin_memcpy(a, b, step);
        __builtin_memcpy(b, scratch, step);
        a += step;
        b += step;
        size -= step;
    }
}

void msrt_list_swap(MsList *v, const MsTypeDesc *d, int64_t i, int64_t j) {
    size_t first = 0;
    size_t second = 0;
    if (!ms_resolve_index(v->len, i, &first)) {
        msrt_list_index_fault(3, i, (int64_t)v->len);
    }
    if (!ms_resolve_index(v->len, j, &second)) {
        msrt_list_index_fault(3, j, (int64_t)v->len);
    }
    if (first != second) {
        swap_slots(ms_list_at(v, d, first), ms_list_at(v, d, second), d->size);
    }
}

void msrt_list_remove(MsList *v, const MsTypeDesc *d, int64_t index) {
    size_t position = 0;
    if (!ms_resolve_index(v->len, index, &position)) {
        msrt_list_index_fault(1, index, (int64_t)v->len);
    }
    uint8_t *slot = ms_list_at(v, d, position);
    ms_slot_drop(d, slot);
    __builtin_memmove(slot, slot + d->size, (v->len - position - 1) * d->size);
    v->len--;
}

/* ---- reversal ---- */

/* Reverses `count` slots whose size is a constant after inlining: the compiler turns the exchange of a
 * one to four word slot into register moves. */
static inline void reverse_slots(uint8_t *items, size_t count, size_t size) {
    size_t front = 0;
    size_t back = count;
    while (front + 1 < back) {
        back--;
        swap_slots(items + front * size, items + back * size, size);
        front++;
    }
}

void msrt_list_reverse(MsList *v, const MsTypeDesc *d) {
    if (v->len < 2) {
        return;
    }
    switch (d->size) {
    case 8:
        reverse_slots(v->ptr, v->len, 8);
        break;
    case 16:
        reverse_slots(v->ptr, v->len, 16);
        break;
    case 24:
        reverse_slots(v->ptr, v->len, 24);
        break;
    case 32:
        reverse_slots(v->ptr, v->len, 32);
        break;
    default:
        reverse_slots(v->ptr, v->len, d->size);
        break;
    }
}

void msrt_list_reversed(const MsList *v, const MsTypeDesc *d, MsList *out) {
    ms_list_clone(v, d, out);
    msrt_list_reverse(out, d);
}

/* The fault of a destructuring pattern whose name count differs from the list's length. */
void msrt_fault_destructure(int64_t names, int64_t elements) {
    MsText text = {0};
    ms_text_add(&text, "destructuring length mismatch; the pattern binds ");
    ms_text_add_i64(&text, names);
    ms_text_add(&text, " names but the list has ");
    ms_text_add_i64(&text, elements);
    ms_text_add(&text, " elements");
    ms_text_fault(&text, MS_FAULT_GENERIC);
}

/* ---- range edits ---- */

static MS_NORETURN void fault_splice_range(const char *what, int64_t found, size_t high) {
    MsText text = {0};
    ms_text_add(&text, "List.splice: ");
    ms_text_add(&text, what);
    ms_text_add(&text, " must be between 0 and ");
    ms_text_add_i64(&text, (int64_t)high);
    ms_text_add(&text, ", found ");
    ms_text_add_i64(&text, found);
    ms_text_fault(&text, MS_FAULT_GENERIC);
}

/* `splice(start, delete_count, replacement)`: the replacement is consumed and its buffer freed. */
void msrt_list_splice(MsList *v, const MsTypeDesc *d, int64_t start, int64_t count, MsList *replacement) {
    const size_t length = v->len;
    if (start < 0 || (uint64_t)start > length) {
        fault_splice_range("start", start, length);
    }
    const size_t from = (size_t)start;
    if (count < 0 || (uint64_t)count > length - from) {
        fault_splice_range("delete_count", count, length - from);
    }
    const size_t removed = (size_t)count;
    for (size_t i = from; i < from + removed; i++) {
        ms_slot_drop(d, ms_list_at(v, d, i));
    }
    const size_t new_len = checked_add(length - removed, replacement->len);
    if (new_len > v->cap) {
        ms_list_reserve(v, d, new_len - length);
    }
    const size_t tail = length - from - removed;
    if (tail != 0) {
        __builtin_memmove(ms_list_at(v, d, from + replacement->len), ms_list_at(v, d, from + removed), tail * d->size);
    }
    if (replacement->len != 0) {
        __builtin_memcpy(ms_list_at(v, d, from), replacement->ptr, replacement->len * d->size);
    }
    v->len = new_len;
    if (replacement->ptr != NULL) {
        msrt_free(replacement->ptr);
    }
    *replacement = empty_list;
}

static MS_NORETURN void fault_bounds(const char *operation, size_t len, int64_t start, int64_t end) {
    MsText text = {0};
    ms_text_add(&text, operation);
    ms_text_add(&text, ": start/end must satisfy 0 <= start <= end <= ");
    ms_text_add_i64(&text, (int64_t)len);
    ms_text_add(&text, "; found start ");
    ms_text_add_i64(&text, start);
    ms_text_add(&text, " and end ");
    ms_text_add_i64(&text, end);
    ms_text_fault(&text, MS_FAULT_GENERIC);
}

static void check_bounds(const char *operation, size_t len, int64_t start, int64_t end) {
    if (start < 0 || end < start || (uint64_t)end > len) {
        fault_bounds(operation, len, start, end);
    }
}

/* `fill(value, start, end)`: `value` is lent and copied into each slot. */
void msrt_list_fill(MsList *v, const MsTypeDesc *d, const uint8_t *value, int64_t start, int64_t end) {
    check_bounds("List.fill", v->len, start, end);
    for (size_t i = (size_t)start; i < (size_t)end; i++) {
        uint8_t *slot = ms_list_at(v, d, i);
        ms_slot_drop(d, slot);
        ms_slot_copy(d, value, slot);
    }
}

static MS_NORETURN void fault_copy_target(size_t len, int64_t target) {
    MsText text = {0};
    ms_text_add(&text, "List.copy_within: target must be between 0 and ");
    ms_text_add_i64(&text, (int64_t)len);
    ms_text_add(&text, ", found ");
    ms_text_add_i64(&text, target);
    ms_text_fault(&text, MS_FAULT_GENERIC);
}

/* Copies `count` slots from `from` over the slots at `to`, which may overlap: the sources are copied
 * first, the overwritten slots dropped, and the copies moved in. */
static void copy_within_owned(MsList *list, const MsTypeDesc *d, size_t to, size_t from, size_t count) {
    MsList scratch = empty_list;
    const MsList source = view_of(list, d, from, count);
    ms_list_clone(&source, d, &scratch);
    for (size_t k = 0; k < count; k++) {
        ms_slot_drop(d, ms_list_at(list, d, to + k));
    }
    __builtin_memcpy(ms_list_at(list, d, to), scratch.ptr, count * d->size);
    msrt_free(scratch.ptr);
}

void msrt_list_copy_within(MsList *v, const MsTypeDesc *d, int64_t target, int64_t start, int64_t end) {
    const size_t length = v->len;
    check_bounds("List.copy_within", length, start, end);
    if (target < 0 || (uint64_t)target > length) {
        fault_copy_target(length, target);
    }
    const size_t to = (size_t)target;
    if (start == end || to == length) {
        return;
    }
    const size_t wanted = (size_t)(end - start);
    const size_t count = wanted < length - to ? wanted : length - to;
    if (ms_desc_is_plain(d)) {
        if (d->size != 0) {
            __builtin_memmove(ms_list_at(v, d, to), ms_list_at(v, d, (size_t)start), count * d->size);
        }
        return;
    }
    copy_within_owned(v, d, to, (size_t)start, count);
}

/* ---- derived lists ---- */

static void store_slice_error(MsStr *err, int64_t start, int64_t end, size_t len) {
    if (err == NULL) {
        return;
    }
    MsText text = {0};
    ms_text_add(&text, "slice(");
    ms_text_add_i64(&text, start);
    ms_text_add(&text, ", ");
    ms_text_add_i64(&text, end);
    ms_text_add(&text, ") of a list with ");
    ms_text_add_i64(&text, (int64_t)len);
    ms_text_add(&text, " items: bounds must satisfy 0 <= start <= end <= length (negative bounds count from the end)");
    ms_text_to_string(&text, err);
}

static void start_error_slot(MsStr *err) {
    if (err != NULL) {
        msrt_string_empty(err);
    }
}

/* `slice(start, end)`: a copy of the elements; the status protocol reports bad bounds in `err`. */
uint8_t msrt_list_slice(const MsList *v, const MsTypeDesc *d, int64_t start, int64_t end, MsList *out, MsStr *err) {
    start_error_slot(err);
    size_t from = 0;
    size_t to = 0;
    if (!ms_resolve_bounds(v->len, start, end, &from, &to)) {
        store_slice_error(err, start, end, v->len);
        return MS_STATUS_OUT_OF_RANGE;
    }
    const MsList range = view_of(v, d, from, to - from);
    ms_list_clone(&range, d, out);
    return MS_STATUS_OK;
}

/* `slice` of a list the caller keeps unchanged while the result is used: the result borrows the elements in
 * place (a view), so nothing is copied. */
uint8_t msrt_list_slice_view(const MsList *v, const MsTypeDesc *d, int64_t start, int64_t end, MsList *out,
                             MsStr *err) {
    start_error_slot(err);
    size_t from = 0;
    size_t to = 0;
    if (!ms_resolve_bounds(v->len, start, end, &from, &to)) {
        store_slice_error(err, start, end, v->len);
        return MS_STATUS_OUT_OF_RANGE;
    }
    const size_t count = to - from;
    *out = count == 0 ? empty_list : (MsList){.ptr = ms_list_at(v, d, from), .len = count, .cap = 0};
    return MS_STATUS_OK;
}

void msrt_list_take(const MsList *v, const MsTypeDesc *d, int64_t count, MsList *out) {
    const MsList head = view_of(v, d, 0, split_count(count, v->len));
    ms_list_clone(&head, d, out);
}

/* `drop(count)`, named `drop_n` because msrt_list_drop releases a value. */
void msrt_list_drop_n(const MsList *v, const MsTypeDesc *d, int64_t count, MsList *out) {
    const size_t skipped = split_count(count, v->len);
    const MsList rest = view_of(v, d, skipped, v->len - skipped);
    ms_list_clone(&rest, d, out);
}

/* How many pieces of `size` elements, starting every `step`, a list of `len` splits into. */
static size_t piece_count(size_t len, size_t size, size_t step, bool short_last) {
    if (short_last) {
        return len / step + (len % step != 0);
    }
    return len >= size ? (len - size) / step + 1 : 0;
}

/* `chunks(size)` and `windows(size)`: lists of copies of `size` consecutive elements, starting every `step`
 * elements. `short_last` keeps a final shorter piece (chunks); otherwise only full pieces are made
 * (windows). `od` describes the outer list's element, a list. */
void msrt_list_pieces(const MsList *v, const MsTypeDesc *d, const MsTypeDesc *od, int64_t size, int64_t step,
                      uint8_t short_last, MsList *out) {
    if (size <= 0) { /* no group of zero or fewer elements exists */
        *out = empty_list;
        return;
    }
    const size_t piece_size = (size_t)size;
    const size_t stride = step > 1 ? (size_t)step : 1;
    MsList result = empty_list;
    const size_t pieces = piece_count(v->len, piece_size, stride, short_last != 0);
    if (pieces != 0) {
        ms_list_reserve(&result, od, pieces);
    }
    for (size_t start = 0; start < v->len && (short_last != 0 || v->len - start >= piece_size); start += stride) {
        const size_t room = v->len - start;
        const MsList range = view_of(v, d, start, piece_size < room ? piece_size : room);
        MsList piece = empty_list;
        ms_list_clone(&range, d, &piece);
        __builtin_memcpy(ms_list_at(&result, od, result.len), &piece, sizeof piece);
        result.len++;
    }
    *out = result;
}

/* The capacity a concatenation keeps: the spare room the copy-then-extend path used to leave. */
static size_t concat_capacity(size_t a_len, size_t b_len, size_t total) {
    if (b_len == 0) {
        return a_len;
    }
    if (a_len == 0) {
        return total > FIRST_CAPACITY ? total : FIRST_CAPACITY;
    }
    size_t doubled = 0;
    if (!ms_size_mul(a_len, 2, &doubled)) {
        fault_list_overflow();
    }
    return doubled > total ? doubled : total;
}

void msrt_list_concat(const MsList *a, const MsList *b, const MsTypeDesc *d, MsList *out) {
    const size_t total = checked_add(a->len, b->len);
    if (total == 0) {
        *out = empty_list;
        return;
    }
    const size_t capacity = concat_capacity(a->len, b->len, total);
    uint8_t *buffer = msrt_alloc(buffer_bytes(capacity, d->size));
    copy_range(d, a->ptr, buffer, a->len);
    copy_range(d, b->ptr, buffer + a->len * d->size, b->len);
    *out = (MsList){.ptr = buffer, .len = total, .cap = capacity};
}

/* `repeated(count)`: the elements `count` times over, in order. Plain elements copy once and double in
 * place, so a long fill is a few bulk copies. */
void msrt_list_repeat(const MsList *v, const MsTypeDesc *d, int64_t count, MsList *out) {
    size_t rounds = count > 0 ? (size_t)count : 0;
    size_t total = 0;
    if (!ms_size_mul(v->len, rounds, &total)) {
        fault_list_overflow();
    }
    if (total == 0) {
        *out = empty_list;
        return;
    }
    uint8_t *buffer = msrt_alloc(buffer_bytes(total, d->size));
    if (ms_desc_is_plain(d)) {
        copy_range(d, v->ptr, buffer, v->len);
        for (size_t done = v->len; done < total;) {
            const size_t step = done < total - done ? done : total - done;
            __builtin_memcpy(buffer + done * d->size, buffer, step * d->size);
            done += step;
        }
    } else {
        for (size_t round = 0; round < rounds; round++) {
            copy_range(d, v->ptr, buffer + round * v->len * d->size, v->len);
        }
    }
    *out = (MsList){.ptr = buffer, .len = total, .cap = total};
}

/* `extend`: appends copies of the elements of `other`, which stays unchanged. */
void msrt_list_extend(MsList *v, const MsTypeDesc *d, const MsList *other) {
    if (other->len == 0) {
        return;
    }
    if (other->len > v->cap - v->len) { /* capacity reserved up front skips the growth path */
        ms_list_reserve(v, d, other->len);
    }
    copy_range(d, other->ptr, ms_list_at(v, d, v->len), other->len);
    v->len += other->len;
}

/* ---- distinct ---- */

/* What a fault or cancellation inside `distinct` must release: the unpublished result and the seen set. */
typedef struct DistinctState {
    MsList *result;
    MsMap *seen;
    const MsTypeDesc *d;
} DistinctState;

static void release_distinct(uint8_t *arg) {
    DistinctState *state = (DistinctState *)__builtin_assume_aligned(arg, _Alignof(DistinctState));
    ms_list_drop(state->result, state->d);
    msrt_map_drop(state->seen, state->d, NULL);
}

static bool seen_before(DistinctState *state, const MsList *result, const uint8_t *element, bool hashed) {
    const MsTypeDesc *d = state->d;
    if (hashed) {
        if (msrt_map_contains(state->seen, d, NULL, element) != 0) {
            return true;
        }
        msrt_set_add_copy(state->seen, d, element);
        return false;
    }
    for (size_t j = 0; j < result->len; j++) {
        if (ms_slot_eq(d, ms_list_at(result, d, j), element)) {
            return true;
        }
    }
    return false;
}

/* `distinct`: keeps the first of equal elements. A hash set decides membership of a long list; the result
 * and the set are released if an equality or hash callback leaves by a jump before the result is published. */
void msrt_list_distinct(const MsList *v, const MsTypeDesc *d, MsList *out) {
    MsList result = empty_list;
    MsMap seen;
    msrt_map_new(&seen);
    DistinctState state = {.result = &result, .seen = &seen, .d = d};
    const bool hashed = ms_desc_hashable(d) && v->len > DISTINCT_HASH_THRESHOLD;
    const size_t handle = msrt_cleanup_push(release_distinct, (uint8_t *)&state);
    for (size_t i = 0; i < v->len; i++) {
        const uint8_t *element = ms_list_at(v, d, i);
        if (seen_before(&state, &result, element, hashed)) {
            continue;
        }
        ms_list_reserve(&result, d, 1);
        ms_slot_copy(d, element, ms_list_at(&result, d, result.len));
        result.len++;
    }
    msrt_cleanup_discard(handle);
    msrt_map_drop(&seen, d, NULL);
    *out = result;
}

/* ---- generators ---- */

/* `keys()`: 0, 1, ..., len-1. */
void msrt_list_keys(const MsList *v, MsList *out) {
    if (v->len == 0) {
        *out = empty_list;
        return;
    }
    uint8_t *buffer = msrt_alloc(buffer_bytes(v->len, sizeof(int64_t)));
    for (size_t i = 0; i < v->len; i++) {
        const int64_t key = (int64_t)i;
        __builtin_memcpy(buffer + i * sizeof key, &key, sizeof key);
    }
    *out = (MsList){.ptr = buffer, .len = v->len, .cap = v->len};
}

/* Stores `count` Ints, the first `first` and each `step` after the last, wrapping like two's complement. */
static void fill_ints(uint8_t *buffer, size_t count, int64_t first, int64_t step) {
    uint64_t value = (uint64_t)first;
    for (size_t i = 0; i < count; i++) {
        __builtin_memcpy(buffer + i * sizeof value, &value, sizeof value);
        value += (uint64_t)step;
    }
}

void msrt_list_range(int64_t start, int64_t end, MsList *out) {
    if (end <= start) {
        *out = empty_list;
        return;
    }
    const uint64_t count = (uint64_t)end - (uint64_t)start; /* exact: the difference of two Ints fits */
    if (count > MS_LIST_MAX_ITEMS) {
        fault_literal("range: more than 268435456 items; iterate with 'for index in start..end' directly or "
                      "bound the list with range_by(max_items:)");
    }
    uint8_t *buffer = msrt_alloc(buffer_bytes((size_t)count, sizeof(int64_t)));
    fill_ints(buffer, (size_t)count, start, 1);
    *out = (MsList){.ptr = buffer, .len = (size_t)count, .cap = (size_t)count};
}

/* The distance covered and the step size of a range_by, or false when it covers nothing. */
static bool range_extent(int64_t start, int64_t end, int64_t step, uint64_t *span, uint64_t *size) {
    if (step > 0 && start < end) {
        *span = (uint64_t)end - (uint64_t)start;
        *size = (uint64_t)step;
        return true;
    }
    if (step < 0 && start > end) {
        *span = (uint64_t)start - (uint64_t)end;
        *size = (uint64_t)0 - (uint64_t)step;
        return true;
    }
    return false;
}

uint8_t msrt_list_range_by(int64_t start, int64_t end, int64_t step, uint8_t has_max, int64_t max, MsList *out) {
    const int64_t requested = has_max != 0 ? max : INT64_MAX;
    if (step == 0 || requested < 0) {
        return MS_STATUS_INVALID_INPUT;
    }
    const uint64_t limit = (uint64_t)requested < MS_LIST_MAX_ITEMS ? (uint64_t)requested : MS_LIST_MAX_ITEMS;
    uint64_t span = 0;
    uint64_t size = 1;
    if (!range_extent(start, end, step, &span, &size)) {
        *out = empty_list;
        return MS_STATUS_OK;
    }
    const uint64_t count = (span - 1) / size + 1;
    if (count > limit) {
        return MS_STATUS_LIMIT_EXCEEDED;
    }
    uint8_t *buffer = msrt_alloc(buffer_bytes((size_t)count, sizeof(int64_t)));
    fill_ints(buffer, (size_t)count, start, step);
    *out = (MsList){.ptr = buffer, .len = (size_t)count, .cap = (size_t)count};
    return MS_STATUS_OK;
}

/* `to_set`: a set of copies of the elements. */
void msrt_list_to_set(const MsList *v, const MsTypeDesc *d, MsMap *out) {
    MsMap set;
    msrt_map_new(&set);
    for (size_t i = 0; i < v->len; i++) {
        msrt_set_add_copy(&set, d, ms_list_at(v, d, i));
    }
    *out = set;
}

int64_t msrt_hash_list(const MsList *v, const MsTypeDesc *d) {
    uint64_t hash = v->len;
    for (size_t i = 0; i < v->len; i++) {
        hash = ms_hash_combine(hash, ms_slot_hash(d, ms_list_at(v, d, i)));
    }
    return (int64_t)hash;
}
