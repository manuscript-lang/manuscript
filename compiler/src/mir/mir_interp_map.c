/* The runtime's maps for the interpreter: `msrt_map_new`, `msrt_map_add` and the lookups
 * `msrt_map_get_ptr`, `_w8`, `_sw8`. A map is the value `MV_MAP` whose blob holds keys and values
 * alternately in insertion order; a key or value passes through a memory cell (the slot the
 * lowering made) and a lookup returns a pointer to a new cell holding the value. The shaped lookups
 * differ from the general one only in speed, so they share one implementation. */
#include <stdlib.h>
#include <string.h>

#include "mir/mir_interp_impl.h"

static bool ip_map_name(MsStr name, const char *text) {
    return name.len == strlen(text) && memcmp(name.ptr, text, name.len) == 0;
}

/* Memory cell `pointer` names, or NULL for null and addresses the interpreter never made. */
static MirVal *ip_map_cell(MirInterp *it, const MirVal *pointer) {
    if (pointer->tag != MV_PTR || pointer->as.p == 0 || pointer->as.p > it->nmemory) {
        return NULL;
    }
    return &it->memory[pointer->as.p - 1];
}

static bool ip_map_key_equal(MirVal a, MirVal b) {
    if (a.tag != b.tag) {
        return false;
    }
    if (a.tag == MV_STR) {
        const MsStr x = ip_str_view(a);
        const MsStr y = ip_str_view(b);
        return x.len == y.len && memcmp(x.ptr, y.ptr, x.len) == 0;
    }
    return a.as.i == b.as.i;
}

/* The index of `key`'s value among the blob's items, or 0 when absent (a value is never item 0). */
static uint32_t ip_map_find(const MirVal *map, MirVal key) {
    const MirBlob *blob = map->as.blob;
    for (uint32_t i = 0; blob != NULL && i < blob->count; i += 2) {
        if (ip_map_key_equal(blob->items[i], key)) {
            return i + 1;
        }
    }
    return 0;
}

/* `map` with `key` bound to `value` (both taken from the caller by retaining them). */
static void ip_map_set(MirVal *map, MirVal key, MirVal value) {
    (void)ip_make_unique(map);
    const uint32_t at = ip_map_find(map, key);
    if (at != 0) {
        mir_val_release(&map->as.blob->items[at]);
        map->as.blob->items[at] = ip_retain(value);
        return;
    }
    const uint32_t count = map->as.blob == NULL ? 0 : map->as.blob->count;
    MirBlob *grown = ip_blob_new(count + 2);
    if (count != 0) {
        memcpy(grown->items, map->as.blob->items, sizeof(MirVal) * count);
        free(map->as.blob);
    }
    grown->items[count] = ip_retain(key);
    grown->items[count + 1] = ip_retain(value);
    map->as.blob = grown;
}

/* A new memory cell holding `value`; its address. */
static MirVal ip_map_new_cell(MirInterp *it, MirVal value) {
    if (it->nmemory == it->cmemory) {
        const uint32_t grown = ip_grow_cap(it->cmemory, 16);
        it->memory = ip_regrow(it->memory, sizeof(MirVal) * it->cmemory, sizeof(MirVal) * grown);
        it->cmemory = grown;
    }
    it->memory[it->nmemory++] = ip_retain(value);
    return ip_ptr(it->nmemory);
}

bool ip_map_runtime(MirInterp *it, MsStr name, const MirVal *args, uint32_t count, MirVal *result, IpFlow *flow) {
    if (ip_map_name(name, "msrt_map_new") && count == 0) {
        *result = ip_aggregate(MV_MAP, 0, NULL);
        return true;
    }
    if (ip_map_name(name, "msrt_map_add") && count == 5) {
        MirVal *map = ip_map_cell(it, &args[0]);
        const MirVal *key = ip_map_cell(it, &args[3]);
        const MirVal *value = ip_map_cell(it, &args[4]);
        if (map == NULL || map->tag != MV_MAP || key == NULL || value == NULL) {
            *flow = ip_internal(it, "msrt_map_add: operand of the wrong kind");
            return true;
        }
        ip_map_set(map, *key, *value);
        return true;
    }
    const bool lookup = ip_map_name(name, "msrt_map_get_ptr") || ip_map_name(name, "msrt_map_get_ptr_w8") ||
                        ip_map_name(name, "msrt_map_get_ptr_sw8");
    if (!lookup || count != 4) {
        return false;
    }
    const MirVal *map = args[0].tag == MV_PTR ? ip_map_cell(it, &args[0]) : &args[0];
    const MirVal *key = ip_map_cell(it, &args[3]);
    if (map == NULL || map->tag != MV_MAP || key == NULL) {
        *flow = ip_internal(it, "%.*s: operand of the wrong kind", (int)name.len, name.ptr);
        return true;
    }
    const uint32_t at = ip_map_find(map, *key);
    *result = at == 0 ? ip_ptr(0) : ip_map_new_cell(it, map->as.blob->items[at]);
    return true;
}
