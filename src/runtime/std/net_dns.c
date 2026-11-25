/* The DNS wire format (see net_dns.h). */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include "runtime/std/net_dns.h"

#include <string.h>

#include "base/alloc.h"
#include "base/strbuild.h"
#include "runtime/std/fs_job.h"
#include "runtime/std/net_ip.h"

enum { HEADER = 12, MAX_HOPS = 32, NAME_LIMIT = 253, LABEL_LIMIT = 63, MAX_RECORDS = 256 };

uint16_t ms_dns_type_of_kind(int64_t kind) {
  static const uint16_t types[] = {MS_DNS_A,  MS_DNS_AAAA, MS_DNS_CNAME, MS_DNS_MX,
                                   MS_DNS_NS, MS_DNS_TXT,  MS_DNS_PTR,   MS_DNS_SRV};
  return kind >= 0 && kind < (int64_t)(sizeof types / sizeof types[0]) ? types[kind] : 0;
}

static void put16(uint8_t *at, uint16_t value) {
  at[0] = (uint8_t)(value >> 8);
  at[1] = (uint8_t)value;
}

static uint16_t get16(const uint8_t *at) { return (uint16_t)((at[0] << 8) | at[1]); }

size_t ms_dns_build_query(uint8_t *out, uint16_t id, MsSpan name, uint16_t type) {
  size_t length = name.len;
  if (length > 0 && name.ptr[length - 1] == '.') {
    length--;
  }
  if (length > NAME_LIMIT) {
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
    if (label == 0 || label > LABEL_LIMIT) {
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

/* Reads the name at `at` into `text` with a final dot ("." for the root), following compression pointers; the offset
 * after the name in the record goes to `*next`. Bytes that are not printable ASCII become '?'. */
static bool read_name(MsSpan message, size_t at, MsStrBuild *text, size_t *next) {
  size_t end = 0;
  size_t used = 0;
  for (int hops = 0;;) {
    if (at >= message.len) {
      return false;
    }
    const size_t label = message.ptr[at];
    if (label == 0) {
      at++;
      break;
    }
    if ((label & 0xC0u) == 0xC0u) {
      if (at + 1 >= message.len || ++hops > MAX_HOPS) {
        return false;
      }
      end = end == 0 ? at + 2 : end;
      at = ((label & 0x3Fu) << 8) | message.ptr[at + 1];
      continue;
    }
    if ((label & 0xC0u) != 0 || at + 1 + label > message.len || used + label + 1 > NAME_LIMIT + 1) {
      return false;
    }
    for (size_t i = 0; i < label; i++) {
      const uint8_t byte = message.ptr[at + 1 + i];
      ms_strbuild_append_byte(text, byte > 0x20 && byte < 0x7F ? byte : '?');
    }
    ms_strbuild_append_byte(text, '.');
    used += label + 1;
    at += 1 + label;
  }
  if (used == 0) {
    ms_strbuild_append_byte(text, '.');
  }
  *next = end != 0 ? end : at;
  return true;
}

/* Fills `record` from the data at message[data, data + length); false for a malformed one. `*keep` is false for data
 * of a shape this kind does not have. */
static bool read_record(MsSpan message, uint16_t type, size_t data, size_t length, MsDnsRecord *record, bool *keep) {
  const uint8_t *rdata = message.ptr + data;
  MsStrBuild text = ms_strbuild_new();
  size_t next = 0;
  bool ok = true;
  *keep = true;
  switch (type) {
  case MS_DNS_A:
  case MS_DNS_AAAA: {
    const bool v6 = type == MS_DNS_AAAA;
    MsIp address = {.v6 = v6};
    if (length != (v6 ? 16u : 4u)) {
      *keep = false;
      break;
    }
    memcpy(address.b, rdata, length);
    ms_ip_text(&address, &text);
    break;
  }
  case MS_DNS_NS:
  case MS_DNS_CNAME:
  case MS_DNS_PTR:
    ok = read_name(message, data, &text, &next);
    break;
  case MS_DNS_MX:
    *keep = length >= 3;
    if (*keep) {
      record->priority = get16(rdata);
      ok = read_name(message, data + 2, &text, &next);
    }
    break;
  case MS_DNS_SRV:
    *keep = length >= 7;
    if (*keep) {
      record->priority = get16(rdata);
      record->weight = get16(rdata + 2);
      record->port = get16(rdata + 4);
      ok = read_name(message, data + 6, &text, &next);
    }
    break;
  default: { /* TXT: length-prefixed pieces, joined */
    MsStrBuild joined = ms_strbuild_new();
    for (size_t i = 0; ok && i < length;) {
      const size_t piece = rdata[i];
      ok = i + 1 + piece <= length;
      if (ok) {
        ms_strbuild_append(&joined, ms_span_of(rdata + i + 1, piece));
        i += 1 + piece;
      }
    }
    ms_fs_append_lossy(&text, ms_strbuild_span(&joined));
    ms_strbuild_free(&joined);
    break;
  }
  }
  record->value = ms_strbuild_finish(&text);
  return ok;
}

void ms_dns_answer_free(MsDnsAnswer *answer) {
  MsDnsRecord *records = (MsDnsRecord *)(void *)answer->records.ptr;
  for (size_t i = 0; i < answer->records.len; i++) {
    ms_string_release(&records[i].value);
  }
  ms_list_free(&answer->records);
}

bool ms_dns_parse(MsSpan message, uint16_t type, int64_t kind, MsDnsAnswer *out) {
  if (message.len < HEADER) {
    return false;
  }
  const uint16_t flags = get16(message.ptr + 2);
  if ((flags & 0x8000u) == 0) {
    return false;
  }
  *out = (MsDnsAnswer){.id = get16(message.ptr), .truncated = (flags & 0x0200u) != 0, .rcode = (uint8_t)(flags & 0xFu)};
  const size_t questions = get16(message.ptr + 4);
  const size_t answers = get16(message.ptr + 6);
  size_t at = HEADER;
  for (size_t i = 0; i < questions; i++) {
    MsStrBuild skipped = ms_strbuild_new();
    const bool ok = read_name(message, at, &skipped, &at);
    ms_strbuild_free(&skipped);
    if (!ok) {
      return false;
    }
    at += 4;
  }
  for (size_t i = 0; i < answers; i++) {
    MsStrBuild skipped = ms_strbuild_new();
    size_t next = 0;
    const bool named = read_name(message, at, &skipped, &next);
    ms_strbuild_free(&skipped);
    if (!named || next + 10 > message.len) {
      ms_dns_answer_free(out);
      return false;
    }
    const uint16_t record_type = get16(message.ptr + next);
    const size_t length = get16(message.ptr + next + 8);
    const size_t data = next + 10;
    if (data + length > message.len) {
      ms_dns_answer_free(out);
      return false;
    }
    at = data + length;
    MsDnsRecord record = {.kind = kind, .value = ms_string_empty()};
    bool keep = record_type == type;
    if (keep && !read_record(message, type, data, length, &record, &keep)) {
      ms_string_release(&record.value);
      ms_dns_answer_free(out);
      return false;
    }
    if (!keep || out->records.len >= MAX_RECORDS) {
      ms_string_release(&record.value);
    } else {
      ms_list_push(&out->records, sizeof record, &record);
    }
  }
  return true;
}

void ms_dns_records_free(MsList *records) {
  MsDnsRecord *items = (MsDnsRecord *)(void *)records->ptr;
  for (size_t i = 0; i < records->len; i++) {
    ms_string_release(&items[i].value);
  }
  ms_list_free(records);
}

bool ms_dns_reverse_name(MsSpan text, MsStrBuild *out) {
  static const char digits[] = "0123456789abcdef";
  MsIp ip;
  if (!ms_ip_parse(text, &ip)) {
    return false;
  }
  ms_ip_normalize(&ip);
  if (!ip.v6) {
    for (int i = 3; i >= 0; i--) {
      ms_strbuild_append_u64(out, ip.b[i]);
      ms_strbuild_append_byte(out, '.');
    }
    ms_strbuild_append_text(out, "in-addr.arpa");
    return true;
  }
  for (int i = 15; i >= 0; i--) {
    ms_strbuild_append_byte(out, (uint8_t)digits[ip.b[i] & 0xF]);
    ms_strbuild_append_byte(out, '.');
    ms_strbuild_append_byte(out, (uint8_t)digits[ip.b[i] >> 4]);
    ms_strbuild_append_byte(out, '.');
  }
  ms_strbuild_append_text(out, "ip6.arpa");
  return true;
}

/* ---- resolv.conf ---- */

static bool is_blank(uint8_t byte) { return byte == ' ' || byte == '\t' || byte == '\r'; }

/* The next blank-separated word of `line` from `*at`; false at the end. */
static bool next_word(MsSpan line, size_t *at, MsSpan *word) {
  while (*at < line.len && is_blank(line.ptr[*at])) {
    (*at)++;
  }
  const size_t start = *at;
  while (*at < line.len && !is_blank(line.ptr[*at])) {
    (*at)++;
  }
  *word = ms_span_of(line.ptr + start, *at - start);
  return *at > start;
}

static void push_text(MsList *list, MsSpan text) {
  MsString item = ms_string_from_span(text);
  ms_list_push(list, sizeof item, &item);
}

static void clear_list(MsList *list) {
  MsString *items = (MsString *)(void *)list->ptr;
  for (size_t i = 0; i < list->len; i++) {
    ms_string_release(&items[i]);
  }
  list->len = 0;
}

static void add_server(MsDnsConfig *config, MsSpan address) {
  MsIp ip;
  size_t zone = 0;
  while (zone < address.len && address.ptr[zone] != '%') {
    zone++;
  }
  if (!ms_ip_parse(ms_span_of(address.ptr, zone), &ip)) {
    return;
  }
  MsStrBuild text = ms_strbuild_new();
  ms_join_host_port(ms_span_of(address.ptr, zone), 53, &text);
  MsString server = ms_strbuild_finish(&text);
  ms_list_push(&config->servers, sizeof server, &server);
}

static void read_options(MsDnsConfig *config, MsSpan line, size_t at) {
  static const char key[] = "ndots:";
  MsSpan word;
  while (next_word(line, &at, &word)) {
    if (word.len > sizeof key - 1 && ms_span_starts_with_text(word, key)) {
      int value = 0;
      for (size_t i = sizeof key - 1; i < word.len && word.ptr[i] >= '0' && word.ptr[i] <= '9' && value < 15; i++) {
        value = value * 10 + (word.ptr[i] - '0');
      }
      config->ndots = value;
    }
  }
}

static bool is_word(MsSpan word, const char *name) {
  return ms_span_equal(word, ms_span_of_text(name));
}

void ms_dns_config_parse(MsSpan text, MsDnsConfig *out) {
  *out = (MsDnsConfig){.ndots = 1};
  size_t line_start = 0;
  while (line_start < text.len) {
    size_t line_end = line_start;
    while (line_end < text.len && text.ptr[line_end] != '\n') {
      line_end++;
    }
    const MsSpan line = ms_span_of(text.ptr + line_start, line_end - line_start);
    line_start = line_end + 1;
    size_t at = 0;
    MsSpan key;
    MsSpan word;
    if (!next_word(line, &at, &key)) {
      continue;
    }
    if (is_word(key, "nameserver") && next_word(line, &at, &word)) {
      add_server(out, word);
    } else if (is_word(key, "search") || is_word(key, "domain")) {
      clear_list(&out->search); /* the last search or domain line wins */
      while (next_word(line, &at, &word)) {
        const size_t length = word.len > 0 && word.ptr[word.len - 1] == '.' ? word.len - 1 : word.len;
        if (length > 0) {
          push_text(&out->search, ms_span_of(word.ptr, length));
        }
      }
    } else if (is_word(key, "options")) {
      read_options(out, line, at);
    }
  }
}

void ms_dns_config_free(MsDnsConfig *config) {
  clear_list(&config->servers);
  clear_list(&config->search);
  ms_list_free(&config->servers);
  ms_list_free(&config->search);
}
