/* runtime/std/net_ip.c: IP address and CIDR text. Parsing follows the grammar of Rust's std::net (the
 * recorded vectors of the old crate pass): decimal octets of one to three digits without a leading zero,
 * IPv6 groups of one to four hex digits, one `::` standing for at least one group, an IPv4 tail. */
#include "runtime/std/net_ip.h"

typedef struct Cursor {
  MsSpan text;
  size_t at;
} Cursor;

static bool take(Cursor *c, uint8_t byte) {
  if (c->at < c->text.len && c->text.ptr[c->at] == byte) {
    c->at++;
    return true;
  }
  return false;
}

static int digit_value(uint8_t byte, unsigned radix) {
  int v = -1;
  if (byte >= '0' && byte <= '9') {
    v = byte - '0';
  } else if (byte >= 'a' && byte <= 'f') {
    v = byte - 'a' + 10;
  } else if (byte >= 'A' && byte <= 'F') {
    v = byte - 'A' + 10;
  }
  return v >= 0 && (unsigned)v < radix ? v : -1;
}

/* Reads at most `max_digits` digits; false when there are none, more, or (decimal) a leading zero. */
static bool read_number(Cursor *c, unsigned radix, unsigned max_digits, uint32_t limit, uint32_t *out) {
  uint32_t value = 0;
  unsigned count = 0;
  while (c->at < c->text.len && digit_value(c->text.ptr[c->at], radix) >= 0) {
    if (count == max_digits || (radix == 10 && count == 1 && value == 0)) {
      return false;
    }
    value = value * radix + (uint32_t)digit_value(c->text.ptr[c->at], radix);
    count++;
    c->at++;
  }
  if (count == 0 || value > limit) {
    return false;
  }
  *out = value;
  return true;
}

static bool read_v4(Cursor *c, uint8_t out[4]) {
  const size_t start = c->at;
  for (unsigned i = 0; i < 4; i++) {
    uint32_t octet = 0;
    if ((i > 0 && !take(c, '.')) || !read_number(c, 10, 3, 255, &octet)) {
      c->at = start;
      return false;
    }
    out[i] = (uint8_t)octet;
  }
  return true;
}

/* Reads up to `limit` groups of the head or tail of an IPv6 address; *ended_v4 is set when the last two
 * groups were an IPv4 tail. Returns the group count. */
static size_t read_groups(Cursor *c, uint16_t groups[8], size_t limit, bool *ended_v4) {
  *ended_v4 = false;
  for (size_t i = 0; i < limit; i++) {
    const size_t start = c->at;
    if (i > 0 && !take(c, ':')) {
      return i;
    }
    uint8_t v4[4];
    if (i + 1 < limit && read_v4(c, v4)) {
      groups[i] = (uint16_t)(v4[0] << 8 | v4[1]);
      groups[i + 1] = (uint16_t)(v4[2] << 8 | v4[3]);
      *ended_v4 = true;
      return i + 2;
    }
    uint32_t group = 0;
    if (!read_number(c, 16, 4, 0xffff, &group)) {
      c->at = start;
      return i;
    }
    groups[i] = (uint16_t)group;
  }
  return limit;
}

static bool parse_v6(MsSpan text, MsIp *out) {
  Cursor c = {.text = text};
  uint16_t groups[8] = {0};
  uint16_t tail[8] = {0};
  bool v4 = false;
  size_t head = read_groups(&c, groups, 8, &v4);
  size_t tail_count = 0;
  if (head < 8) {
    if (v4 || !take(&c, ':') || !take(&c, ':')) {
      return false;
    }
    bool ignored = false;
    tail_count = read_groups(&c, tail, 8 - (head + 1), &ignored);
  }
  if (c.at != text.len) {
    return false;
  }
  for (size_t i = 0; i < tail_count; i++) {
    groups[8 - tail_count + i] = tail[i];
  }
  *out = (MsIp){.v6 = true};
  for (size_t i = 0; i < 8; i++) {
    out->b[2 * i] = (uint8_t)(groups[i] >> 8);
    out->b[2 * i + 1] = (uint8_t)groups[i];
  }
  return true;
}

bool ms_ip_parse(MsSpan text, MsIp *out) {
  Cursor c = {.text = text};
  uint8_t v4[4];
  if (read_v4(&c, v4)) {
    if (c.at != text.len) {
      return false;
    }
    *out = (MsIp){.v6 = false};
    for (size_t i = 0; i < 4; i++) {
      out->b[i] = v4[i];
    }
    return true;
  }
  return parse_v6(text, out);
}

static bool is_mapped(const MsIp *ip) {
  for (size_t i = 0; i < 10; i++) {
    if (ip->b[i] != 0) {
      return false;
    }
  }
  return ip->b[10] == 0xff && ip->b[11] == 0xff;
}

void ms_ip_normalize(MsIp *ip) {
  if (ip->v6 && is_mapped(ip)) {
    const MsIp v4 = {.v6 = false, .b = {ip->b[12], ip->b[13], ip->b[14], ip->b[15]}};
    *ip = v4;
  }
}

static void text_v4(const uint8_t *b, MsStrBuild *out) {
  for (size_t i = 0; i < 4; i++) {
    if (i > 0) {
      ms_strbuild_append_byte(out, '.');
    }
    ms_strbuild_append_u64(out, b[i]);
  }
}

static void text_groups(const uint16_t *groups, size_t from, size_t to, MsStrBuild *out) {
  for (size_t i = from; i < to; i++) {
    if (i > from) {
      ms_strbuild_append_byte(out, ':');
    }
    ms_strbuild_append_u64_radix(out, groups[i], 16);
  }
}

void ms_ip_text(const MsIp *ip, MsStrBuild *out) {
  if (!ip->v6) {
    text_v4(ip->b, out);
    return;
  }
  if (is_mapped(ip)) {
    ms_strbuild_append_text(out, "::ffff:");
    text_v4(ip->b + 12, out);
    return;
  }
  uint16_t groups[8];
  for (size_t i = 0; i < 8; i++) {
    groups[i] = (uint16_t)(ip->b[2 * i] << 8 | ip->b[2 * i + 1]);
  }
  size_t best_at = 0;
  size_t best_len = 0;
  for (size_t i = 0; i < 8;) {
    size_t run = 0;
    while (i + run < 8 && groups[i + run] == 0) {
      run++;
    }
    if (run > best_len) {
      best_at = i;
      best_len = run;
    }
    i += run == 0 ? 1 : run;
  }
  if (best_len < 2) {
    text_groups(groups, 0, 8, out);
    return;
  }
  text_groups(groups, 0, best_at, out);
  ms_strbuild_append_text(out, "::");
  text_groups(groups, best_at + best_len, 8, out);
}

/* Keeps the first `bits` bits. */
static void ms_ip_mask(MsIp *ip, unsigned bits) {
  const unsigned size = ip->v6 ? 16 : 4;
  for (unsigned i = 0; i < size; i++) {
    const unsigned keep = bits >= 8 * (i + 1) ? 8 : bits > 8 * i ? bits - 8 * i : 0;
    ip->b[i] &= (uint8_t)(0xff00u >> keep);
  }
}

bool ms_cidr_parse(MsSpan text, MsCidr *out) {
  size_t slash = 0;
  if (!ms_span_find(text, ms_span_of_text("/"), &slash)) {
    return false;
  }
  MsSpan addr = {0};
  MsSpan bits_text = {0};
  if (!ms_span_slice(text, 0, slash, &addr) || !ms_span_slice(text, slash + 1, text.len, &bits_text)) {
    return false;
  }
  Cursor c = {.text = bits_text};
  uint32_t bits = 0;
  if (!read_number(&c, 10, 3, 128, &bits) || c.at != bits_text.len) {
    return false;
  }
  MsIp ip = {0};
  if (!ms_ip_parse(addr, &ip) || bits > (ip.v6 ? 128u : 32u)) {
    return false;
  }
  ms_ip_mask(&ip, bits);
  *out = (MsCidr){.addr = ip, .bits = (uint8_t)bits};
  return true;
}

void ms_cidr_text(const MsCidr *cidr, MsStrBuild *out) {
  ms_ip_text(&cidr->addr, out);
  ms_strbuild_append_byte(out, '/');
  ms_strbuild_append_u64(out, cidr->bits);
}

bool ms_cidr_contains(const MsCidr *cidr, const MsIp *ip) {
  if (cidr->addr.v6 != ip->v6) {
    return false;
  }
  MsIp masked = *ip;
  ms_ip_mask(&masked, cidr->bits);
  return ms_span_equal(ms_span_of(masked.b, 16), ms_span_of(cidr->addr.b, 16));
}
