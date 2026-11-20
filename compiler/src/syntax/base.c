/* Arena, scratch buffer, interner and UTF-8 helpers. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms/base.h"
#include "ms_rt/chars.h"

struct MsChunk {
    MsChunk *next;
    size_t size;
    /* data follows, aligned to 16 */
};

#define MS_CHUNK_MIN ((size_t)64 * 1024)
#define MS_CHUNK_HEADER 16

_Noreturn void ms_oom(void) {
    fputs("ms: out of memory\n", stderr);
    abort();
}

/* Bytes to skip from `cursor` to reach a multiple of `align` (a power of two). */
static size_t padding_for(const char *cursor, size_t align) {
    size_t misalignment = (uintptr_t)cursor & (align - 1);
    return (align - misalignment) & (align - 1);
}

static bool chunk_fits(const MsArena *a, size_t size, size_t align) {
    if (a->cur == NULL) {
        return false;
    }
    size_t padding = padding_for(a->cur, align);
    size_t remaining = (size_t)(a->end - a->cur);
    return padding <= remaining && size <= remaining - padding;
}

static void arena_add_chunk(MsArena *a, size_t size, size_t align) {
    size_t want = size + align + MS_CHUNK_HEADER;
    size_t capacity = want > MS_CHUNK_MIN ? want : MS_CHUNK_MIN;
    MsChunk *chunk = malloc(sizeof(MsChunk) + capacity);
    if (chunk == NULL) {
        ms_oom();
    }
    chunk->next = a->head;
    chunk->size = capacity;
    a->head = chunk;
    a->cur = (char *)(chunk + 1);
    a->end = a->cur + capacity;
}

void *ms_alloc_zeroed(MsArena *a, size_t count, size_t size) {
    void *p = ms_alloc(a, size * (count + 1), 16);
    memset(p, 0, size * (count + 1));
    return p;
}

void *ms_alloc(MsArena *a, size_t size, size_t align) {
    if (!chunk_fits(a, size, align)) {
        arena_add_chunk(a, size, align);
    }
    a->cur += padding_for(a->cur, align);
    void *result = a->cur;
    a->cur += size;
    return result;
}

void ms_arena_free(MsArena *a) {
    MsChunk *c = a->head;
    while (c != NULL) {
        MsChunk *next = c->next;
        free(c);
        c = next;
    }
    a->head = NULL;
    a->cur = a->end = NULL;
}

void ms_arena_reset(MsArena *a) {
    MsChunk *keep = a->head;
    if (keep == NULL) {
        return;
    }
    MsChunk *c = keep->next;
    while (c != NULL) {
        MsChunk *next = c->next;
        free(c);
        c = next;
    }
    keep->next = NULL;
    a->cur = (char *)(keep + 1);
    a->end = a->cur + keep->size;
}

uint32_t ms_capacity_for(uint32_t current, uint32_t needed) {
    uint32_t capacity = current != 0 ? current : 64;
    while (capacity < needed) {
        if (capacity > UINT32_MAX / 2) {
            ms_oom();
        }
        capacity *= 2;
    }
    return capacity;
}

void *ms_array_resize(void *array, uint32_t capacity, size_t element_size) {
    if (element_size == 0 || capacity > SIZE_MAX / element_size) {
        ms_oom();
    }
    void *moved = realloc(array, (size_t)capacity * element_size);
    if (moved == NULL) {
        ms_oom();
    }
    return moved;
}

char *ms_arena_strndup(MsArena *a, const char *s, size_t n) {
    char *d = ms_alloc(a, n + 1, 1);
    memcpy(d, s, n);
    d[n] = 0;
    return d;
}

MsStr ms_arena_vfmt(MsArena *a, const char *fmt, va_list ap) {
    va_list again;
    va_copy(again, ap);
    int n = vsnprintf(NULL, 0, fmt, ap);
    if (n < 0) {
        ms_oom();
    }
    char *d = ms_alloc(a, (size_t)n + 1, 1);
    vsnprintf(d, (size_t)n + 1, fmt, again);
    va_end(again);
    MsStr r = {d, (uint32_t)n};
    return r;
}

MsStr ms_arena_fmt(MsArena *a, const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    MsStr r = ms_arena_vfmt(a, fmt, ap);
    va_end(ap);
    return r;
}

/* ---- MsBuf ---- */

void ms_buf_free(MsBuf *b) {
    free(b->data);
    b->data = NULL;
    b->len = b->cap = 0;
}

void *ms_buf_push(MsBuf *b, size_t n) {
    if (b->len + n > b->cap) {
        size_t cap = b->cap ? b->cap : 256;
        while (cap < b->len + n) {
            cap *= 2;
        }
        char *d = realloc(b->data, cap);
        if (d == NULL) {
            ms_oom();
        }
        b->data = d;
        b->cap = cap;
    }
    void *p = b->data + b->len;
    b->len += n;
    return p;
}

void ms_buf_put(MsBuf *b, const void *p, size_t n) {
    if (n != 0) {
        memcpy(ms_buf_push(b, n), p, n);
    }
}

void ms_buf_putc(MsBuf *b, char c) {
    *(char *)ms_buf_push(b, 1) = c;
}

void ms_buf_puts(MsBuf *b, const char *s) {
    ms_buf_put(b, s, strlen(s));
}

void ms_buf_printf(MsBuf *b, const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    va_list again;
    va_copy(again, ap);
    int n = vsnprintf(NULL, 0, fmt, ap);
    va_end(ap);
    if (n < 0) {
        ms_oom();
    }
    char *d = ms_buf_push(b, (size_t)n + 1);
    vsnprintf(d, (size_t)n + 1, fmt, again);
    va_end(again);
    b->len--; /* drop the NUL */
}

/* ---- names ---- */

static uint32_t hash_bytes(const char *s, size_t n) {
    uint32_t h = 2166136261u; /* FNV-1a */
    for (size_t i = 0; i < n; i++) {
        h = (h ^ (uint8_t)s[i]) * 16777619u;
    }
    return h;
}

static void names_grow_table(MsNames *n) {
    uint32_t size = n->mask ? (n->mask + 1) * 2 : 1024;
    uint32_t *table = calloc(size, sizeof(uint32_t));
    if (table == NULL) {
        ms_oom();
    }
    for (uint32_t i = 0; i < n->count; i++) {
        uint32_t h = hash_bytes(n->text[i], n->len[i]) & (size - 1);
        while (table[h] != 0) {
            h = (h + 1) & (size - 1);
        }
        table[h] = i + 1;
    }
    free(n->table);
    n->table = table;
    n->mask = size - 1;
}

void ms_names_init(MsNames *n) {
    memset(n, 0, sizeof *n);
    names_grow_table(n);
    ms_intern(n, "", 0); /* symbol 0 */
}

void ms_names_free(MsNames *n) {
    free(n->text);
    free(n->len);
    free(n->table);
    ms_arena_free(&n->arena);
    memset(n, 0, sizeof *n);
}

MsSym ms_intern(MsNames *n, const char *s, size_t len) {
    uint32_t h = hash_bytes(s, len) & n->mask;
    while (n->table[h] != 0) {
        uint32_t id = n->table[h] - 1;
        if (n->len[id] == len && memcmp(n->text[id], s, len) == 0) {
            return id;
        }
        h = (h + 1) & n->mask;
    }
    if (n->count == n->cap) {
        uint32_t cap = n->cap ? n->cap * 2 : 1024;
        const char **text = realloc((void *)n->text, cap * sizeof *text);
        uint32_t *lens = realloc(n->len, cap * sizeof *lens);
        if (text == NULL || lens == NULL) {
            ms_oom();
        }
        n->text = text;
        n->len = lens;
        n->cap = cap;
    }
    uint32_t id = n->count++;
    n->text[id] = ms_arena_strndup(&n->arena, s, len);
    n->len[id] = (uint32_t)len;
    n->table[h] = id + 1;
    if ((uint64_t)n->count * 2 > n->mask) {
        names_grow_table(n);
    }
    return id;
}

MsSym ms_intern_cstr(MsNames *n, const char *s) {
    return ms_intern(n, s, strlen(s));
}

/* ---- UTF-8 ---- */

bool ms_utf8_valid(const char *s, size_t n) {
    const uint8_t *p = (const uint8_t *)s;
    size_t i = 0;
    while (i < n) {
        uint8_t b = p[i];
        if (b < 0x80) {
            i++;
        } else if (b >= 0xC2 && b <= 0xDF) {
            if (i + 1 >= n || (p[i + 1] & 0xC0) != 0x80) {
                return false;
            }
            i += 2;
        } else if (b >= 0xE0 && b <= 0xEF) {
            if (i + 2 >= n || (p[i + 1] & 0xC0) != 0x80 || (p[i + 2] & 0xC0) != 0x80) {
                return false;
            }
            if (b == 0xE0 && p[i + 1] < 0xA0) {
                return false; /* overlong */
            }
            if (b == 0xED && p[i + 1] >= 0xA0) {
                return false; /* surrogate */
            }
            i += 3;
        } else if (b >= 0xF0 && b <= 0xF4) {
            if (i + 3 >= n || (p[i + 1] & 0xC0) != 0x80 || (p[i + 2] & 0xC0) != 0x80 ||
                (p[i + 3] & 0xC0) != 0x80) {
                return false;
            }
            if (b == 0xF0 && p[i + 1] < 0x90) {
                return false; /* overlong */
            }
            if (b == 0xF4 && p[i + 1] >= 0x90) {
                return false; /* beyond U+10FFFF */
            }
            i += 4;
        } else {
            return false;
        }
    }
    return true;
}

int ms_utf8_decode(const char *s, size_t n, uint32_t *scalar) {
    const uint8_t *p = (const uint8_t *)s;
    if (n == 0) {
        *scalar = 0;
        return 0;
    }
    if (p[0] < 0x80) {
        *scalar = p[0];
        return 1;
    }
    if (p[0] < 0xE0 && n >= 2) {
        *scalar = ((uint32_t)(p[0] & 0x1F) << 6) | (p[1] & 0x3F);
        return 2;
    }
    if (p[0] < 0xF0 && n >= 3) {
        *scalar = ((uint32_t)(p[0] & 0x0F) << 12) | ((uint32_t)(p[1] & 0x3F) << 6) | (p[2] & 0x3F);
        return 3;
    }
    if (n >= 4) {
        *scalar = ((uint32_t)(p[0] & 0x07) << 18) | ((uint32_t)(p[1] & 0x3F) << 12) |
                  ((uint32_t)(p[2] & 0x3F) << 6) | (p[3] & 0x3F);
        return 4;
    }
    *scalar = 0xFFFD;
    return 1;
}

void ms_utf8_put(MsBuf *b, uint32_t scalar) {
    uint8_t encoded[4];
    const size_t width = ms_utf8_encode(scalar, encoded);
    for (size_t i = 0; i < width; i++) {
        ms_buf_putc(b, (char)encoded[i]);
    }
}
