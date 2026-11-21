/* The IP natives of @std/net/ip (ms_rt/net.h): IpAddress and Cidr are runtime objects holding a family and the address
 * bytes. Text follows RFC 5952, an IPv4-mapped IPv6 address is an IPv4 address, and a zone ("%eth0") is refused. The
 * parser and the formatter of addr_text.c do the text work. */
#include <stdio.h>
#include <string.h>

#include "../std/abi.h"
#include "addr_text.h"
#include "status.h"
#include "ms_rt/alloc.h"
#include "ms_rt/net.h"
#include "ms_rt/safe.h"

enum { IP_V4_BYTES = 4, IP_V6_BYTES = 16, IP_V4_BITS = 32, IP_V6_BITS = 128, IP_MAX_DIGITS = 3 };

struct MsIpCell {
    MsObj header;
    MsAddr address; /* port 0, no scope */
};

struct MsCidrCell {
    MsObj header;
    MsAddr address; /* masked */
    int bits;
};


static void cell_drop_entry(MsObj *object) { msrt_free(object); }

static MsIpCell *ip_new(const MsAddr *address) {
    MsIpCell *const cell = msrt_alloc(sizeof *cell);
    cell->header.clone = NULL;
    cell->header.drop = cell_drop_entry;
    cell->address = *address;
    return cell;
}

static MsCidrCell *cidr_new(const MsAddr *address, int bits) {
    MsCidrCell *const cell = msrt_alloc(sizeof *cell);
    cell->header.clone = NULL;
    cell->header.drop = cell_drop_entry;
    cell->address = *address;
    cell->bits = bits;
    return cell;
}

static size_t address_size(const MsAddr *address) { return address->family == 4 ? IP_V4_BYTES : IP_V6_BYTES; }

/* Whether `address` is ::ffff:a.b.c.d. */
static bool is_mapped(const MsAddr *address) {
    static const uint8_t prefix[IP_V6_BYTES - IP_V4_BYTES] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xff};
    return address->family == 6 && memcmp(address->ip, prefix, sizeof prefix) == 0;
}

/* Reads an address without a zone. */
static bool parse_address(MsBytes text, MsAddr *out) {
    if (memchr(text.ptr, '%', text.len) != NULL) {
        return false;
    }
    return ms_net_ip_parse(text, out);
}

/* The IPv4 address an IPv4-mapped address stands for; any other address stays. */
static void normalize(MsAddr *address) {
    if (!is_mapped(address)) {
        return;
    }
    MsAddr v4 = {.family = 4};
    memcpy(v4.ip, address->ip + (IP_V6_BYTES - IP_V4_BYTES), IP_V4_BYTES);
    *address = v4;
}

/* Writes the address alone, which addr_text.c formats with its port: "1.2.3.4:0" and "[::1]:0". Returns the length. */
static size_t bare_text(const MsAddr *address, char *out, size_t capacity) {
    char text[MS_NET_ADDR_TEXT_MAX];
    size_t length = 0;
    if (!ms_net_addr_format(address, text, sizeof text, &length) || length < 3 || length >= capacity) {
        return 0;
    }
    const char *const first = address->family == 6 ? text + 1 : text; /* past the bracket */
    const size_t suffix = address->family == 6 ? 3 : 2;               /* "]:0" or ":0" */
    const size_t used = length - suffix - (size_t)(first - text);
    memcpy(out, first, used);
    out[used] = '\0';
    return used;
}

/* Writes the canonical text of `address`: IPv4 mapped addresses keep their dotted tail ("::ffff:192.0.2.0"). */
static void write_text(const MsAddr *address, MsStr *out) {
    char text[MS_NET_ADDR_TEXT_MAX];
    size_t length = 0;
    if (is_mapped(address)) {
        const uint8_t *tail = address->ip + (IP_V6_BYTES - IP_V4_BYTES);
        length = (size_t)snprintf(text, sizeof text, "::ffff:%u.%u.%u.%u", tail[0], tail[1], tail[2], tail[3]);
    } else {
        length = bare_text(address, text, sizeof text);
    }
    msrt_string_from_bytes((const uint8_t *)text, length, out);
}

/* The address of `text`, with an IPv4-mapped address as IPv4; false when it is not one. */
static bool parse_ip(const MsStr *text, MsIpCell **out) {
    MsAddr address;
    if (!parse_address(msrt_str_bytes(text), &address)) {
        return false;
    }
    normalize(&address);
    *out = ip_new(&address);
    return true;
}

uint8_t msstd_net_parse_ip(const MsStr *text, MsIpCell **out, MsStr *err) {
    ms_net_clear_text(err);
    return parse_ip(text, out) ? STATUS_OK : STATUS_INVALID_DATA;
}

uint8_t msstd_json_dec_ip(const MsStr *text, MsIpCell **out) { return parse_ip(text, out) ? STATUS_OK : STATUS_INVALID_INPUT; }

void msstd_net_ip_address_text(const MsIpCell *address, MsStr *out) { write_text(&address->address, out); }

uint8_t msstd_net_ip_address_family(const MsIpCell *address) { return address->address.family == 6 ? 1 : 0; }

/* ---- ranges ---- */

/* Clears every bit of `address` after the first `bits`. */
static void mask(MsAddr *address, int bits) {
    const size_t size = address_size(address);
    for (size_t i = 0; i < size; i++) {
        const int first = (int)i * 8;
        if (bits <= first) {
            address->ip[i] = 0;
        } else if (bits < first + 8) {
            address->ip[i] &= (uint8_t)(0xff << (first + 8 - bits));
        }
    }
}

/* Reads the prefix length: one to three digits, no sign, no leading zero. */
static bool parse_bits(MsBytes text, int *bits) {
    if (text.len == 0 || text.len > IP_MAX_DIGITS || (text.len > 1 && text.ptr[0] == '0')) {
        return false;
    }
    int value = 0;
    for (size_t i = 0; i < text.len; i++) {
        if (text.ptr[i] < '0' || text.ptr[i] > '9') {
            return false;
        }
        value = value * 10 + (text.ptr[i] - '0');
    }
    *bits = value;
    return true;
}

/* Reads "address/bits" with the mask applied. A prefix keeps an IPv4-mapped address as IPv6. */
static bool parse_range(MsBytes text, MsAddr *address, int *bits) {
    const uint8_t *slash = memchr(text.ptr, '/', text.len);
    if (slash == NULL) {
        return false;
    }
    const size_t split = (size_t)(slash - text.ptr);
    if (!parse_address(ms_bytes_of(text.ptr, split), address) ||
        !parse_bits(ms_bytes_of(slash + 1, text.len - split - 1), bits)) {
        return false;
    }
    if (*bits > (address->family == 4 ? IP_V4_BITS : IP_V6_BITS)) {
        return false;
    }
    mask(address, *bits);
    return true;
}

static bool parse_cidr(const MsStr *text, MsCidrCell **out) {
    MsAddr address;
    int bits = 0;
    if (!parse_range(msrt_str_bytes(text), &address, &bits)) {
        return false;
    }
    *out = cidr_new(&address, bits);
    return true;
}

uint8_t msstd_net_parse_cidr(const MsStr *text, MsCidrCell **out, MsStr *err) {
    ms_net_clear_text(err);
    return parse_cidr(text, out) ? STATUS_OK : STATUS_INVALID_DATA;
}

uint8_t msstd_json_dec_cidr(const MsStr *text, MsCidrCell **out) { return parse_cidr(text, out) ? STATUS_OK : STATUS_INVALID_INPUT; }

void msstd_net_cidr_text(const MsCidrCell *range, MsStr *out) {
    MsStr address;
    write_text(&range->address, &address);
    char text[MS_NET_ADDR_TEXT_MAX + 8];
    const int length = snprintf(text, sizeof text, "%.*s/%d", (int)msrt_str_len(&address), msrt_str_data(&address), range->bits);
    msrt_string_free(&address);
    msrt_string_from_bytes((const uint8_t *)text, length > 0 ? (size_t)length : 0, out);
}

uint8_t msstd_net_contains_ip(const MsCidrCell *range, const MsIpCell *address, uint8_t *out) {
    MsAddr masked = address->address;
    mask(&masked, range->bits);
    *out = masked.family == range->address.family &&
           memcmp(masked.ip, range->address.ip, address_size(&masked)) == 0;
    return STATUS_OK;
}
