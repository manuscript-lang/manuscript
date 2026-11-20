/* The header table and its natives (headers.h). */
#include "headers.h"

#include <stdlib.h>
#include <string.h>

#include "../std/abi.h"
#include "http1.h"
#include "ms_rt/alloc.h"
#include "ms_rt/chars.h"
#include "ms_rt/net.h"

typedef struct Field {
    uint32_t name, name_len, value, value_len; /* offsets and lengths into the table's bytes */
} Field;

struct MsHeaders {
    MsObj header; /* first: the handle the runtime holds */
    MsHeaders *self; /* the handle's writable view: natives receive it as a const pointer */
    Field *fields;
    size_t count, capacity;
    uint8_t *bytes;
    size_t used, bytes_capacity;
};

static void table_drop(MsObj *object) {
    MsHeaders *table = (MsHeaders *)object;
    free(table->fields);
    free(table->bytes);
    msrt_free(table);
}

static MsObj *table_clone(MsObj *object);

MsHeaders *ms_headers_new(void) {
    MsHeaders *table = msrt_alloc(sizeof *table);
    memset(table, 0, sizeof *table);
    table->header.drop = table_drop;
    table->header.clone = table_clone; /* a copy of a record that holds headers is a deep copy */
    table->self = table;
    return table;
}

MsHeaders *ms_headers_of(const void *handle) { return ((const MsHeaders *)handle)->self; }

static MsBytes name_of(const MsHeaders *table, const Field *field) { return ms_bytes_of(table->bytes + field->name, field->name_len); }
static MsBytes value_of(const MsHeaders *table, const Field *field) { return ms_bytes_of(table->bytes + field->value, field->value_len); }

/* The first field called `name` and the one after its last, or count when there is none. */
static bool find_group(const MsHeaders *table, MsBytes name, size_t *first, size_t *end) {
    size_t i = 0;
    while (i < table->count && !ms_ascii_equal_fold(name_of(table, &table->fields[i]), name)) {
        i++;
    }
    *first = i;
    while (i < table->count && ms_ascii_equal_fold(name_of(table, &table->fields[i]), name)) {
        i++;
    }
    *end = i;
    return *first < table->count;
}

/* Appends `data` to the table's bytes; false when it would pass the limit or memory runs out. */
static bool push_bytes(MsHeaders *table, MsBytes data, uint32_t *at) {
    size_t total;
    if (!ms_size_add(table->used, data.len, &total) || total > MS_HEADERS_MAX_BYTES) {
        return false;
    }
    if (total > table->bytes_capacity) {
        size_t capacity = table->bytes_capacity == 0 ? 256 : table->bytes_capacity;
        while (capacity < total) {
            capacity *= 2;
        }
        uint8_t *grown = realloc(table->bytes, capacity);
        if (grown == NULL) {
            return false;
        }
        table->bytes = grown;
        table->bytes_capacity = capacity;
    }
    if (data.len > 0) {
        memcpy(table->bytes + table->used, data.ptr, data.len);
    }
    *at = (uint32_t)table->used;
    table->used = total;
    return true;
}

bool ms_headers_add(MsHeaders *table, MsBytes name, MsBytes value) {
    if (table->count >= MS_HEADERS_MAX_FIELDS) {
        return false;
    }
    if (table->count == table->capacity) {
        const size_t capacity = table->capacity == 0 ? 8 : table->capacity * 2;
        Field *grown = realloc(table->fields, capacity * sizeof *grown);
        if (grown == NULL) {
            return false;
        }
        table->fields = grown;
        table->capacity = capacity;
    }
    size_t first, end;
    const bool known = find_group(table, name, &first, &end);
    const size_t used_before = table->used;
    Field field = {0, 0, 0, (uint32_t)value.len};
    if (known) { /* a later value shares the group's name bytes */
        field.name = table->fields[first].name;
        field.name_len = table->fields[first].name_len;
    } else {
        field.name_len = (uint32_t)name.len;
        if (!push_bytes(table, name, &field.name)) {
            return false;
        }
    }
    if (!push_bytes(table, value, &field.value)) {
        table->used = used_before; /* the name's bytes are given back */
        return false;
    }
    memmove(&table->fields[end + 1], &table->fields[end], (table->count - end) * sizeof(Field));
    table->fields[end] = field;
    table->count++;
    return true;
}

/* Title-cases a name that is a token ("content-type" becomes "Content-Type"); other names are kept as they are. */
bool ms_headers_add_canonical(MsHeaders *table, MsBytes name, MsBytes value) {
    uint8_t text[256];
    if (!ms_h1_is_token(name) || name.len > sizeof text) {
        return ms_headers_add(table, name, value);
    }
    bool upper = true;
    for (size_t i = 0; i < name.len; i++) {
        text[i] = upper ? ms_ascii_to_upper(name.ptr[i]) : ms_ascii_to_lower(name.ptr[i]);
        upper = name.ptr[i] == '-';
    }
    return ms_headers_add(table, ms_bytes_of(text, name.len), value);
}

size_t ms_headers_count(const MsHeaders *table) { return table->count; }

void ms_headers_field(const MsHeaders *table, size_t i, MsBytes *name, MsBytes *value) {
    *name = name_of(table, &table->fields[i]);
    *value = value_of(table, &table->fields[i]);
}

/* ---- natives ---- */

static MsBytes str_bytes(const MsStr *text) { return ms_bytes_of((const uint8_t *)msrt_str_data(text), msrt_str_len(text)); }

void *msstd_headers_new(void) {
    MsHeaders *table = ms_headers_new();
    return table == NULL ? NULL : ms_headers_object(table);
}

void *msstd_headers_clone(const void *handle) {
    const MsHeaders *from = ms_headers_of(handle);
    MsHeaders *copy = ms_headers_new();
    for (size_t i = 0; copy != NULL && i < from->count; i++) {
        MsBytes name, value;
        ms_headers_field(from, i, &name, &value);
        if (!ms_headers_add(copy, name, value)) {
            table_drop(ms_headers_object(copy));
            return NULL;
        }
    }
    return copy == NULL ? NULL : ms_headers_object(copy);
}

static MsObj *table_clone(MsObj *object) { return msstd_headers_clone(object); }

uint8_t msstd_headers_append(const void *handle, const MsStr *name, const MsVec *value) {
    const MsBytes field = str_bytes(name);
    if (!ms_h1_is_token(field)) {
        return STATUS_INVALID_INPUT;
    }
    return ms_headers_add(ms_headers_of(handle), field, ms_bytes_of(value->ptr, value->len)) ? STATUS_OK : STATUS_LIMIT_EXCEEDED;
}

uint8_t msstd_headers_values(const void *handle, const MsStr *name, MsVec *out) {
    const MsHeaders *table = ms_headers_of(handle);
    size_t first, end;
    if (!find_group(table, str_bytes(name), &first, &end)) {
        return 0;
    }
    msrt_list_with_capacity(&msrt_desc_bytes, (int64_t)(end - first), out);
    for (size_t i = first; i < end; i++) {
        const MsBytes value = value_of(table, &table->fields[i]);
        MsVec item;
        msrt_write_bytes(&item, value.ptr, value.len);
        msrt_list_push(out, &msrt_desc_bytes, (const uint8_t *)&item);
    }
    return 1;
}

void msstd_headers_names(const void *handle, MsVec *out) {
    const MsHeaders *table = ms_headers_of(handle);
    msrt_list_with_capacity(&msrt_desc_string, 0, out);
    for (size_t i = 0; i < table->count; i++) {
        if (i > 0 && table->fields[i].name == table->fields[i - 1].name) {
            continue; /* the same name, one more value */
        }
        const MsBytes name = name_of(table, &table->fields[i]);
        MsStr text;
        msrt_string_from_bytes(name.ptr, name.len, &text);
        msrt_list_push(out, &msrt_desc_string, (const uint8_t *)&text);
    }
}

uint8_t msstd_headers_remove(const void *handle, const MsStr *name) {
    MsHeaders *table = ms_headers_of(handle);
    size_t first, end;
    if (!find_group(table, str_bytes(name), &first, &end)) {
        return 0;
    }
    memmove(&table->fields[first], &table->fields[end], (table->count - end) * sizeof(Field));
    table->count -= end - first;
    return 1;
}
