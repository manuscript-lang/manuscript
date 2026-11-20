/* The natives programs call on maps and sets (ms_rt/map.h). The table itself is in map.c. Ported from
 * crates/ms-rt/src/map.rs. */
#include "ms_rt/map.h"

#include "map_table.h"
#include "rt_calls.h"

/* ---- Fixed shapes ----
 *
 * Int and String keys over 8-byte values, and Int sets, are most maps in practice. Their layout is a
 * constant, and the key kind is known at the call site, so a probe needs no descriptor.
 */

static inline MapLayout int_map_layout(void) {
    return (MapLayout){.key_offset = 8, .value_offset = 16, .stride = 24, .key_size = 8, .value_size = 8};
}

static inline MapLayout str_map_layout(void) {
    return (MapLayout){.key_offset = 8, .value_offset = 24, .stride = 32, .key_size = 16, .value_size = 8};
}

static inline MapLayout int_set_layout(void) {
    return (MapLayout){.key_offset = 8, .value_offset = 16, .stride = 16, .key_size = 8, .value_size = 0};
}

/* The entry holding `key`, or NULL. */
static inline MS_ALWAYS_INLINE const uint8_t *find_fixed(const MapKeyOps *ops, const MsMap *m, const MapLayout *l,
                                                  const uint8_t *key) {
    if (m->len == 0) {
        return NULL;
    }
    const uint64_t hash = ms_map_hash(ops, NULL, key);
    const size_t number = ms_map_find(ops, m, NULL, l, key, hash);
    return number == MS_MAP_NO_ENTRY ? NULL : ms_map_entry(m, l, number);
}

const uint8_t *msrt_map_get_ptr_w8(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key) {
    (void)kd;
    (void)vd;
    const MapLayout l = int_map_layout();
    const uint8_t *entry = find_fixed(&ms_int_keys, m, &l, key);
    return entry == NULL ? NULL : entry + l.value_offset;
}

uint8_t msrt_map_contains_w8(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key) {
    (void)kd;
    (void)vd;
    const MapLayout l = int_map_layout();
    return find_fixed(&ms_int_keys, m, &l, key) != NULL;
}

uint8_t msrt_map_get_w8(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key, uint8_t *out) {
    const uint8_t *value = msrt_map_get_ptr_w8(m, kd, vd, key);
    if (value == NULL) {
        return 0;
    }
    __builtin_memcpy(out, value, 8);
    return 1;
}

const uint8_t *msrt_map_get_ptr_sw8(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key) {
    (void)kd;
    (void)vd;
    const MapLayout l = str_map_layout();
    const uint8_t *entry = find_fixed(&ms_str_keys, m, &l, key);
    return entry == NULL ? NULL : entry + l.value_offset;
}

uint8_t msrt_map_contains_sw8(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key) {
    (void)kd;
    (void)vd;
    const MapLayout l = str_map_layout();
    return find_fixed(&ms_str_keys, m, &l, key) != NULL;
}

uint8_t msrt_map_get_sw8(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key, uint8_t *out) {
    const uint8_t *value = msrt_map_get_ptr_sw8(m, kd, vd, key);
    if (value == NULL) {
        return 0;
    }
    __builtin_memcpy(out, value, 8);
    return 1;
}

uint8_t msrt_set_contains_w(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key) {
    (void)kd;
    (void)vd;
    const MapLayout l = int_set_layout();
    return find_fixed(&ms_int_keys, m, &l, key) != NULL;
}

/* Adds an entry for a key known to be absent, with an 8-byte value. */
static void append_word(MsMap *m, const MapLayout *l, uint64_t hash, const uint8_t *key, const uint8_t *val) {
    uint8_t *entry = ms_map_next_entry(m, l);
    ms_map_store_hash(entry, hash);
    ms_map_copy_slot(entry + l->key_offset, key, l->key_size);
    ms_map_copy_slot(entry + l->value_offset, val, l->value_size);
    ms_map_publish(m, hash);
}

/* `add` for an Int (key_size 8) or String (16) key and a plain 8-byte value: the layout is fixed and a
 * replaced value needs no drop. */
static inline MS_ALWAYS_INLINE void add_word(const MapKeyOps *ops, bool key_is_string, MsMap *m, uint8_t *key, const uint8_t *val,
                                      size_t key_size) {
    const MapLayout l = {.key_offset = 8, .value_offset = 8 + key_size, .stride = 16 + key_size, .key_size = key_size, .value_size = 8};
    const uint64_t hash = ms_map_hash(ops, NULL, key);
    const size_t number = ms_map_find(ops, m, NULL, &l, key, hash);
    if (number == MS_MAP_NO_ENTRY) {
        append_word(m, &l, hash, key, val);
        return;
    }
    if (key_is_string) {
        ms_str_release(key_str(key));
    }
    ms_map_copy_slot(ms_map_entry(m, &l, number) + l.value_offset, val, 8);
}

void msrt_map_add_w8(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, uint8_t *key, uint8_t *val) {
    if (m->desc != NULL) { /* a map stamped with its module's key behaviour keeps the general path */
        msrt_map_add(m, kd, vd, key, val);
        return;
    }
    add_word(&ms_int_keys, false, m, key, val, 8);
}

void msrt_map_add_sw8(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, uint8_t *key, uint8_t *val) {
    if (m->desc != NULL) {
        msrt_map_add(m, kd, vd, key, val);
        return;
    }
    add_word(&ms_str_keys, true, m, key, val, sizeof(MsStr));
}

void msrt_set_add_copy_w(MsMap *m, const MsTypeDesc *kd, const uint8_t *key) {
    if (m->desc != NULL) {
        msrt_set_add_copy(m, kd, key);
        return;
    }
    const MapLayout l = int_set_layout();
    const uint64_t hash = ms_map_hash(&ms_int_keys, NULL, key);
    if (ms_map_find(&ms_int_keys, m, NULL, &l, key, hash) == MS_MAP_NO_ENTRY) {
        uint8_t *entry = ms_map_next_entry(m, &l);
        ms_map_store_hash(entry, hash);
        __builtin_memcpy(entry + l.key_offset, key, l.key_size);
        ms_map_publish(m, hash);
    }
}

/* ---- Lifecycle and size ---- */

void msrt_map_new(MsMap *out) { *out = (MsMap){0}; }

/* Records creator evidence only for an unstamped collection: a copy or derived collection keeps the creator
 * of the one it came from. `kd` and its nested descriptors and callbacks must be static. */
void msrt_map_stamp(MsMap *m, const MsTypeDesc *kd) {
    if (m->desc == NULL) {
        m->desc = kd;
    }
}

void msrt_map_drop(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd) {
    ms_map_drop(m, ms_map_key_desc(m, kd), vd);
}

void msrt_map_clear(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd) {
    ms_map_drop(m, ms_map_key_desc(m, kd), vd);
}

void msrt_map_copy(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, MsMap *out) {
    ms_map_clone(m, ms_map_key_desc(m, kd), vd, out);
}

void msrt_map_reserve(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, int64_t n) {
    if (n <= 0) {
        return;
    }
    const MapLayout l = ms_map_layout(ms_map_key_desc(m, kd), vd);
    ms_map_reserve(m, &l, (size_t)n);
}

int64_t msrt_map_length(const MsMap *m) { return (int64_t)m->len; }

int64_t msrt_map_slot_count(const MsMap *m) { return (int64_t)m->used; }

/* Borrowed pointers to the key and value of entry `i`; 0 for a hole. */
uint8_t msrt_map_entry_ptrs(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, int64_t i,
                            const uint8_t **key_out, const uint8_t **val_out) {
    if (i < 0 || (uint64_t)i >= m->used) {
        return 0;
    }
    const MapLayout l = ms_map_layout(ms_map_key_desc(m, kd), vd);
    const uint8_t *entry = ms_map_entry(m, &l, (size_t)i);
    if (!ms_map_entry_is_live(entry)) {
        return 0;
    }
    *key_out = entry + l.key_offset;
    if (val_out != NULL) {
        *val_out = entry + l.value_offset;
    }
    return 1;
}

/* ---- Adding ---- */

void msrt_map_add(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, uint8_t *key, uint8_t *val) {
    ms_map_insert(m, ms_map_key_desc(m, kd), vd, key, val);
}

/* Stores only when the key is absent; both are consumed either way. */
void msrt_map_add_default(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, uint8_t *key, uint8_t *val) {
    kd = ms_map_key_desc(m, kd);
    if (ms_map_has(m, kd, vd, key)) {
        ms_slot_drop(kd, key);
        if (vd != NULL) {
            ms_slot_drop(vd, val);
        }
        return;
    }
    ms_map_insert(m, kd, vd, key, val);
}

void msrt_map_remove(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key) {
    (void)ms_map_remove(m, ms_map_key_desc(m, kd), vd, key);
}

/* Appends an entry for a borrowed key: the entry owns a copy of the key, and `val` is moved in. Returns the
 * value slot. */
static uint8_t *append_lent(MsMap *m, const MapLayout *l, uint64_t hash, const MsTypeDesc *kd, const uint8_t *key,
                            const uint8_t *val) {
    uint8_t *entry = ms_map_next_entry(m, l);
    ms_map_store_hash(entry, hash);
    ms_slot_copy(kd, key, entry + l->key_offset);
    ms_map_copy_slot(entry + l->value_offset, val, l->value_size);
    ms_map_publish(m, hash);
    return entry + l->value_offset;
}

/* The value slot of a borrowed `key`, appending the entry with `default_value` when it is absent. The default
 * is consumed either way: stored when the entry is new, dropped when it exists. One hash and probe serve a
 * read-modify-write: the caller reads and writes through the returned pointer before the map is used again. */
uint8_t *msrt_map_slot_lent(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key, uint8_t *default_value) {
    kd = ms_map_key_desc(m, kd);
    const MapLayout l = ms_map_layout(kd, vd);
    const MapProbe probe = ms_map_probe(m, kd, &l, key);
    if (probe.entry == MS_MAP_NO_ENTRY) {
        return append_lent(m, &l, probe.hash, kd, key, default_value);
    }
    ms_slot_drop(vd, default_value);
    return ms_map_entry(m, &l, probe.entry) + l.value_offset;
}

/* `add(key, value)` with a borrowed key: it is copied only when the entry is absent, so replacing the value of
 * an existing key allocates nothing. */
void msrt_map_add_lent(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key, uint8_t *val) {
    kd = ms_map_key_desc(m, kd);
    const MapLayout l = ms_map_layout(kd, vd);
    const MapProbe probe = ms_map_probe(m, kd, &l, key);
    if (probe.entry == MS_MAP_NO_ENTRY) {
        (void)append_lent(m, &l, probe.hash, kd, key, val);
        return;
    }
    uint8_t *value = ms_map_entry(m, &l, probe.entry) + l.value_offset;
    ms_slot_drop(vd, value);
    ms_map_copy_slot(value, val, l.value_size);
}

/* `add_default(key, value)` with a borrowed key: nothing is copied or stored when the entry exists. */
void msrt_map_add_default_lent(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key, uint8_t *val) {
    kd = ms_map_key_desc(m, kd);
    const MapLayout l = ms_map_layout(kd, vd);
    const MapProbe probe = ms_map_probe(m, kd, &l, key);
    if (probe.entry == MS_MAP_NO_ENTRY) {
        (void)append_lent(m, &l, probe.hash, kd, key, val);
        return;
    }
    ms_slot_drop(vd, val);
}

/* ---- Reading ---- */

uint8_t msrt_map_contains(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key) {
    return ms_map_has(m, ms_map_key_desc(m, kd), vd, key);
}

const uint8_t *msrt_map_get_ptr(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key) {
    if (m->len == 0) {
        return NULL;
    }
    kd = ms_map_key_desc(m, kd);
    const MapLayout l = ms_map_layout(kd, vd);
    const MapProbe probe = ms_map_probe(m, kd, &l, key);
    return probe.entry == MS_MAP_NO_ENTRY ? NULL : ms_map_entry(m, &l, probe.entry) + l.value_offset;
}

uint8_t msrt_map_get(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key, uint8_t *out) {
    const uint8_t *value = msrt_map_get_ptr(m, kd, vd, key);
    if (value == NULL) {
        return 0;
    }
    ms_slot_copy(vd, value, out);
    return 1;
}

/* ---- keys() and values() ---- */

/* A list of copies of the keys (or the values) of `m`. */
static void collect(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, bool keys, MsList *out) {
    const MapLayout l = ms_map_layout(kd, vd);
    const MsTypeDesc *d = keys || vd == NULL ? kd : vd;
    const size_t offset = keys ? l.key_offset : l.value_offset;
    if (m->len == 0) {
        *out = (MsList){0};
        return;
    }
    size_t bytes = 0;
    if (!ms_size_mul(m->len, d->size == 0 ? 1 : d->size, &bytes)) {
        static const char message[] = "map size overflow";
        msfault_raise(MS_FAULT_OVERFLOW, (const uint8_t *)message, sizeof message - 1);
    }
    MsList list = {.ptr = msrt_alloc(bytes), .len = 0, .cap = m->len};
    for (size_t number = 0; number < m->used; number++) {
        const uint8_t *entry = ms_map_entry(m, &l, number);
        if (ms_map_entry_is_live(entry)) {
            ms_slot_copy(d, entry + offset, list.ptr + list.len * d->size);
            list.len++;
        }
    }
    *out = list;
}

/* A string of at most MS_STR_INLINE_MAX bytes keeps them in its own two words. */
static void make_inline_string(const uint8_t *bytes, size_t len, MsStr *out) {
    uint8_t words[16] = {0};
    __builtin_memcpy(words, bytes, len);
    uint64_t high = 0;
    __builtin_memcpy(&out->ptr_word, words, sizeof out->ptr_word);
    __builtin_memcpy(&high, words + 8, sizeof high);
    out->tagged = high | (UINT64_C(1) << 62) | ((uint64_t)len << MS_STR_INLINE_SHIFT);
}

/* A string that borrows what `s` holds: a view of an owned string's bytes, the same words for any other. */
static void borrow_string(const MsStr *s, MsStr *out) {
    if ((s->tagged >> 62) != 0) {
        *out = *s;
        return;
    }
    const size_t len = ms_str_len(s);
    if (len <= MS_STR_INLINE_MAX) {
        make_inline_string(s->ptr_word, len, out);
        return;
    }
    out->ptr_word = s->ptr_word;
    out->tagged = (UINT64_C(3) << 62) | len;
}

/* `for k in m.keys()` over a map that outlives the loop unchanged: string keys come back as views of the
 * map's own strings, so nothing is copied. Other keys are copied as by `keys`. */
static void collect_view(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, bool keys, MsList *out) {
    const MsTypeDesc *d = keys || vd == NULL ? kd : vd;
    if (d->kind != MS_KIND_STRING) {
        collect(m, kd, vd, keys, out);
        return;
    }
    const MapLayout l = ms_map_layout(kd, vd);
    const size_t offset = keys ? l.key_offset : l.value_offset;
    if (m->len == 0) {
        *out = (MsList){0};
        return;
    }
    MsList list = {.ptr = msrt_alloc(m->len * sizeof(MsStr)), .len = 0, .cap = m->len};
    for (size_t number = 0; number < m->used; number++) {
        const uint8_t *entry = ms_map_entry(m, &l, number);
        if (ms_map_entry_is_live(entry)) {
            borrow_string(key_str(entry + offset), (MsStr *)__builtin_assume_aligned(list.ptr + list.len * sizeof(MsStr), 8));
            list.len++;
        }
    }
    *out = list;
}

void msrt_map_keys(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, MsList *out) {
    collect(m, ms_map_key_desc(m, kd), vd, true, out);
}

void msrt_map_values(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, MsList *out) {
    collect(m, ms_map_key_desc(m, kd), vd, false, out);
}

void msrt_map_keys_view(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, MsList *out) {
    collect_view(m, ms_map_key_desc(m, kd), vd, true, out);
}

void msrt_map_values_view(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, MsList *out) {
    collect_view(m, ms_map_key_desc(m, kd), vd, false, out);
}

void msrt_set_values(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, MsList *out) {
    msrt_map_keys(m, kd, vd, out);
}

/* ---- merge and literals ---- */

/* A scratch slot: on the stack when it fits, else allocated. */
typedef struct Scratch {
    _Alignas(16) uint64_t words[8];
    uint8_t *ptr;
    bool heap;
} Scratch;

static void scratch_open(Scratch *scratch, size_t size) {
    scratch->heap = size > sizeof scratch->words;
    scratch->ptr = scratch->heap ? msrt_alloc(size) : (uint8_t *)scratch->words;
}

static void scratch_close(const Scratch *scratch) {
    if (scratch->heap) {
        msrt_free(scratch->ptr);
    }
}

/* `merge(other)`: the entries of `other` (borrowed, copied) replace or append. */
void msrt_map_merge(MsMap *m, const MsMap *other, const MsTypeDesc *kd, const MsTypeDesc *vd) {
    kd = ms_map_key_desc(m, kd);
    if (other->len == 0) {
        return;
    }
    const MapLayout l = ms_map_layout(kd, vd);
    /* Each insertion moves the copied slots in, so the scratch slots are reused for every entry. */
    Scratch key;
    Scratch value;
    scratch_open(&key, l.key_size);
    scratch_open(&value, l.value_size);
    for (size_t number = 0; number < other->used; number++) {
        const uint8_t *entry = ms_map_entry(other, &l, number);
        if (!ms_map_entry_is_live(entry)) {
            continue;
        }
        ms_slot_copy(kd, entry + l.key_offset, key.ptr);
        if (vd != NULL) {
            ms_slot_copy(vd, entry + l.value_offset, value.ptr);
        }
        ms_map_insert(m, kd, vd, key.ptr, value.ptr);
    }
    scratch_close(&key);
    scratch_close(&value);
}

static MS_NORETURN void fault_bad_table(void) {
    static const char message[] = "runtime invariant: malformed map table";
    msrt_fault((const uint8_t *)message, sizeof message - 1);
}

/* Decodes one item of a literal table into `out`, a slot of `size` bytes: tag 0 and an 8-byte word (an Int, the
 * bits of a Float, a Bool as 0 or 1), or tag 1, a u32 length and that many bytes (a String). Returns the
 * bytes after it. The compiler wrote the table, so a short one is a compiler bug. */
static MsBytes table_item(MsBytes rest, uint8_t *out, size_t size) {
    if (rest.len < 1) {
        fault_bad_table();
    }
    const uint8_t tag = rest.ptr[0];
    rest = ms_bytes_of(rest.ptr + 1, rest.len - 1);
    if (tag == 0) {
        if (rest.len < 8) {
            fault_bad_table();
        }
        __builtin_memcpy(out, rest.ptr, size < 8 ? size : 8);
        return ms_bytes_of(rest.ptr + 8, rest.len - 8);
    }
    uint32_t len = 0;
    if (rest.len < sizeof len) {
        fault_bad_table();
    }
    __builtin_memcpy(&len, rest.ptr, sizeof len);
    if (len > rest.len - sizeof len || size != sizeof(MsStr)) {
        fault_bad_table();
    }
    msrt_string_from_bytes(rest.ptr + sizeof len, len, (MsStr *)__builtin_assume_aligned(out, 8));
    return ms_bytes_of(rest.ptr + sizeof len + len, rest.len - sizeof len - len);
}

/* Adds the entries of a packed table of constants, in order, so a later entry replaces an earlier one with
 * an equal key. The compiler emits the table for a literal whose keys and values are all constants. */
void msrt_map_add_table(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const MsStr *table) {
    kd = ms_map_key_desc(m, kd);
    const MapLayout l = ms_map_layout(kd, vd);
    MsBytes rest = ms_bytes_of(ms_str_data(table), ms_str_len(table));
    _Alignas(16) uint64_t key[2] = {0, 0};
    _Alignas(16) uint64_t value[2] = {0, 0};
    while (rest.len > 0) {
        rest = table_item(rest, (uint8_t *)key, l.key_size);
        rest = table_item(rest, (uint8_t *)value, l.value_size);
        ms_map_insert(m, kd, vd, (uint8_t *)key, (uint8_t *)value);
    }
}

/* ---- Sets ---- */

/* A key copy that no entry owns yet: a hash or equality callback can leave by a jump before the insertion
 * stores it, so it is released then. */
typedef struct PendingKey {
    const MsTypeDesc *kd;
    uint8_t *key;
    bool heap;
} PendingKey;

static void release_pending(uint8_t *arg) {
    const PendingKey *pending = (const PendingKey *)__builtin_assume_aligned(arg, _Alignof(PendingKey));
    ms_slot_drop(pending->kd, pending->key);
    if (pending->heap) {
        msrt_free(pending->key);
    }
}

/* True when hashing or comparing keys of this type may run program code that leaves by a jump. */
static bool key_runs_program_code(const MsTypeDesc *kd) {
    return !ms_desc_drop_is_noop(kd) && kd->kind != MS_KIND_STRING && kd->kind != MS_KIND_BYTES;
}

/* Adds a copy of the key at `key`, first checking for a duplicate unless the caller knows the output has none. */
static void add_copy(MsMap *m, const MsTypeDesc *kd, const uint8_t *key, bool check) {
    if (check && ms_map_has(m, kd, NULL, key)) {
        return;
    }
    Scratch copy;
    scratch_open(&copy, kd->size);
    ms_slot_copy(kd, key, copy.ptr);
    if (key_runs_program_code(kd)) {
        PendingKey pending = {.kd = kd, .key = copy.ptr, .heap = copy.heap};
        const size_t handle = msrt_cleanup_push(release_pending, (uint8_t *)&pending);
        ms_map_insert(m, kd, NULL, copy.ptr, NULL);
        msrt_cleanup_discard(handle);
    } else {
        ms_map_insert(m, kd, NULL, copy.ptr, NULL);
    }
    scratch_close(&copy);
}

void msrt_set_add_copy(MsMap *m, const MsTypeDesc *kd, const uint8_t *key) {
    add_copy(m, ms_map_key_desc(m, kd), key, true);
}

/* Calls `visit` for each key of `m` in order until it returns false. False when it stopped early. */
typedef bool (*KeyVisitor)(void *context, const uint8_t *key);

static bool each_key(const MsMap *m, const MsTypeDesc *kd, KeyVisitor visit, void *context) {
    const MapLayout l = ms_map_layout(kd, NULL);
    for (size_t number = 0; number < m->used; number++) {
        const uint8_t *entry = ms_map_entry(m, &l, number);
        if (ms_map_entry_is_live(entry) && !visit(context, entry + l.key_offset)) {
            return false;
        }
    }
    return true;
}

/* Keys are tested against another set, probed with the key behaviour of the module that built it. */
typedef struct Membership {
    const MsMap *other;
    const MsTypeDesc *other_kd;
    bool wanted; /* the answer a key must get from `other` */
    MsMap *out;  /* where a key is copied */
    const MsTypeDesc *kd;
    bool check; /* whether the copy must look for a duplicate in `out` first */
} Membership;

static bool has_wanted_membership(void *context, const uint8_t *key) {
    const Membership *test = (const Membership *)context;
    return ms_map_has(test->other, test->other_kd, NULL, key) == test->wanted;
}

static bool copy_if_wanted(void *context, const uint8_t *key) {
    const Membership *test = (const Membership *)context;
    if (has_wanted_membership(context, key)) {
        add_copy(test->out, test->kd, key, test->check);
    }
    return true;
}

static bool add_checked(void *context, const uint8_t *key) {
    const Membership *test = (const Membership *)context;
    add_copy(test->out, test->kd, key, true);
    return true;
}

/* The keys of `a` that `other` has (or lacks), as a fresh set in a's order. */
static void filter_into(const MsMap *a, const MsTypeDesc *kd, const MsMap *other, const MsTypeDesc *other_kd, bool wanted, MsMap *out) {
    *out = (MsMap){.desc = a->desc};
    /* `a` has no duplicates and the output starts empty, so no copy needs a check. */
    Membership test = {.other = other, .other_kd = other_kd, .wanted = wanted, .out = out, .kd = kd, .check = false};
    (void)each_key(a, kd, copy_if_wanted, &test);
}

void msrt_set_union(const MsMap *a, const MsMap *b, const MsTypeDesc *kd, MsMap *out) {
    kd = ms_map_key_desc(a, kd);
    ms_map_clone(a, kd, NULL, out);
    Membership test = {.out = out, .kd = kd, .check = true};
    (void)each_key(b, kd, add_checked, &test);
}

void msrt_set_intersection(const MsMap *a, const MsMap *b, const MsTypeDesc *kd, MsMap *out) {
    const MsTypeDesc *right_kd = ms_map_key_desc(b, kd);
    if (b->len == 0) {
        *out = (MsMap){.desc = a->desc};
        return;
    }
    filter_into(a, ms_map_key_desc(a, kd), b, right_kd, true, out);
}

void msrt_set_difference(const MsMap *a, const MsMap *b, const MsTypeDesc *kd, MsMap *out) {
    filter_into(a, ms_map_key_desc(a, kd), b, ms_map_key_desc(b, kd), false, out);
}

void msrt_set_symmetric_difference(const MsMap *a, const MsMap *b, const MsTypeDesc *kd, MsMap *out) {
    const MsTypeDesc *right_kd = ms_map_key_desc(b, kd);
    const MsTypeDesc *left_kd = ms_map_key_desc(a, kd);
    filter_into(a, left_kd, b, right_kd, false, out);
    /* Then the keys of `b` that `a` lacks. */
    Membership test = {.other = a, .other_kd = left_kd, .wanted = false, .out = out, .kd = left_kd, .check = true};
    (void)each_key(b, left_kd, copy_if_wanted, &test);
}

/* True when every key of `a` has the membership `wanted` in `b`. */
static bool all_keys_have(const MsMap *a, const MsTypeDesc *a_kd, const MsMap *b, const MsTypeDesc *b_kd, bool wanted) {
    Membership test = {.other = b, .other_kd = b_kd, .wanted = wanted};
    return each_key(a, a_kd, has_wanted_membership, &test);
}

uint8_t msrt_set_is_subset_of(const MsMap *a, const MsMap *b, const MsTypeDesc *kd) {
    return all_keys_have(a, ms_map_key_desc(a, kd), b, ms_map_key_desc(b, kd), true);
}

uint8_t msrt_set_is_superset_of(const MsMap *a, const MsMap *b, const MsTypeDesc *kd) {
    return msrt_set_is_subset_of(b, a, ms_map_key_desc(a, kd));
}

uint8_t msrt_set_is_disjoint_from(const MsMap *a, const MsMap *b, const MsTypeDesc *kd) {
    if (b->len == 0) {
        return 1;
    }
    return all_keys_have(a, ms_map_key_desc(a, kd), b, ms_map_key_desc(b, kd), false);
}

/* ---- JSON objects ---- */

/* Fills the empty map `m` (no storage) from `n` string keys and values `stride` bytes apart, consuming them.
 * Returns -1, or the index of the first repeated key: members before it are in the map, the caller keeps
 * ownership of the rest. */
int64_t msrt_map_fill_strings(MsMap *m, const MsTypeDesc *vd, MsStr *keys, uint8_t *vals, int64_t stride, int64_t n) {
    m->desc = &msrt_desc_string;
    if (n <= 0) {
        return -1;
    }
    const MapLayout l = ms_map_layout(&msrt_desc_string, vd);
    ms_map_reserve(m, &l, (size_t)n);
    for (int64_t i = 0; i < n; i++) {
        const uint8_t *key = (const uint8_t *)&keys[i];
        const uint64_t hash = ms_map_hash(&ms_str_keys, NULL, key);
        if (ms_map_find(&ms_str_keys, m, NULL, &l, key, hash) != MS_MAP_NO_ENTRY) {
            return i;
        }
        uint8_t *entry = ms_map_next_entry(m, &l);
        ms_map_store_hash(entry, hash);
        ms_map_copy_slot(entry + l.key_offset, key, l.key_size);
        ms_map_copy_slot(entry + l.value_offset, vals + i * stride, l.value_size);
        ms_map_publish(m, hash);
    }
    return -1;
}
