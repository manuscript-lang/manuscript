/* Regions: bump allocation with a byte budget and one-step release. See region.h.
 *
 * A region is a chain of chunks. The oldest chunk also holds the MsRegion record itself, so a region is one
 * heap block until it grows. Newer chunks are linked in front and are twice the size of the one before, up to
 * MS_REGION_MAX_CHUNK, or exactly as big as a single request needs. */
#include "region.h"

#define MS_REGION_ALIGN ((size_t)16)
#define MS_REGION_FIRST_CHUNK ((size_t)4096)
#define MS_REGION_MAX_CHUNK ((size_t)256 << 10)

typedef struct MsChunk {
    struct MsChunk *next; /* owned: the next older chunk, null for the oldest */
    size_t size;          /* bytes of the chunk, this header included */
    size_t padding[2];    /* keeps the first block 16-byte aligned */
} MsChunk;

struct MsRegion {
    char *cursor;     /* borrowed from `newest`: the next free byte */
    char *limit;      /* borrowed from `newest`: one past its last byte */
    MsChunk *newest;  /* owned: the chunk being filled */
    MsChunk *oldest;  /* owned: the chunk that holds this record */
    size_t budget;
    size_t held;
    size_t used;
    size_t next_chunk_size;
};

_Static_assert(sizeof(MsChunk) % MS_REGION_ALIGN == 0, "chunk header keeps blocks aligned");

/* Where the first block of the oldest chunk starts: after the chunk header and the region record. */
static size_t first_block_offset(void) {
    return (sizeof(MsChunk) + sizeof(MsRegion) + MS_REGION_ALIGN - 1) / MS_REGION_ALIGN * MS_REGION_ALIGN;
}

/* Rounds `size` up to the alignment; false when that overflows. A zero size takes one alignment unit. */
static bool round_up(size_t size, size_t *out) {
    size_t rounded = 0;
    if (!ms_size_add(size == 0 ? 1 : size, MS_REGION_ALIGN - 1, &rounded)) {
        return false;
    }
    *out = rounded / MS_REGION_ALIGN * MS_REGION_ALIGN;
    return true;
}

static char *chunk_end(MsChunk *chunk) {
    return (char *)chunk + chunk->size;
}

static void start_filling(MsRegion *region, MsChunk *chunk, char *first_free) {
    region->newest = chunk;
    region->cursor = first_free;
    region->limit = chunk_end(chunk);
}

bool ms_region_new(size_t budget, MsRegion **out) {
    const size_t header = first_block_offset();
    if (budget < header + MS_REGION_ALIGN) {
        return false;
    }
    const size_t size = budget < MS_REGION_FIRST_CHUNK ? budget : MS_REGION_FIRST_CHUNK;
    MsChunk *chunk = msrt_alloc(size);
    chunk->next = NULL;
    chunk->size = size;
    MsRegion *region = (MsRegion *)(chunk + 1);
    *region = (MsRegion){
        .oldest = chunk,
        .budget = budget,
        .held = size,
        .next_chunk_size = MS_REGION_FIRST_CHUNK * 2,
    };
    start_filling(region, chunk, (char *)chunk + header);
    *out = region;
    return true;
}

/* Bytes the next chunk takes to hold `need` bytes of blocks: the doubling size, or what the request needs,
 * cut down to the budget that is left. Zero when even that is too little. */
static size_t next_chunk_bytes(const MsRegion *region, size_t need) {
    size_t wanted = 0;
    if (!ms_size_add(need, sizeof(MsChunk), &wanted)) {
        return 0;
    }
    size_t size = region->next_chunk_size > wanted ? region->next_chunk_size : wanted;
    const size_t room = region->budget - region->held;
    if (size > room) {
        size = room;
    }
    return size < wanted ? 0 : size;
}

/* Adds a chunk with room for `need` bytes and hands out the first `need` of them. */
static bool alloc_in_new_chunk(MsRegion *region, size_t need, void **out) {
    const size_t size = next_chunk_bytes(region, need);
    if (size == 0) {
        return false;
    }
    MsChunk *chunk = msrt_alloc(size);
    chunk->next = region->newest;
    chunk->size = size;
    region->held += size;
    if (region->next_chunk_size < MS_REGION_MAX_CHUNK) {
        region->next_chunk_size *= 2;
    }
    char *block = (char *)(chunk + 1);
    start_filling(region, chunk, block + need);
    *out = block;
    return true;
}

bool ms_region_alloc(MsRegion *region, size_t size, void **out) {
    size_t need = 0;
    if (!round_up(size, &need)) {
        return false;
    }
    if ((size_t)(region->limit - region->cursor) >= need) {
        *out = region->cursor;
        region->cursor += need;
        region->used += need;
        return true;
    }
    if (!alloc_in_new_chunk(region, need, out)) {
        return false;
    }
    region->used += need;
    return true;
}

bool ms_region_alloc_zeroed(MsRegion *region, size_t size, void **out) {
    void *block = NULL;
    if (!ms_region_alloc(region, size, &block)) {
        return false;
    }
    __builtin_memset(block, 0, size);
    *out = block;
    return true;
}

size_t ms_region_used(const MsRegion *region) {
    return region->used;
}

size_t ms_region_held(const MsRegion *region) {
    return region->held;
}

size_t ms_region_budget(const MsRegion *region) {
    return region->budget;
}

/* Frees every chunk but the oldest. */
static void free_newer_chunks(MsRegion *region) {
    MsChunk *chunk = region->newest;
    while (chunk != region->oldest) {
        MsChunk *older = chunk->next;
        msrt_free(chunk);
        chunk = older;
    }
    region->newest = region->oldest;
}

void ms_region_reset(MsRegion *region) {
    free_newer_chunks(region);
    MsChunk *oldest = region->oldest;
    start_filling(region, oldest, (char *)oldest + first_block_offset());
    region->held = oldest->size;
    region->used = 0;
    region->next_chunk_size = MS_REGION_FIRST_CHUNK * 2;
}

void ms_region_release(MsRegion *region) {
    if (region == NULL) {
        return;
    }
    free_newer_chunks(region);
    msrt_free(region->oldest);
}
