/* The generated table of runtime functions (rt_ops_data.inc, written
 * by `ms run tools/ms/symbols.ms` from the `ms-sig` tags), searched by symbol. libms.c includes this file. */
#include <string.h>

#include <ctype.h>

#include "ms/check.h"
#include "ms/rt_ops.h"

#include "rt_ops_data.inc"
#include "status_rows_data.inc"

size_t ms_rt_status_rows(const MsRtFn *fn, MsStatusRow *out, size_t cap) {
    const size_t count = sizeof status_rows / sizeof status_rows[0];
    for (size_t i = 0; i < count && i < cap; i++) {
        out[i] = status_rows[i];
        for (size_t k = 0; k < sizeof status_words / sizeof status_words[0]; k++) {
            if (status_words[k].status == status_rows[i].status && strcmp(status_words[k].symbol, fn->symbol) == 0) {
                out[i].words = status_words[k].words;
            }
        }
    }
    return count;
}

const MsRtFn *ms_rt_fn_find(const char *symbol, size_t length) {
    size_t low = 0;
    size_t high = sizeof rt_fns / sizeof rt_fns[0];
    while (low < high) {
        const size_t middle = low + (high - low) / 2;
        const MsRtFn *row = &rt_fns[middle];
        const size_t row_length = strlen(row->symbol);
        const size_t common = row_length < length ? row_length : length;
        int order = strncmp(row->symbol, symbol, common);
        if (order == 0 && row_length != length) {
            order = row_length < length ? -1 : 1;
        }
        if (order == 0) {
            return row;
        }
        if (order < 0) {
            low = middle + 1;
        } else {
            high = middle;
        }
    }
    return NULL;
}

/* The runtime function `msrt_<type>_<method>` (the type in lower case), or NULL. */
static const MsRtFn *rt_method_symbol(const char *type, size_t type_len, const char *method, size_t method_len) {
    char symbol[96];
    if (type_len + method_len + 8 > sizeof symbol) {
        return NULL;
    }
    size_t length = 0;
    for (const char *part = "msrt_"; *part != '\0'; part++) {
        symbol[length++] = *part;
    }
    for (size_t i = 0; i < type_len; i++) {
        symbol[length++] = (char)tolower((unsigned char)type[i]);
    }
    symbol[length++] = '_';
    for (size_t i = 0; i < method_len; i++) {
        symbol[length++] = method[i];
    }
    return ms_rt_fn_find(symbol, length);
}

const MsRtFn *ms_rt_method_fn(const MsCheck *c, MsTy receiver, MsSym method) {
    const MsStr type = ms_name(c->names, c->tys.name[receiver]);
    const MsStr name = ms_name(c->names, method);
    for (size_t i = 0; i < sizeof rt_methods / sizeof rt_methods[0]; i++) { // a declared implementation comes first
        const char *declared = rt_methods[i].method;
        const size_t declared_length = strlen(declared);
        if (declared_length == type.len + 1 + name.len && memcmp(declared, type.ptr, type.len) == 0 &&
            declared[type.len] == '.' && memcmp(declared + type.len + 1, name.ptr, name.len) == 0) {
            return ms_rt_fn_find(rt_methods[i].symbol, strlen(rt_methods[i].symbol));
        }
    }
    const MsRtFn *own = rt_method_symbol(type.ptr, type.len, name.ptr, name.len);
    if (own != NULL || type.len != 5 || memcmp(type.ptr, "Bytes", 5) != 0) {
        return own;
    }
    const MsRtFn *list = rt_method_symbol("List", 4, name.ptr, name.len);
    return list != NULL && (list->op[0] != '\0' || list->seq[0] != '\0') ? list : NULL; // `Bytes` is a list of bytes: the list functions serve it
}
