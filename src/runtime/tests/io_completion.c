/* Unit test of the reactor's completions (src/runtime/io/reactor.c): work on the thread pool, name resolution, and the
 * limit on outstanding completions. Run under the sanitizers by `make c-test`. */
#define _POSIX_C_SOURCE 200809L /* the socket and name-resolution types under -std=c11 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#include "../io/reactor.h"

#define CHECK(condition)                                                                \
    do {                                                                                \
        if (!(condition)) {                                                             \
            fprintf(stderr, "%s:%d: check failed: %s\n", __FILE__, __LINE__, #condition); \
            exit(1);                                                                    \
        }                                                                               \
    } while (0)

enum { CAPACITY = 8, SECOND = 1000000000, FIRST_ID = 100 };

static int32_t add_seven(void *argument) {
    int *value = argument;
    return *value + 7;
}

/* Waits (at most five seconds) until a completion arrives, then takes it. */
static MsIoEvent next_completion(void) {
    MsIoReady ready[CAPACITY];
    size_t count = 0;
    for (int attempt = 0; attempt < 5; attempt++) {
        MsIoEvent event;
        if (ms_io_completion(&event)) {
            return event;
        }
        CHECK(ms_io_wait(SECOND, ready, CAPACITY, &count));
    }
    fprintf(stderr, "%s:%d: no completion arrived\n", __FILE__, __LINE__);
    exit(1);
}

static void test_work_completes_with_its_result(void) {
    int value = 35;
    CHECK(ms_io_work(add_seven, &value, FIRST_ID));
    const MsIoEvent event = next_completion();
    CHECK(event.kind == MS_IO_WORK && event.id == FIRST_ID && event.result == 42);
    MsIoEvent none;
    CHECK(!ms_io_completion(&none));
}

static void test_outstanding_completions_are_bounded(void) {
    int value = 0;
    int accepted = 0;
    while (ms_io_work(add_seven, &value, FIRST_ID + (uint64_t)accepted)) {
        accepted++;
    }
    CHECK(accepted == MS_IO_MAX_COMPLETIONS);
    for (int index = 0; index < accepted; index++) {
        const MsIoEvent event = next_completion();
        CHECK(event.kind == MS_IO_WORK && event.result == 7);
    }
    CHECK(ms_io_work(add_seven, &value, FIRST_ID)); /* room again once collected */
    CHECK(next_completion().kind == MS_IO_WORK);
}

static void test_resolve_finds_the_loopback_address(void) {
    MsIoAddresses *addresses = NULL;
    CHECK(ms_io_resolve("127.0.0.1", "8080", FIRST_ID + 1, &addresses));
    const MsIoEvent event = next_completion();
    CHECK(event.kind == MS_IO_RESOLVE && event.id == FIRST_ID + 1 && event.result == 0);
    CHECK(ms_io_addresses_count(addresses) >= 1);
    MsIoAddress first;
    CHECK(ms_io_addresses_at(addresses, 0, &first));
    CHECK(first.family == AF_INET && first.length > 0);
    CHECK(!ms_io_addresses_at(addresses, ms_io_addresses_count(addresses), &first));
    ms_io_addresses_free(addresses);
}

static void test_resolve_reports_an_error(void) {
    MsIoAddresses *addresses = NULL;
    CHECK(ms_io_resolve("host.invalid", "80", FIRST_ID + 2, &addresses));
    const MsIoEvent event = next_completion();
    CHECK(event.kind == MS_IO_RESOLVE && event.result < 0);
    CHECK(ms_io_addresses_count(addresses) == 0);
    ms_io_addresses_free(addresses);
}

static uint64_t sunk_id;
static int32_t sunk_result;
static uint32_t sunk_kind;

static void record_completion(uint64_t id, int32_t result, uint32_t kind) {
    sunk_id = id;
    sunk_result = result;
    sunk_kind = kind;
}

/* With a sink installed, ms_io_wait hands completions over itself instead of leaving them on the ring. */
static void test_sink_receives_completions(void) {
    MsIoReady ready[CAPACITY];
    size_t count = 0;
    int value = 1;
    ms_io_set_completion_sink(record_completion);
    CHECK(ms_io_work(add_seven, &value, FIRST_ID + 3));
    for (int attempt = 0; attempt < 5 && sunk_id == 0; attempt++) {
        CHECK(ms_io_wait(SECOND, ready, CAPACITY, &count));
    }
    CHECK(sunk_id == FIRST_ID + 3 && sunk_result == 8 && sunk_kind == MS_IO_WORK);
    ms_io_set_completion_sink(NULL);
}

/* An abandoned resolve neither delivers a completion nor leaks, whether or not it had finished. */
static void test_abandoned_resolve_is_dropped(void) {
    MsIoReady ready[CAPACITY];
    size_t count = 0;
    MsIoAddresses *addresses = NULL;
    CHECK(ms_io_resolve("127.0.0.1", "80", FIRST_ID + 4, &addresses));
    ms_io_addresses_abandon(addresses);
    for (int round = 0; round < 3; round++) {
        CHECK(ms_io_wait(0, ready, CAPACITY, &count));
    }
    MsIoEvent event;
    CHECK(!ms_io_completion(&event));
}

int main(void) {
    MsIoReactor *reactor = NULL;
    CHECK(ms_io_open(false, &reactor));
    test_work_completes_with_its_result();
    test_outstanding_completions_are_bounded();
    test_resolve_finds_the_loopback_address();
    test_resolve_reports_an_error();
    test_sink_receives_completions();
    test_abandoned_resolve_is_dropped();
    ms_io_close(false);
    puts("io_completion: ok");
    return 0;
}
