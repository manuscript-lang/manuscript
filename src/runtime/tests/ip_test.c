/* Tests for src/runtime/net/ip.c: the address and range vectors of the Rust crate it replaces, containment, and the JSON
 * readers. */
#include <stdio.h>
#include <string.h>

#include "../std/abi.h"
#include "ms_rt/net.h"

static int failed;
#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #c); failed = 1; } } while (0)

typedef struct Vector {
    const char *input;
    const char *want; /* NULL: refused */
} Vector;

static const Vector ADDRESSES[] = {
    {"1.2.3.4", "1.2.3.4"}, {"01.2.3.4", NULL}, {"1.2.3", NULL}, {"256.1.1.1", NULL}, {"::1", "::1"}, {"::", "::"},
    {"2001:0db8::1", "2001:db8::1"}, {"2001:db8:0:0:1:0:0:1", "2001:db8::1:0:0:1"}, {"2001:db8::0:1", "2001:db8::1"},
    {"::ffff:1.2.3.4", "1.2.3.4"}, {"::1.2.3.4", "::102:304"}, {"fe80::1%eth0", NULL}, {"FE80::AB", "fe80::ab"},
    {"1:2:3:4:5:6:7:8", "1:2:3:4:5:6:7:8"}, {"1:0:0:2:0:0:0:3", "1:0:0:2::3"}, {"0:0:0:0:0:0:0:1", "::1"},
    {"::ffff:0:0", "0.0.0.0"}, {"64:ff9b::1.2.3.4", "64:ff9b::102:304"}, {" 1.2.3.4", NULL}, {"1.2.3.4 ", NULL},
    {"", NULL}, {"::g", NULL}, {"1::2::3", NULL}, {"2001:db8:0:1:1:1:1:1", "2001:db8:0:1:1:1:1:1"},
    {"0:1:0:1:0:1:0:1", "0:1:0:1:0:1:0:1"}, {"::127.0.0.1", "::7f00:1"}, {"1.2.3.4.5", NULL}, {"1e2.1.1.1", NULL},
    {"0x1.2.3.4", NULL},
};

static const Vector RANGES[] = {
    {"192.0.2.3/24", "192.0.2.0/24"}, {"10.0.0.0/8", "10.0.0.0/8"}, {"10.0.0.0/08", NULL}, {"10.0.0.0/+8", NULL},
    {"10.0.0.0/33", NULL}, {"10.0.0.0/0", "0.0.0.0/0"}, {"::/0", "::/0"}, {"::1/128", "::1/128"},
    {"2001:db8::5/32", "2001:db8::/32"}, {"::ffff:192.0.2.0/120", "::ffff:192.0.2.0/120"},
    {"::ffff:192.0.2.1/128", "::ffff:192.0.2.1/128"}, {"fe80::1%eth0/64", NULL}, {"1.2.3.4", NULL}, {"1.2.3.4/", NULL},
    {"/8", NULL}, {"1.2.3.4/8/8", NULL}, {"1.2.3.4/-1", NULL}, {"::ffff:1.2.3.4/96", "::ffff:0.0.0.0/96"},
    {"::ffff:1.2.3.4/104", "::ffff:1.0.0.0/104"}, {"192.0.2.0/24 ", NULL}, {"0.0.0.0/32", "0.0.0.0/32"},
};

static MsStr text_of(const char *text) {
    MsStr out;
    msrt_string_from_bytes((const uint8_t *)text, strlen(text), &out);
    return out;
}

static bool says(const MsStr *text, const char *want) {
    return msrt_str_len(text) == strlen(want) && memcmp(msrt_str_data(text), want, strlen(want)) == 0;
}

static MsIpCell *address(const char *text) {
    MsStr input = text_of(text), err;
    MsIpCell *cell = NULL;
    CHECK(msstd_net_parse_ip(&input, &cell, &err) == STATUS_OK && cell != NULL);
    msrt_string_free(&input);
    return cell;
}

static MsCidrCell *range(const char *text) {
    MsStr input = text_of(text), err;
    MsCidrCell *cell = NULL;
    CHECK(msstd_net_parse_cidr(&input, &cell, &err) == STATUS_OK && cell != NULL);
    msrt_string_free(&input);
    return cell;
}

static bool contains(const char *cidr, const char *ip) {
    MsCidrCell *const r = range(cidr);
    MsIpCell *const a = address(ip);
    uint8_t found = 0;
    CHECK(msstd_net_contains_ip(r, a, &found) == STATUS_OK);
    ((MsObj *)r)->drop((MsObj *)r);
    ((MsObj *)a)->drop((MsObj *)a);
    return found != 0;
}

int main(void) {
    for (size_t i = 0; i < sizeof ADDRESSES / sizeof ADDRESSES[0]; i++) {
        MsStr input = text_of(ADDRESSES[i].input), err, shown;
        MsIpCell *cell = NULL;
        const uint8_t status = msstd_net_parse_ip(&input, &cell, &err);
        if (ADDRESSES[i].want == NULL) {
            CHECK(status == STATUS_INVALID_DATA);
            if (status != STATUS_INVALID_DATA) printf("  address %s\n", ADDRESSES[i].input);
        } else {
            CHECK(status == STATUS_OK);
            if (status == STATUS_OK) {
                msstd_net_ip_address_text(cell, &shown);
                CHECK(says(&shown, ADDRESSES[i].want));
                if (!says(&shown, ADDRESSES[i].want)) printf("  address %s\n", ADDRESSES[i].input);
                msrt_string_free(&shown);
                ((MsObj *)cell)->drop((MsObj *)cell);
            }
        }
        msrt_string_free(&input);
        msrt_string_free(&err);
    }
    for (size_t i = 0; i < sizeof RANGES / sizeof RANGES[0]; i++) {
        MsStr input = text_of(RANGES[i].input), err, shown;
        MsCidrCell *cell = NULL;
        const uint8_t status = msstd_net_parse_cidr(&input, &cell, &err);
        if (RANGES[i].want == NULL) {
            CHECK(status == STATUS_INVALID_DATA);
            if (status != STATUS_INVALID_DATA) printf("  range %s\n", RANGES[i].input);
        } else {
            CHECK(status == STATUS_OK);
            if (status == STATUS_OK) {
                msstd_net_cidr_text(cell, &shown);
                CHECK(says(&shown, RANGES[i].want));
                if (!says(&shown, RANGES[i].want)) printf("  range %s\n", RANGES[i].input);
                msrt_string_free(&shown);
                ((MsObj *)cell)->drop((MsObj *)cell);
            }
        }
        msrt_string_free(&input);
        msrt_string_free(&err);
    }

    /* containment needs the same family */
    CHECK(contains("192.0.2.0/24", "192.0.2.255"));
    CHECK(!contains("192.0.2.0/24", "192.0.3.0"));
    CHECK(!contains("192.0.2.0/24", "2001:db8::1"));
    CHECK(!contains("::ffff:192.0.2.0/120", "::ffff:192.0.2.1")); /* the address is IPv4 */
    CHECK(contains("0.0.0.0/0", "8.8.8.8"));
    CHECK(contains("2001:db8::/32", "2001:db8:1::1"));
    CHECK(!contains("2001:db8::/32", "2001:db9::1"));

    /* the family index and the JSON readers */
    {
        MsIpCell *const v4 = address("1.2.3.4"), *const v6 = address("::1");
        CHECK(msstd_net_ip_address_family(v4) == 0 && msstd_net_ip_address_family(v6) == 1);
        ((MsObj *)v4)->drop((MsObj *)v4);
        ((MsObj *)v6)->drop((MsObj *)v6);
        MsStr good = text_of("10.0.0.1"), bad = text_of("nope"), net = text_of("10.0.0.0/8");
        MsIpCell *a = NULL;
        MsCidrCell *c = NULL;
        CHECK(msstd_json_dec_ip(&good, &a) == STATUS_OK && a != NULL);
        CHECK(msstd_json_dec_ip(&bad, &a) == STATUS_INVALID_INPUT);
        CHECK(msstd_json_dec_cidr(&net, &c) == STATUS_OK && c != NULL);
        CHECK(msstd_json_dec_cidr(&bad, &c) == STATUS_INVALID_INPUT);
        ((MsObj *)a)->drop((MsObj *)a);
        ((MsObj *)c)->drop((MsObj *)c);
        msrt_string_free(&good);
        msrt_string_free(&bad);
        msrt_string_free(&net);
    }
    if (!failed) printf("ip ok\n");
    return failed;
}
