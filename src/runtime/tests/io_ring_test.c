/* Tests for the completion ring and the scratch buffer (src/runtime/io/ring.c). */
#include "../io/ring.h"
#include <stdio.h>
#include <stdlib.h>

#define CHECK(condition)                                                          \
    do {                                                                          \
        if (!(condition)) {                                                       \
            fprintf(stderr, "%s:%d: check failed: %s\n", __FILE__, __LINE__, #condition); \
            exit(1);                                                              \
        }                                                                         \
    } while (0)

static void test_order_and_wrap(void)
{
    MsIoRing *ring = ms_io_ring_new(4);
    CHECK(ring != NULL);
    uint64_t next_push = 1;
    uint64_t next_pop = 1;
    for (int round = 0; round < 1000; round++) {
        for (int i = 0; i < 3; i++) {
            const MsIoEvent event = {.id = next_push++, .result = round, .kind = MS_IO_READ};
            CHECK(ms_io_ring_push(ring, event));
        }
        MsIoEvent popped = {0};
        for (int i = 0; i < 3; i++) {
            CHECK(ms_io_ring_pop(ring, &popped));
            CHECK(popped.id == next_pop++);
            CHECK(popped.result == round);
        }
        CHECK(!ms_io_ring_pop(ring, &popped));
    }
    CHECK(ms_io_ring_length(ring) == 0);
    ms_io_ring_free(ring);
}

static void test_full_ring_refuses_and_counts(void)
{
    MsIoRing *ring = ms_io_ring_new(3); /* rounds up to four slots */
    CHECK(ring != NULL);
    const MsIoEvent event = {.id = 7, .result = -1, .kind = MS_IO_WRITE};
    for (int i = 0; i < 4; i++) {
        CHECK(ms_io_ring_push(ring, event));
    }
    CHECK(!ms_io_ring_push(ring, event));
    CHECK(ms_io_ring_dropped(ring) == 1);
    CHECK(ms_io_ring_length(ring) == 4);
    MsIoEvent popped = {0};
    CHECK(ms_io_ring_pop(ring, &popped));
    CHECK(popped.id == 7 && popped.result == -1 && popped.kind == MS_IO_WRITE);
    CHECK(ms_io_ring_push(ring, event));
    ms_io_ring_free(ring);
}

static void test_scratch(void)
{
    MsIoScratch scratch = {0};
    CHECK(ms_io_scratch_init(&scratch, 65536));
    CHECK(scratch.size == 65536);
    scratch.data[0] = 1;
    scratch.data[scratch.size - 1] = 2;
    ms_io_scratch_release(&scratch);
    CHECK(scratch.data == NULL && scratch.size == 0);
}

int main(void)
{
    test_order_and_wrap();
    test_full_ring_refuses_and_counts();
    test_scratch();
    printf("io ring: %zu bytes per event, 0 bytes per idle connection\n", sizeof(MsIoEvent));
    return 0;
}
