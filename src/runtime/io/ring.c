/* The completion ring; see ring.h. */
#include "runtime/io/ring.h"

#include "base/alloc.h"

struct MsIoRing {
  uint32_t mask;     /* slot count minus one; the slot count is a power of two */
  uint32_t head;     /* next slot to pop; counts up and wraps through the mask */
  uint32_t tail;     /* next slot to push */
  uint32_t dropped;  /* pushes refused because the ring was full */
  MsIoEvent slots[]; /* owned by the ring, one allocation with the header */
};

enum { MAX_SLOTS = 1 << 30 };

MsIoRing *ms_io_ring_new(uint32_t capacity) {
  uint32_t slots = 2;
  while (slots < capacity && slots < MAX_SLOTS) {
    slots <<= 1;
  }
  MsIoRing *ring = ms_alloc_zeroed(sizeof *ring + (size_t)slots * sizeof ring->slots[0]);
  ring->mask = slots - 1;
  return ring;
}

void ms_io_ring_free(MsIoRing *ring) { ms_free(ring); }

uint32_t ms_io_ring_length(const MsIoRing *ring) { return ring->tail - ring->head; }

uint32_t ms_io_ring_capacity(const MsIoRing *ring) { return ring->mask + 1; }

uint32_t ms_io_ring_dropped(const MsIoRing *ring) { return ring->dropped; }

bool ms_io_ring_push(MsIoRing *ring, MsIoEvent event) {
  if (ms_io_ring_length(ring) > ring->mask) {
    ring->dropped++;
    return false;
  }
  ring->slots[ring->tail & ring->mask] = event;
  ring->tail++;
  return true;
}

bool ms_io_ring_pop(MsIoRing *ring, MsIoEvent *event) {
  if (ring->head == ring->tail) {
    return false;
  }
  *event = ring->slots[ring->head & ring->mask];
  ring->head++;
  return true;
}
