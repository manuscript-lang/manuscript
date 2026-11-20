/* Unit test of the reactor's completions (runtime/io/reactor.c): work on the thread pool, name resolution, and the
 * limit on outstanding completions. Run under the sanitizers by `make c-test`. */
#define _POSIX_C_SOURCE 200809L /* the socket and name-resolution types under -std=c11 */

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

int main(void) {
    MsIoReactor *reactor = NULL;
    CHECK(ms_io_open(false, &reactor));
    test_work_completes_with_its_result();
    test_outstanding_completions_are_bounded();
    test_resolve_finds_the_loopback_address();
    test_resolve_reports_an_error();
    ms_io_close(false);
    puts("io_completion: ok");
    return 0;
}
