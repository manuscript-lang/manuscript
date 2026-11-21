/* Unit tests for src/runtime/net/addr_text.c: both families, the compression rules, scopes, and refusals. */
#include <stdio.h>
#include <string.h>

#include "../net/addr_text.h"

static int failed;
#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #c); failed = 1; } } while (0)

static MsBytes text(const char *s) { return ms_bytes_of((const uint8_t *)s, strlen(s)); }

/* Parses `input` and checks it formats back to `expected`. */
static void round_trip(const char *input, const char *expected) {
    MsAddr address;
    char out[MS_NET_ADDR_TEXT_MAX];
    size_t length = 0;
    CHECK(ms_net_addr_parse(text(input), &address));
    CHECK(ms_net_addr_format(&address, out, sizeof out, &length));
    CHECK(length == strlen(expected) && strcmp(out, expected) == 0);
    if (strcmp(out, expected) != 0) printf("  %s -> %s (wanted %s)\n", input, out, expected);
}

static void refused(const char *input) {
    MsAddr address;
    CHECK(!ms_net_addr_parse(text(input), &address));
    if (ms_net_addr_parse(text(input), &address)) printf("  accepted %s\n", input);
}

int main(void) {
    round_trip("1.2.3.4:80", "1.2.3.4:80");
    round_trip("0.0.0.0:0", "0.0.0.0:0");
    round_trip("255.255.255.255:65535", "255.255.255.255:65535");
    round_trip("[::1]:8080", "[::1]:8080");
    round_trip("[::]:1", "[::]:1");
    round_trip("[2001:db8::1]:443", "[2001:db8::1]:443");
    round_trip("[2001:0db8:0000:0000:0000:0000:0000:0001]:443", "[2001:db8::1]:443");
    round_trip("[2001:db8:0:0:1:0:0:1]:1", "[2001:db8::1:0:0:1]:1"); /* the first of two equal runs */
    round_trip("[1:0:2:3:4:5:6:7]:1", "[1:0:2:3:4:5:6:7]:1");        /* a single zero group is not compressed */
    round_trip("[fe80::1%3]:22", "[fe80::1%3]:22");
    round_trip("[::ffff:1.2.3.4]:9", "[::ffff:102:304]:9");
    round_trip("[1:2:3:4:5:6:7:8]:9", "[1:2:3:4:5:6:7:8]:9");
    round_trip("[ABCD::EF]:9", "[abcd::ef]:9");

    MsAddr a;
    CHECK(ms_net_ip_parse(text("10.0.0.1"), &a) && a.family == 4 && a.ip[0] == 10 && a.port == 0);
    CHECK(ms_net_ip_parse(text("::1"), &a) && a.family == 6 && a.ip[15] == 1);
    CHECK(!ms_net_ip_parse(text("localhost"), &a));

    refused("");
    refused("1.2.3.4");
    refused("1.2.3.4:");
    refused("1.2.3.4:65536");
    refused("1.2.3.4:-1");
    refused("1.2.3:80");
    refused("1.2.3.4.5:80");
    refused("256.1.1.1:80");
    refused("01.2.3.4:80");
    refused("example.com:80");
    refused("::1:80");       /* a bare IPv6 literal needs brackets */
    refused("[::1]");
    refused("[::1]80");
    refused("[1.2.3.4]:80"); /* brackets are for IPv6 */
    refused("[1:2:3:4:5:6:7:8:9]:1");
    refused("[1:2:3:4:5:6:7]:1");
    refused("[1::2::3]:1");
    refused("[:1]:1");
    refused("[1:]:1");
    refused("[12345::]:1");
    refused("[fe80::1%]:1");

    char small[8];
    size_t length;
    a = (MsAddr){.family = 4, .ip = {1, 2, 3, 4}, .port = 80};
    CHECK(!ms_net_addr_format(&a, small, sizeof small, &length));
    puts(failed ? "addr_text_test: FAILED" : "addr_text_test: ok");
    return failed;
}
