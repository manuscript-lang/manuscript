/* Interpreter values: reference-counted aggregates with copy on write, and their display. A
 * MirVal holds one reference to its block; blocks are freed when the last reference goes. */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "mir/mir_interp_impl.h"

void ip_oom(void) {
    fputs("ms: out of memory\n", stderr);
    abort();
}

MirVal ip_void(void) {
    MirVal value = {.tag = MV_VOID};
    return value;
}

MirVal mir_val_int(int64_t value) {
    MirVal result = {.tag = MV_INT};
    result.as.i = value;
    return result;
}

MirVal mir_val_bool(bool value) {
    MirVal result = {.tag = MV_BOOL};
    result.as.i = value ? 1 : 0;
    return result;
}

MirVal ip_float(double value) {
    MirVal result = {.tag = MV_FLOAT};
    result.as.f = value;
    return result;
}

MirVal ip_ptr(uint64_t address) {
    MirVal result = {.tag = MV_PTR};
    result.as.p = address;
    return result;
}

static bool ip_is_aggregate(MirVal value) {
    switch ((MirValTag)value.tag) {
    case MV_STR: case MV_TYPE: case MV_ALT: case MV_LIST: case MV_OPT: case MV_CLOSURE:
    case MV_IFACE: case MV_MAP:
        return true;
    case MV_VOID: case MV_BOOL: case MV_INT: case MV_FLOAT: case MV_PTR:
        return false;
    }
    return false;
}

MirVal ip_retain(MirVal value) {
    if (ip_is_aggregate(value) && value.as.blob != NULL) {
        value.as.blob->refs++;
    }
    return value;
}

static void *ip_xalloc(size_t size) {
    void *block = calloc(1, size);
    if (block == NULL) {
        ip_oom();
    }
    return block;
}

/* The next capacity for a growing array: doubled from `count`, at least `first`; exhausted at 2^31. */
uint32_t ip_grow_cap(uint32_t count, uint32_t first) {
    if (count >= UINT32_MAX / 2) {
        ip_oom();
    }
    return count < first ? first : count * 2;
}

/* A bigger copy of an array of `old_bytes`; the old one is freed. */
void *ip_regrow(void *old, size_t old_bytes, size_t new_bytes) {
    void *block = ip_xalloc(new_bytes);
    if (old_bytes > 0) {
        memcpy(block, old, old_bytes);
    }
    free(old);
    return block;
}

static size_t ip_blob_bytes(size_t payload) {
    size_t total = 0;
    if (!ms_size_add(sizeof(MirBlob), payload, &total)) {
        ip_oom();
    }
    return total;
}

MirBlob *ip_blob_new(uint32_t count) {
    if (count == 0) {
        return NULL;
    }
    size_t payload = 0;
    if (!ms_size_mul(count, sizeof(MirVal), &payload)) {
        ip_oom();
    }
    MirBlob *blob = ip_xalloc(ip_blob_bytes(payload));
    blob->refs = 1;
    blob->count = count;
    blob->cap = count;
    return blob;
}

MirVal ip_aggregate(uint8_t tag, uint32_t id, MirBlob *blob) {
    MirVal value = {.tag = tag, .id = id};
    value.as.blob = blob;
    return value;
}

MirVal ip_str(const char *bytes, size_t length) {
    if (length == 0) {
        return ip_aggregate(MV_STR, 0, NULL);
    }
    if (length > UINT32_MAX) {
        ip_oom();
    }
    MirBlob *blob = ip_xalloc(ip_blob_bytes(length));
    blob->refs = 1;
    blob->count = (uint32_t)length;
    blob->cap = (uint32_t)length;
    memcpy((char *)blob->items, bytes, length);
    return ip_aggregate(MV_STR, 0, blob);
}

MsStr ip_str_view(MirVal value) {
    MsStr view = {.ptr = "", .len = 0};
    if (value.as.blob != NULL) {
        view.ptr = (const char *)value.as.blob->items;
        view.len = value.as.blob->count;
    }
    return view;
}

MirVal ip_opt_some(MirVal payload) {
    MirBlob *blob = ip_blob_new(1);
    blob->items[0] = payload;
    return ip_aggregate(MV_OPT, 0, blob);
}

uint32_t ip_count(MirVal value) {
    return value.as.blob == NULL ? 0 : value.as.blob->count;
}

MirVal *ip_items(MirVal value) {
    return value.as.blob == NULL ? NULL : value.as.blob->items;
}

/* ---- release ---- */

/* Frees blocks whose last reference is gone. A long chain (a list of lists, a linked record) is
 * walked with an explicit stack, so its depth does not reach the C stack. */
void mir_val_release(MirVal *value) {
    MsBuf pending = {0};
    MirVal current = *value;
    *value = ip_void();
    for (;;) {
        if (ip_is_aggregate(current) && current.as.blob != NULL && --current.as.blob->refs == 0) {
            MirBlob *blob = current.as.blob;
            if (current.tag != MV_STR) {
                ms_buf_put(&pending, blob->items, sizeof(MirVal) * blob->count);
            }
            free(blob);
        }
        if (pending.len == 0) {
            break;
        }
        pending.len -= sizeof(MirVal);
        memcpy(&current, pending.data + pending.len, sizeof current);
    }
    ms_buf_free(&pending);
}

/* ---- copy on write ---- */

bool ip_make_unique(MirVal *value) {
    if (!ip_is_aggregate(*value) || value->tag == MV_STR) {
        return false;
    }
    MirBlob *old = value->as.blob;
    if (old == NULL || old->refs == 1) {
        return true;
    }
    MirBlob *copy = ip_blob_new(old->count);
    for (uint32_t i = 0; i < old->count; i++) {
        copy->items[i] = ip_retain(old->items[i]);
    }
    old->refs--;
    value->as.blob = copy;
    return true;
}

void ip_list_push(MirVal *list, MirVal item) {
    MirBlob *blob = list->as.blob;
    if (blob == NULL || blob->count == blob->cap) {
        uint32_t count = blob == NULL ? 0 : blob->count;
        uint32_t cap = ip_grow_cap(count, 4);
        size_t payload = 0;
        if (!ms_size_mul(cap, sizeof(MirVal), &payload)) {
            ip_oom();
        }
        MirBlob *grown = realloc(blob, ip_blob_bytes(payload));
        if (grown == NULL) {
            ip_oom();
        }
        if (blob == NULL) {
            grown->refs = 1;
            grown->count = 0;
        }
        grown->cap = cap;
        blob = grown;
        list->as.blob = blob;
    }
    blob->items[blob->count++] = item;
}

void ip_list_pop(MirVal *list) {
    MirBlob *blob = list->as.blob;
    if (blob != NULL && blob->count > 0) {
        blob->count--;
        mir_val_release(&blob->items[blob->count]);
    }
}

/* ---- display ---- */

/* printf rounds an exact tie to even where Rust rounds it up. If `value` lies exactly halfway
 * between two `precision`-digit texts and `text` is the lower one (even last digit), bump it. */
static void ip_round_half_up(char *text, int precision, double value) {
    static char exact[1100];
    snprintf(exact, sizeof exact, "%.*e", 1000, value);
    char digits[1100];
    size_t count = 0;
    for (const char *p = exact; *p != 'e' && *p != '\0'; p++) {
        if (*p >= '0' && *p <= '9') digits[count++] = *p;
    }
    size_t kept = (size_t)precision + 1;
    if (count <= kept || digits[kept] != '5') {
        return;
    }
    for (size_t i = kept + 1; i < count; i++) {
        if (digits[i] != '0') return;
    }
    char *end = strchr(text, 'e');
    if (end != NULL && end > text && (end[-1] - '0') % 2 == 0) {
        end[-1]++;
    }
}

/* Writes the shortest `%e` text that reads back as `value`. The correctly rounded n-digit text can
 * miss while a neighbouring n-digit text hits (Rust then prints the neighbour), so try both. */
static void ip_shortest(char *text, size_t size, double value) {
    for (int precision = 0; precision <= 16; precision++) {
        snprintf(text, size, "%.*e", precision, value);
        if (strtod(text, NULL) == value) {
            ip_round_half_up(text, precision, value);
            return;
        }
        char *mark = strchr(text, 'e');
        if (mark == NULL) {
            continue;
        }
        long exponent = strtol(mark + 1, NULL, 10);
        unsigned long long mantissa = 0;
        for (const char *p = text + (text[0] == '-' ? 1 : 0); p < mark; p++) {
            if (*p != '.') mantissa = mantissa * 10 + (unsigned long long)(*p - '0');
        }
        /* The neighbour on the side of the exact value is the closer one: compare the exact digits with the text's.
         * No long double: aarch64 builds have no compiler-rt for its soft-float routines. */
        static char exact[1100];
        snprintf(exact, sizeof exact, "%.*e", 1000, value);
        const char *exact_mark = strchr(exact, 'e');
        bool above = exact_mark != NULL && strtol(exact_mark + 1, NULL, 10) == exponent;
        if (above) {
            const char *t = text + (text[0] == '-' ? 1 : 0);
            const char *x = exact + (exact[0] == '-' ? 1 : 0);
            above = false;
            for (; t < mark; t++) {
                if (*t == '.') continue;
                if (*x == '.') x++;
                if (*x != *t) {
                    above = *x > *t;
                    break;
                }
                x++;
            }
            if (t == mark) above = true; /* the digits agree, so the exact value lies above the text */
        }
        for (int pick = 0; pick < 2; pick++) {
            int step = (pick == 0) == above ? 1 : -1;
            char digits[32];
            int ndigits = snprintf(digits, sizeof digits, "%llu", mantissa + (unsigned long long)step);
            char candidate[48];
            snprintf(candidate, sizeof candidate, "%s%c.%se%ld", value < 0 ? "-" : "", digits[0],
                     digits + 1, exponent + ndigits - (precision + 1));
            if (strtod(candidate, NULL) != value) continue;
            snprintf(text, size, "%s", candidate);
            return;
        }
    }
}

/* The shortest text that reads back as `value`, with no exponent (Rust's `{}` for a float). */
void ip_fmt_float(MsBuf *out, double value) {
    if (isnan(value)) {
        ms_buf_puts(out, "NaN");
        return;
    }
    if (isinf(value)) {
        ms_buf_puts(out, value < 0 ? "-inf" : "inf");
        return;
    }
    if (value == 0) {
        ms_buf_puts(out, signbit(value) ? "-0" : "0");
        return;
    }
    char text[48] = {0};
    ip_shortest(text, sizeof text, value);
    const char *at = text;
    if (*at == '-') {
        ms_buf_putc(out, '-');
        at++;
    }
    char digits[24] = {0};
    size_t ndigits = 0;
    for (; *at != 'e' && *at != '\0'; at++) {
        if (*at != '.' && ndigits < sizeof digits - 1) {
            digits[ndigits++] = *at;
        }
    }
    long exponent = *at == 'e' ? strtol(at + 1, NULL, 10) : 0;
    long point = exponent + 1; /* digits before the decimal point */
    if (point <= 0) {
        ms_buf_puts(out, "0.");
        for (long i = point; i < 0; i++) {
            ms_buf_putc(out, '0');
        }
        ms_buf_put(out, digits, ndigits);
        return;
    }
    for (long i = 0; i < point; i++) {
        char digit = '0';
        if ((size_t)i < ndigits) {
            digit = digits[i];
        }
        ms_buf_putc(out, digit);
    }
    if ((size_t)point < ndigits) {
        ms_buf_putc(out, '.');
        ms_buf_put(out, digits + point, ndigits - (size_t)point);
    }
}

/* What `print` and `msrt_fault` show: scalars and strings; an aggregate is only named. */
void ip_show(MsBuf *out, MirVal value) {
    switch ((MirValTag)value.tag) {
    case MV_VOID:
        ms_buf_puts(out, "()");
        break;
    case MV_BOOL:
        ms_buf_puts(out, value.as.i != 0 ? "true" : "false");
        break;
    case MV_INT:
        ms_buf_printf(out, "%lld", (long long)value.as.i);
        break;
    case MV_FLOAT:
        ip_fmt_float(out, value.as.f);
        break;
    case MV_STR: {
        MsStr text = ip_str_view(value);
        ms_buf_put(out, text.ptr, text.len);
        break;
    }
    case MV_PTR: case MV_TYPE: case MV_ALT: case MV_LIST: case MV_OPT: case MV_CLOSURE:
    case MV_IFACE: case MV_MAP:
        ms_buf_puts(out, "<value>");
        break;
    }
}
