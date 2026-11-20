/* The DNS wire format (dns.h). */
#include "dns.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "addr_text.h"

enum { NAME_MAX_TEXT = 256, HEADER = 12, MAX_HOPS = 32 };

/* ---- query ---- */

static void put16(uint8_t *at, uint16_t value) {
    at[0] = (uint8_t)(value >> 8);
    at[1] = (uint8_t)value;
}

size_t ms_dns_build_query(uint8_t *out, uint16_t id, MsBytes name, uint16_t type) {
    size_t length = name.len;
    if (length > 0 && name.ptr[length - 1] == '.') {
        length--;
    }
    if (length > 253) {
        return 0;
    }
    memset(out, 0, HEADER);
    put16(out, id);
    out[2] = 0x01; /* recursion desired */
    put16(out + 4, 1);
    size_t used = HEADER;
    size_t start = 0;
    while (length > 0 && start <= length) {
        size_t end = start;
        while (end < length && name.ptr[end] != '.') {
            end++;
        }
        const size_t label = end - start;
        if (label == 0 || label > 63) {
            return 0;
        }
        out[used++] = (uint8_t)label;
        memcpy(out + used, name.ptr + start, label);
        used += label;
        start = end + 1;
    }
    out[used++] = 0;
    put16(out + used, type);
    put16(out + used + 2, 1);
    return used + 4;
}

/* ---- response ---- */

static uint16_t get16(const uint8_t *at) { return (uint16_t)((at[0] << 8) | at[1]); }

/* Reads the name at `at` into `text` with a final dot ("." for the root), following compression pointers; the offset
 * after the name in the record goes to *next. Bytes that are not printable ASCII become '?'. */
static bool read_name(MsBytes message, size_t at, char text[NAME_MAX_TEXT], size_t *length, size_t *next) {
    size_t used = 0;
    size_t end = 0;
    for (int hops = 0;;) {
        if (at >= message.len) {
            return false;
        }
        const size_t label = message.ptr[at];
        if (label == 0) {
            at++;
            break;
        }
        if ((label & 0xC0) == 0xC0) {
            if (at + 1 >= message.len || ++hops > MAX_HOPS) {
                return false;
            }
            if (end == 0) {
                end = at + 2;
            }
            at = ((label & 0x3F) << 8) | message.ptr[at + 1];
            continue;
        }
        if ((label & 0xC0) != 0 || at + 1 + label > message.len || used + label + 1 >= NAME_MAX_TEXT) {
            return false;
        }
        for (size_t i = 0; i < label; i++) {
            const uint8_t byte = message.ptr[at + 1 + i];
            const bool printable = byte > 0x20 && byte < 0x7F;
            text[used] = '?';
            if (printable) {
                text[used] = (char)byte;
            }
            used++;
        }
        text[used++] = '.';
        at += 1 + label;
    }
    if (used == 0) {
        text[used++] = '.';
    }
    *length = used;
    *next = end != 0 ? end : at;
    return true;
}

/* How many bytes of the well-formed UTF-8 sequence at `p`, or 0. */
static size_t utf8_width(const uint8_t *p, size_t n) {
    const uint8_t b = p[0];
    size_t width = 0;
    uint32_t minimum = 0;
    uint32_t scalar = 0;
    if (b < 0x80) {
        return 1;
    }
    if (b >= 0xC2 && b <= 0xDF) {
        width = 2; minimum = 0x80; scalar = b & 0x1Fu;
    } else if (b >= 0xE0 && b <= 0xEF) {
        width = 3; minimum = 0x800; scalar = b & 0x0Fu;
    } else if (b >= 0xF0 && b <= 0xF4) {
        width = 4; minimum = 0x10000; scalar = b & 0x07u;
    } else {
        return 0;
    }
    if (n < width) {
        return 0;
    }
    for (size_t i = 1; i < width; i++) {
        if ((p[i] & 0xC0) != 0x80) {
            return 0;
        }
        scalar = (scalar << 6) | (p[i] & 0x3Fu);
    }
    return scalar >= minimum && scalar <= 0x10FFFF && (scalar < 0xD800 || scalar > 0xDFFF) ? width : 0;
}

/* A malloc'd copy of `data` as UTF-8, each invalid byte replaced by U+FFFD. */
static char *utf8_lossy(const uint8_t *data, size_t length, size_t *out_length) {
    char *copy = malloc(length * 3 + 1);
    if (copy == NULL) {
        return NULL;
    }
    size_t used = 0;
    for (size_t i = 0; i < length;) {
        const size_t width = utf8_width(data + i, length - i);
        if (width == 0) {
            memcpy(copy + used, "\xEF\xBF\xBD", 3);
            used += 3;
            i++;
        } else {
            memcpy(copy + used, data + i, width);
            used += width;
            i += width;
        }
    }
    copy[used] = 0;
    *out_length = used;
    return copy;
}

static bool set_value(MsDnsRecord *record, const char *text, size_t length) {
    record->value = malloc(length + 1);
    if (record->value == NULL) {
        return false;
    }
    memcpy(record->value, text, length);
    record->value[length] = 0;
    record->length = length;
    return true;
}

static bool set_address(MsDnsRecord *record, const uint8_t *bytes, bool v6) {
    MsAddr address = {0};
    address.family = v6 ? 6 : 4;
    memcpy(address.ip, bytes, v6 ? 16 : 4);
    char text[MS_NET_ADDR_TEXT_MAX];
    size_t length = 0;
    if (!ms_net_addr_format(&address, text, sizeof text, &length)) {
        return false;
    }
    /* "1.2.3.4:0" and "[::1]:0" without the port and brackets */
    const char *start = text;
    length -= 2;
    if (v6) {
        start++;
        length -= 2;
    }
    return set_value(record, start, length);
}

static bool skipped(bool *keep) {
    *keep = false;
    return true;
}

/* Fills `record` from the answer's data at message[data, data + rdlength); false for a malformed one. `*keep` is
 * false for a kind that is skipped. */
static bool read_record(MsBytes message, size_t data, size_t rdlength, MsDnsRecord *record, bool *keep) {
    const uint8_t *rdata = message.ptr + data;
    char name[NAME_MAX_TEXT];
    size_t length = 0;
    size_t next = 0;
    *keep = true;
    switch (record->type) {
    case MS_DNS_A: return rdlength != 4 ? skipped(keep) : set_address(record, rdata, false);
    case MS_DNS_AAAA: return rdlength != 16 ? skipped(keep) : set_address(record, rdata, true);
    case MS_DNS_NS:
    case MS_DNS_CNAME:
    case MS_DNS_PTR:
        return read_name(message, data, name, &length, &next) && set_value(record, name, length);
    case MS_DNS_MX:
        if (rdlength < 3) {
            return skipped(keep);
        }
        record->priority = get16(rdata);
        return read_name(message, data + 2, name, &length, &next) && set_value(record, name, length);
    case MS_DNS_SRV:
        if (rdlength < 7) {
            return skipped(keep);
        }
        record->priority = get16(rdata);
        record->weight = get16(rdata + 2);
        record->port = get16(rdata + 4);
        return read_name(message, data + 6, name, &length, &next) && set_value(record, name, length);
    case MS_DNS_TXT: {
        uint8_t *text = malloc(rdlength + 1);
        if (text == NULL) {
            return false;
        }
        size_t used = 0;
        for (size_t i = 0; i < rdlength;) {
            const size_t piece = rdata[i];
            if (i + 1 + piece > rdlength) {
                free(text);
                return false;
            }
            memcpy(text + used, rdata + i + 1, piece);
            used += piece;
            i += 1 + piece;
        }
        record->value = utf8_lossy(text, used, &record->length);
        free(text);
        return record->value != NULL;
    }
    default:
        *keep = false;
        return true;
    }
}

void ms_dns_response_free(MsDnsResponse *response) {
    for (size_t i = 0; i < response->count; i++) {
        free(response->records[i].value);
    }
    free(response->records);
    response->records = NULL;
    response->count = 0;
}

bool ms_dns_parse_response(MsBytes message, MsDnsResponse *out) {
    if (message.len < HEADER) {
        return false;
    }
    const uint16_t flags = get16(message.ptr + 2);
    if ((flags & 0x8000) == 0) {
        return false;
    }
    out->id = get16(message.ptr);
    out->truncated = (flags & 0x0200) != 0;
    out->rcode = (uint8_t)(flags & 0xF);
    out->records = NULL;
    out->count = 0;
    const size_t questions = get16(message.ptr + 4);
    const size_t answers = get16(message.ptr + 6);
    char name[NAME_MAX_TEXT];
    size_t length = 0;
    size_t at = HEADER;
    for (size_t i = 0; i < questions; i++) {
        if (!read_name(message, at, name, &length, &at)) {
            return false;
        }
        at += 4;
    }
    out->records = calloc(answers < MS_DNS_MAX_RECORDS ? answers + 1 : MS_DNS_MAX_RECORDS, sizeof *out->records);
    if (out->records == NULL) {
        return false;
    }
    for (size_t i = 0; i < answers; i++) {
        size_t next = 0;
        if (!read_name(message, at, name, &length, &next) || next + 10 > message.len) {
            ms_dns_response_free(out);
            return false;
        }
        MsDnsRecord record = {.type = get16(message.ptr + next)};
        const size_t rdlength = get16(message.ptr + next + 8);
        const size_t data = next + 10;
        if (data + rdlength > message.len) {
            ms_dns_response_free(out);
            return false;
        }
        at = data + rdlength;
        bool keep = false;
        if (!read_record(message, data, rdlength, &record, &keep)) {
            free(record.value);
            ms_dns_response_free(out);
            return false;
        }
        if (!keep || out->count == MS_DNS_MAX_RECORDS) {
            free(record.value);
        } else {
            out->records[out->count++] = record;
        }
    }
    return true;
}

/* ---- host configuration ---- */

static bool is_space(char c) { return c == ' ' || c == '\t' || c == '\r'; }

static void add_search(MsDnsConfig *config, const char *word, size_t length) {
    while (length > 0 && word[length - 1] == '.') {
        length--;
    }
    if (length > 0 && length < MS_DNS_SEARCH_TEXT && config->search_count < MS_DNS_MAX_SEARCH) {
        memcpy(config->search[config->search_count], word, length);
        config->search[config->search_count][length] = 0;
        config->search_count++;
    }
}

/* Splits `line` into words, up to `max`; returns how many. */
static size_t words_of(MsBytes line, MsBytes *words, size_t max) {
    size_t count = 0;
    size_t i = 0;
    while (i < line.len && count < max) {
        while (i < line.len && is_space((char)line.ptr[i])) {
            i++;
        }
        const size_t start = i;
        while (i < line.len && !is_space((char)line.ptr[i])) {
            i++;
        }
        if (i > start) {
            words[count++] = ms_bytes_of(line.ptr + start, i - start);
        }
    }
    return count;
}

static void read_line(MsBytes line, MsDnsConfig *config, bool *domain_only) {
    for (size_t i = 0; i < line.len; i++) {
        if (line.ptr[i] == '#' || line.ptr[i] == ';') {
            line.len = i;
            break;
        }
    }
    MsBytes words[1 + MS_DNS_MAX_SEARCH];
    const size_t count = words_of(line, words, 1 + MS_DNS_MAX_SEARCH);
    if (count < 2) {
        return;
    }
    if (ms_bytes_is_text(words[0], "nameserver") && config->server_count < MS_DNS_MAX_SERVERS) {
        char text[MS_NET_ADDR_TEXT_MAX];
        if (words[1].len < 48) {
            const char *plain = (const char *)words[1].ptr;
            const bool v6 = memchr(plain, ':', words[1].len) != NULL;
            const int written = v6 ? snprintf(text, sizeof text, "[%.*s]:53", (int)words[1].len, plain)
                                   : snprintf(text, sizeof text, "%.*s:53", (int)words[1].len, plain);
            MsAddr address;
            if (written > 0 && ms_net_addr_parse(ms_bytes_of((const uint8_t *)text, (size_t)written), &address)) {
                config->servers[config->server_count++] = address;
            }
        }
    } else if (ms_bytes_is_text(words[0], "search")) {
        config->search_count = 0;
        *domain_only = false;
        for (size_t i = 1; i < count; i++) {
            add_search(config, (const char *)words[i].ptr, words[i].len);
        }
    } else if (ms_bytes_is_text(words[0], "domain") && *domain_only) {
        add_search(config, (const char *)words[1].ptr, words[1].len);
    } else if (ms_bytes_is_text(words[0], "options")) {
        for (size_t i = 1; i < count; i++) {
            if (words[i].len > 6 && memcmp(words[i].ptr, "ndots:", 6) == 0) {
                int64_t value = 0;
                for (size_t k = 6; k < words[i].len && words[i].ptr[k] >= '0' && words[i].ptr[k] <= '9' && value < 100; k++) {
                    value = value * 10 + (words[i].ptr[k] - '0');
                }
                config->ndots = value > 15 ? 15 : value;
            }
        }
    }
}

void ms_dns_config_parse(MsBytes text, MsDnsConfig *out) {
    memset(out, 0, sizeof *out);
    out->ndots = 1;
    bool domain_only = true; /* a `domain` line counts until a `search` line has been seen */
    size_t start = 0;
    for (size_t i = 0; i <= text.len; i++) {
        if (i == text.len || text.ptr[i] == '\n') {
            read_line(ms_bytes_of(text.ptr + start, i - start), out, &domain_only);
            start = i + 1;
        }
    }
    if (out->server_count == 0) {
        const MsAddr loopbacks[2] = {{.family = 4, .ip = {127, 0, 0, 1}, .port = 53},
                                     {.family = 6, .ip = {[15] = 1}, .port = 53}};
        out->servers[0] = loopbacks[0];
        out->servers[1] = loopbacks[1];
        out->server_count = 2;
    }
}
