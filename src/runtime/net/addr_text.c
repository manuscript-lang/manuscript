/* Address text (addr_text.h). */
#include "addr_text.h"

#include <stdio.h>
#include <string.h>

#include "ms_rt/chars.h"

enum { V6_GROUPS = 8 };

/* ---- reading ---- */

/* Reads decimal digits at *at into *value (at most `limit`); false when there are none or it is too big. */
static bool read_decimal(MsBytes text, size_t *at, uint32_t limit, uint32_t *value) {
    size_t i = *at;
    uint64_t number = 0;
    while (i < text.len && ms_ascii_is_digit(text.ptr[i])) {
        number = number * 10 + (uint64_t)(text.ptr[i] - '0');
        if (number > limit) {
            return false;
        }
        i++;
    }
    if (i == *at) {
        return false;
    }
    *value = (uint32_t)number;
    *at = i;
    return true;
}

static bool parse_v4(MsBytes text, uint8_t out[4]) {
    size_t at = 0;
    for (size_t part = 0; part < 4; part++) {
        const size_t start = at;
        uint32_t value = 0;
        if (!read_decimal(text, &at, 255, &value) || (at - start > 1 && text.ptr[start] == '0')) {
            return false; /* a leading zero reads as octal in some parsers: refused */
        }
        out[part] = (uint8_t)value;
        if (part < 3) {
            if (at >= text.len || text.ptr[at] != '.') {
                return false;
            }
            at++;
        }
    }
    return at == text.len;
}

/* Reads one group of up to four hex digits. */
static bool read_group(MsBytes text, size_t *at, uint16_t *value) {
    size_t i = *at;
    uint32_t number = 0;
    uint32_t digit = 0;
    while (i < text.len && i - *at < 4 && ms_hex_digit_value(text.ptr[i], &digit)) {
        number = number * 16 + digit;
        i++;
    }
    if (i == *at) {
        return false;
    }
    *value = (uint16_t)number;
    *at = i;
    return true;
}

/* Reads the groups of one side of a "::" (or the whole address): hex groups separated by ':', the last one possibly
 * an IPv4 tail that counts for two. An empty side has no groups. */
static bool read_side(MsBytes side, uint16_t groups[V6_GROUPS], size_t *count) {
    *count = 0;
    if (side.len == 0) {
        return true;
    }
    size_t at = 0;
    for (;;) {
        if (*count == V6_GROUPS) {
            return false;
        }
        size_t end = at;
        while (end < side.len && side.ptr[end] != ':') {
            end++;
        }
        const MsBytes token = ms_bytes_of(side.ptr + at, end - at);
        bool dotted = false;
        for (size_t i = 0; i < token.len; i++) {
            dotted = dotted || token.ptr[i] == '.';
        }
        if (dotted) {
            uint8_t v4[4];
            if (end != side.len || *count + 2 > V6_GROUPS || !parse_v4(token, v4)) {
                return false;
            }
            groups[(*count)++] = (uint16_t)(v4[0] << 8 | v4[1]);
            groups[(*count)++] = (uint16_t)(v4[2] << 8 | v4[3]);
            return true;
        }
        size_t used = 0;
        if (!read_group(token, &used, &groups[*count]) || used != token.len) {
            return false;
        }
        (*count)++;
        if (end == side.len) {
            return true;
        }
        at = end + 1;
        if (at == side.len) {
            return false; /* a trailing ':' */
        }
    }
}

static bool parse_v6(MsBytes text, MsAddr *out) {
    size_t scope_at = text.len;
    for (size_t i = 0; i < text.len; i++) {
        if (text.ptr[i] == '%') {
            scope_at = i;
            break;
        }
    }
    uint32_t scope = 0;
    if (scope_at < text.len) {
        size_t at = scope_at + 1;
        if (!read_decimal(text, &at, UINT32_MAX, &scope) || at != text.len) {
            return false;
        }
    }
    const MsBytes body = ms_bytes_of(text.ptr, scope_at);
    size_t gap = body.len; /* where "::" starts, or body.len for none */
    for (size_t i = 0; i + 1 < body.len; i++) {
        if (body.ptr[i] == ':' && body.ptr[i + 1] == ':') {
            gap = i;
            break;
        }
    }
    uint16_t left[V6_GROUPS] = {0}, right[V6_GROUPS] = {0};
    size_t nleft = 0, nright = 0;
    const bool has_gap = gap < body.len;
    if (!read_side(ms_bytes_of(body.ptr, gap), left, &nleft)) {
        return false;
    }
    if (has_gap && (!read_side(ms_bytes_of(body.ptr + gap + 2, body.len - gap - 2), right, &nright) || nleft + nright > V6_GROUPS - 1)) {
        return false;
    }
    if (!has_gap && nleft != V6_GROUPS) {
        return false;
    }
    *out = (MsAddr){.family = 6, .scope = scope};
    for (size_t i = 0; i < V6_GROUPS; i++) {
        uint16_t group = 0;
        if (i < nleft) {
            group = left[i];
        } else if (i >= V6_GROUPS - nright) {
            group = right[i - (V6_GROUPS - nright)];
        }
        out->ip[2 * i] = (uint8_t)(group >> 8);
        out->ip[2 * i + 1] = (uint8_t)(group & 0xff);
    }
    return true;
}

bool ms_net_ip_parse(MsBytes text, MsAddr *out) {
    bool colon = false;
    for (size_t i = 0; i < text.len; i++) {
        colon = colon || text.ptr[i] == ':';
    }
    if (colon) {
        return parse_v6(text, out);
    }
    MsAddr address = {.family = 4};
    if (!parse_v4(text, address.ip)) {
        return false;
    }
    *out = address;
    return true;
}

bool ms_net_addr_parse(MsBytes text, MsAddr *out) {
    const bool bracket = text.len > 0 && text.ptr[0] == '[';
    size_t colon = 0; /* the ':' that starts the port */
    if (bracket) {
        size_t close = 1;
        while (close < text.len && text.ptr[close] != ']') {
            close++;
        }
        if (close + 1 >= text.len || text.ptr[close + 1] != ':') {
            return false;
        }
        colon = close + 1;
    } else {
        size_t colons = 0;
        for (size_t i = 0; i < text.len; i++) {
            if (text.ptr[i] == ':') {
                colons++;
                colon = i;
            }
        }
        if (colons != 1) { /* a bare IPv6 literal has more and needs brackets */
            return false;
        }
    }
    const MsBytes host = bracket ? ms_bytes_of(text.ptr + 1, colon - 2) : ms_bytes_of(text.ptr, colon);
    size_t at = colon + 1;
    uint32_t port = 0;
    MsAddr address;
    if (!read_decimal(text, &at, 65535, &port) || at != text.len || !ms_net_ip_parse(host, &address)) {
        return false;
    }
    if (bracket != (address.family == 6)) {
        return false; /* brackets are for IPv6 only */
    }
    address.port = (uint16_t)port;
    *out = address;
    return true;
}

/* ---- writing ---- */

static uint16_t group_at(const MsAddr *a, size_t i) { return (uint16_t)(a->ip[2 * i] << 8 | a->ip[2 * i + 1]); }

/* Writes the IPv6 groups of `a` with the RFC 5952 compression into `out`. */
static int format_v6(const MsAddr *a, char *out, size_t capacity) {
    size_t best_start = 0, best_len = 0;
    for (size_t i = 0; i < V6_GROUPS;) {
        size_t run = 0;
        while (i + run < V6_GROUPS && group_at(a, i + run) == 0) {
            run++;
        }
        if (run > best_len) {
            best_start = i;
            best_len = run;
        }
        i += run == 0 ? 1 : run;
    }
    if (best_len < 2) {
        best_len = 0;
    }
    size_t used = 0;
    for (size_t i = 0; i < V6_GROUPS; i++) {
        int n;
        if (best_len > 0 && i == best_start) {
            n = snprintf(out + used, capacity - used, "::");
            i += best_len - 1;
        } else {
            const bool separator = i > 0 && !(best_len > 0 && i == best_start + best_len);
            n = snprintf(out + used, capacity - used, separator ? ":%x" : "%x", (unsigned)group_at(a, i));
        }
        if (n < 0 || (size_t)n >= capacity - used) {
            return -1;
        }
        used += (size_t)n;
    }
    return (int)used;
}

bool ms_net_addr_format(const MsAddr *address, char *out, size_t capacity, size_t *length) {
    char host[MS_NET_ADDR_TEXT_MAX];
    int n;
    if (address->family == 4) {
        n = snprintf(host, sizeof host, "%u.%u.%u.%u", address->ip[0], address->ip[1], address->ip[2], address->ip[3]);
    } else {
        n = format_v6(address, host, sizeof host);
        if (n >= 0 && address->scope != 0) {
            n += snprintf(host + n, sizeof host - (size_t)n, "%%%u", (unsigned)address->scope);
        }
    }
    if (n < 0 || (size_t)n >= sizeof host) {
        return false;
    }
    const int total = snprintf(out, capacity, address->family == 6 ? "[%s]:%u" : "%s:%u", host, (unsigned)address->port);
    if (total < 0 || (size_t)total >= capacity) {
        return false;
    }
    *length = (size_t)total;
    return true;
}
