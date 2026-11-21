/* Network restriction (net_filter.h). */
#include "net_filter.h"

#include <stdlib.h>
#include <string.h>

#include "addr_text.h"
#include "ms_rt/chars.h"

typedef struct Range {
    MsAddr base;
    unsigned bits;
} Range;

typedef struct Level {
    char **hosts;
    size_t host_count;
    Range *ranges;
    size_t range_count;
} Level;

struct MsNetFilter {
    Level *levels;
    size_t count;
};

bool ms_net_filter_restricted(const MsNetFilter *filter) { return filter->count > 0; }

MsNetFilter *ms_net_filter_new(void) { return calloc(1, sizeof(MsNetFilter)); }

void ms_net_filter_free(MsNetFilter *filter) {
    if (filter == NULL) {
        return;
    }
    for (size_t i = 0; i < filter->count; i++) {
        for (size_t h = 0; h < filter->levels[i].host_count; h++) {
            free(filter->levels[i].hosts[h]);
        }
        free(filter->levels[i].hosts);
        free(filter->levels[i].ranges);
    }
    free(filter->levels);
    free(filter);
}

/* The host name as it is compared: lower-case, one trailing dot dropped. NULL when out of memory. */
static char *fold(MsBytes name, size_t *length) {
    size_t n = name.len;
    if (n > 0 && name.ptr[n - 1] == '.') {
        n--;
    }
    char *text = malloc(n + 1);
    for (size_t i = 0; text != NULL && i < n; i++) {
        text[i] = (char)ms_ascii_to_lower(name.ptr[i]);
    }
    if (text != NULL) {
        text[n] = 0;
        *length = n;
    }
    return text;
}

static bool parse_cidr(MsBytes text, Range *out) {
    const uint8_t *slash = memchr(text.ptr, '/', text.len);
    if (slash == NULL || !ms_net_ip_parse(ms_bytes_of(text.ptr, (size_t)(slash - text.ptr)), &out->base)) {
        return false;
    }
    const size_t digits = text.len - (size_t)(slash - text.ptr) - 1;
    unsigned bits = 0;
    if (digits == 0 || digits > 3) {
        return false;
    }
    for (size_t i = 0; i < digits; i++) {
        const uint8_t c = slash[1 + i];
        if (!ms_ascii_is_digit(c)) {
            return false;
        }
        bits = bits * 10 + (unsigned)(c - '0');
    }
    out->bits = bits;
    return bits <= (out->base.family == 4 ? 32u : 128u);
}

static bool range_contains(const Range *range, const MsAddr *address) {
    if (range->base.family != address->family) {
        return false;
    }
    const unsigned whole = range->bits / 8, rest = range->bits % 8;
    if (memcmp(range->base.ip, address->ip, whole) != 0) {
        return false;
    }
    if (rest == 0) {
        return true;
    }
    const unsigned mask = (0xFFu << (8 - rest)) & 0xFFu;
    return ((range->base.ip[whole] ^ address->ip[whole]) & mask) == 0;
}

bool ms_net_filter_narrow(MsNetFilter *filter, const MsBytes *hosts, size_t host_count, const MsBytes *cidrs, size_t cidr_count) {
    Level level = {0};
    level.hosts = calloc(host_count == 0 ? 1 : host_count, sizeof *level.hosts);
    level.ranges = calloc(cidr_count == 0 ? 1 : cidr_count, sizeof *level.ranges);
    bool ok = level.hosts != NULL && level.ranges != NULL;
    for (size_t i = 0; ok && i < host_count; i++) {
        size_t length = 0;
        level.hosts[i] = fold(hosts[i], &length);
        ok = level.hosts[i] != NULL;
        level.host_count++;
    }
    for (size_t i = 0; ok && i < cidr_count; i++) {
        ok = parse_cidr(cidrs[i], &level.ranges[i]);
        level.range_count++;
    }
    Level *grown = ok ? realloc(filter->levels, (filter->count + 1) * sizeof *grown) : NULL;
    if (grown == NULL) {
        for (size_t i = 0; i < level.host_count; i++) {
            free(level.hosts[i]);
        }
        free(level.hosts);
        free(level.ranges);
        return false;
    }
    grown[filter->count++] = level;
    filter->levels = grown;
    return true;
}

static bool level_allows_host(const Level *level, const char *name, size_t length) {
    for (size_t i = 0; i < level->host_count; i++) {
        if (strlen(level->hosts[i]) == length && memcmp(level->hosts[i], name, length) == 0) {
            return true;
        }
    }
    MsAddr literal;
    if (!ms_net_ip_parse(ms_bytes_of((const uint8_t *)name, length), &literal)) {
        return false;
    }
    for (size_t i = 0; i < level->range_count; i++) {
        if (range_contains(&level->ranges[i], &literal)) {
            return true;
        }
    }
    return false;
}

bool ms_net_filter_host_allowed(const MsNetFilter *filter, MsBytes host) {
    size_t length = 0;
    char *name = fold(host, &length);
    bool allowed = name != NULL;
    for (size_t i = 0; allowed && i < filter->count; i++) {
        allowed = level_allows_host(&filter->levels[i], name, length);
    }
    free(name);
    return allowed;
}

bool ms_net_filter_address_allowed(const MsNetFilter *filter, const MsAddr *address) {
    for (size_t i = 0; i < filter->count; i++) {
        const Level *level = &filter->levels[i];
        bool allowed = level->range_count == 0 && level->host_count > 0;
        for (size_t r = 0; r < level->range_count; r++) {
            allowed = allowed || range_contains(&level->ranges[r], address);
        }
        if (!allowed) {
            return false;
        }
    }
    return true;
}
