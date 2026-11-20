/* The completion ring and the loop's scratch read buffer; see ring.h. */
#include "ring.h"
#include <stdlib.h>

struct MsIoRing {
    uint32_t mask;    /* slot count minus one; the slot count is a power of two */
    uint32_t head;    /* next slot to pop; counts up and wraps through the mask */
    uint32_t tail;    /* next slot to push */
    uint32_t dropped; /* pushes refused because the ring was full */
    MsIoEvent slots[]; /* owned by the ring, one allocation with the header */
};

static uint32_t slot_count_for(uint32_t capacity)
{
    uint32_t slots = 2;
    while (slots < capacity && slots < (UINT32_C(1) << 30)) {
        slots <<= 1;
    }
    return slots;
}

MsIoRing *ms_io_ring_new(uint32_t capacity)
{
    const uint32_t slots = slot_count_for(capacity);
    if (slots < capacity) {
        return NULL;
    }
    MsIoRing *ring = calloc(1, sizeof *ring + (size_t)slots * sizeof ring->slots[0]);
    if (ring == NULL) {
        return NULL;
    }
    ring->mask = slots - 1;
    return ring;
}

void ms_io_ring_free(MsIoRing *ring)
{
    free(ring);
}

uint32_t ms_io_ring_length(const MsIoRing *ring)
{
    return ring->tail - ring->head;
}

uint32_t ms_io_ring_dropped(const MsIoRing *ring)
{
    return ring->dropped;
}

bool ms_io_ring_push(MsIoRing *ring, MsIoEvent event)
{
    if (ms_io_ring_length(ring) > ring->mask) {
        ring->dropped++;
        return false;
    }
    ring->slots[ring->tail & ring->mask] = event;
    ring->tail++;
    return true;
}

bool ms_io_ring_pop(MsIoRing *ring, MsIoEvent *event)
{
    if (ring->head == ring->tail) {
        return false;
    }
    *event = ring->slots[ring->head & ring->mask];
    ring->head++;
    return true;
}

bool ms_io_scratch_init(MsIoScratch *scratch, size_t size)
{
    uint8_t *data = malloc(size);
    if (data == NULL) {
        return false;
    }
    scratch->data = data;
    scratch->size = size;
    return true;
}

void ms_io_scratch_release(MsIoScratch *scratch)
{
    free(scratch->data);
    scratch->data = NULL;
    scratch->size = 0;
}
