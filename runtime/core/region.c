/* Regions: bump allocation with a byte budget and one-step release. See region.h. */
#include "region.h"

#define ALIGN 16
#define FIRST_CHUNK 4096
#define MAX_CHUNK ((size_t)256 << 10)

typedef struct Chunk {
    struct Chunk *next;
    size_t size; /* bytes of the chunk, header included */
    size_t pad[2];
} Chunk;

struct msregion {
    char *cur;
    char *end;
    Chunk *head; /* the chunk being filled, then older ones */
    Chunk *first; /* the oldest, which holds the region itself */
    size_t budget;
    size_t held;
    size_t used;
    size_t next_chunk;
    size_t pad;
};

#define HEADER_SIZE ((sizeof(Chunk) + sizeof(msregion) + ALIGN - 1) / ALIGN * ALIGN)

static inline size_t round_up(size_t n) {
    return (n + ALIGN - 1) / ALIGN * ALIGN;
}

msregion *msregion_new(size_t budget) {
    if (budget < HEADER_SIZE + ALIGN) {
        return 0;
    }
    size_t size = FIRST_CHUNK < budget ? FIRST_CHUNK : budget;
    Chunk *c = msrt_alloc(size);
    c->next = 0;
    c->size = size;
    msregion *r = (msregion *)(c + 1);
    r->cur = (char *)c + HEADER_SIZE;
    r->end = (char *)c + size;
    r->head = r->first = c;
    r->budget = budget;
    r->held = size;
    r->used = 0;
    r->next_chunk = FIRST_CHUNK * 2;
    return r;
}

static void *alloc_in_new_chunk(msregion *r, size_t need) {
    size_t size = r->next_chunk;
    size_t want = need + sizeof(Chunk);
    if (size < want) {
        size = round_up(want);
    }
    size_t room = r->budget - r->held;
    if (size > room) {
        size = room;
    }
    if (size < want) {
        return 0;
    }
    Chunk *c = msrt_alloc(size);
    c->next = r->head;
    c->size = size;
    r->head = c;
    r->held += size;
    if (r->next_chunk < MAX_CHUNK) {
        r->next_chunk *= 2;
    }
    char *p = (char *)(c + 1);
    r->cur = p + need;
    r->end = (char *)c + size;
    return p;
}

void *msregion_alloc(msregion *r, size_t size) {
    if (size > SIZE_MAX / 2) {
        return 0;
    }
    size_t need = round_up(size ? size : 1);
    if ((size_t)(r->end - r->cur) >= need) {
        char *p = r->cur;
        r->cur = p + need;
        r->used += need;
        return p;
    }
    void *p = alloc_in_new_chunk(r, need);
    if (p) {
        r->used += need;
    }
    return p;
}

void *msregion_alloc_zeroed(msregion *r, size_t size) {
    void *p = msregion_alloc(r, size);
    if (p) {
        __builtin_memset(p, 0, size);
    }
    return p;
}

size_t msregion_used(const msregion *r) {
    return r->used;
}

size_t msregion_held(const msregion *r) {
    return r->held;
}

size_t msregion_budget(const msregion *r) {
    return r->budget;
}

static void free_newer_chunks(msregion *r) {
    Chunk *c = r->head;
    while (c != r->first) {
        Chunk *next = c->next;
        msrt_free(c);
        c = next;
    }
    r->head = r->first;
}

void msregion_reset(msregion *r) {
    free_newer_chunks(r);
    r->cur = (char *)r->first + HEADER_SIZE;
    r->end = (char *)r->first + r->first->size;
    r->held = r->first->size;
    r->used = 0;
    r->next_chunk = FIRST_CHUNK * 2;
}

void msregion_release(msregion *r) {
    if (!r) {
        return;
    }
    free_newer_chunks(r);
    msrt_free(r->first);
}
