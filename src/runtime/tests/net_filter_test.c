/* Unit tests for src/runtime/net/net_filter.c: the rules of src/stdlib/net/policy.ms in C. */
#include <stdio.h>
#include <string.h>

#include "../net/addr_text.h"
#include "../net/net_filter.h"

static int failed;
#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #c); failed = 1; } } while (0)

static MsBytes text(const char *s) { return ms_bytes_of((const uint8_t *)s, strlen(s)); }

static bool address_ok(const MsNetFilter *filter, const char *ip) {
    MsAddr address;
    CHECK(ms_net_ip_parse(text(ip), &address));
    return ms_net_filter_address_allowed(filter, &address);
}

int main(void) {
    MsNetFilter *open = ms_net_filter_new();
    CHECK(ms_net_filter_host_allowed(open, text("anything.example")) && address_ok(open, "8.8.8.8")); /* no level: everything */

    /* hosts only: names compare folded; no ranges, so any resolved address of an allowed name is fine */
    MsNetFilter *hosts = ms_net_filter_new();
    const MsBytes names[] = {text("Example.COM."), text("10.0.0.5")};
    CHECK(ms_net_filter_narrow(hosts, names, 2, NULL, 0));
    CHECK(ms_net_filter_host_allowed(hosts, text("example.com")) && ms_net_filter_host_allowed(hosts, text("EXAMPLE.com.")));
    CHECK(!ms_net_filter_host_allowed(hosts, text("www.example.com")) && !ms_net_filter_host_allowed(hosts, text("other.example")));
    CHECK(ms_net_filter_host_allowed(hosts, text("10.0.0.5")) && address_ok(hosts, "93.184.216.34"));

    /* ranges: an IP literal host must lie in one; resolved addresses must too */
    MsNetFilter *ranges = ms_net_filter_new();
    const MsBytes cidrs[] = {text("10.0.0.0/8"), text("2001:db8::/32"), text("192.168.1.128/25")};
    CHECK(ms_net_filter_narrow(ranges, NULL, 0, cidrs, 3));
    CHECK(ms_net_filter_host_allowed(ranges, text("10.255.0.1")) && !ms_net_filter_host_allowed(ranges, text("11.0.0.1")));
    CHECK(!ms_net_filter_host_allowed(ranges, text("example.com"))); /* a name is not a literal in a range */
    CHECK(address_ok(ranges, "10.1.2.3") && address_ok(ranges, "2001:db8::1") && !address_ok(ranges, "2001:db9::1"));
    CHECK(address_ok(ranges, "192.168.1.200") && !address_ok(ranges, "192.168.1.100") && !address_ok(ranges, "192.168.2.200"));

    /* levels only narrow: a request must pass every one */
    CHECK(ms_net_filter_narrow(ranges, names, 2, NULL, 0));
    CHECK(ms_net_filter_host_allowed(ranges, text("10.0.0.5")) && !ms_net_filter_host_allowed(ranges, text("10.0.0.6")));
    CHECK(address_ok(ranges, "10.1.2.3") && !address_ok(ranges, "93.184.216.34")); /* the host-only level passes any address; the first level holds */

    /* invalid CIDR text changes nothing */
    const MsBytes bad[] = {text("10.0.0.0/33")};
    const MsBytes bad_family[] = {text("::1/129")};
    const MsBytes no_bits[] = {text("10.0.0.0")};
    CHECK(!ms_net_filter_narrow(hosts, NULL, 0, bad, 1) && !ms_net_filter_narrow(hosts, NULL, 0, bad_family, 1) && !ms_net_filter_narrow(hosts, NULL, 0, no_bits, 1));
    CHECK(ms_net_filter_host_allowed(hosts, text("example.com")));

    ms_net_filter_free(open);
    ms_net_filter_free(hosts);
    ms_net_filter_free(ranges);
    puts(failed ? "net_filter_test: FAILED" : "net_filter_test: ok");
    return failed;
}
