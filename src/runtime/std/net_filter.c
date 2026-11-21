/* Network restriction (see net_filter.h). */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include "runtime/std/net_filter.h"

#include <stdatomic.h>
#include <string.h>

#include "base/alloc.h"
#include "base/string.h"
#include "runtime/std/net_ip.h"

typedef struct Level {
  MsString *hosts; /* owned, folded */
  size_t host_count;
  MsCidr *ranges; /* owned */
  size_t range_count;
} Level;

struct MsNetFilter {
  atomic_uint references;
  Level *levels; /* owned */
  size_t count;
};

MsNetFilter *ms_net_filter_retain(MsNetFilter *filter) {
  if (filter != NULL) {
    atomic_fetch_add(&filter->references, 1);
  }
  return filter;
}

static void level_free(Level *level) {
  for (size_t i = 0; i < level->host_count; i++) {
    ms_string_release(&level->hosts[i]);
  }
  ms_free(level->hosts);
  ms_free(level->ranges);
}

void ms_net_filter_release(MsNetFilter *filter) {
  if (filter == NULL || atomic_fetch_sub(&filter->references, 1) != 1) {
    return;
  }
  for (size_t i = 0; i < filter->count; i++) {
    level_free(&filter->levels[i]);
  }
  ms_free(filter->levels);
  ms_free(filter);
}

static uint8_t lower(uint8_t byte) { return byte >= 'A' && byte <= 'Z' ? (uint8_t)(byte + ('a' - 'A')) : byte; }

/* `name` as it is compared: lower-case, one trailing dot dropped. */
static MsString fold(MsSpan name) {
  const size_t length = name.len > 0 && name.ptr[name.len - 1] == '.' ? name.len - 1 : name.len;
  MsStrBuild folded = ms_strbuild_new();
  for (size_t i = 0; i < length; i++) {
    ms_strbuild_append_byte(&folded, lower(name.ptr[i]));
  }
  return ms_strbuild_finish(&folded);
}

static bool level_copy(Level *level, const Level *from) {
  level->hosts = ms_alloc(from->host_count * sizeof *level->hosts + 1);
  level->ranges = ms_alloc(from->range_count * sizeof *level->ranges + 1);
  level->host_count = from->host_count;
  level->range_count = from->range_count;
  for (size_t i = 0; i < from->host_count; i++) {
    level->hosts[i] = ms_string_clone(&from->hosts[i]);
  }
  memcpy(level->ranges, from->ranges, from->range_count * sizeof *level->ranges);
  return true;
}

MsNetFilter *ms_net_filter_narrow(const MsNetFilter *base, const MsList *hosts, const MsList *cidrs) {
  const MsString *host_items = (const MsString *)(const void *)hosts->ptr;
  const MsString *cidr_items = (const MsString *)(const void *)cidrs->ptr;
  Level level = {.hosts = ms_alloc(hosts->len * sizeof *level.hosts + 1),
                 .ranges = ms_alloc(cidrs->len * sizeof *level.ranges + 1)};
  for (size_t i = 0; i < hosts->len; i++) {
    level.hosts[level.host_count++] = fold(ms_string_span(&host_items[i]));
  }
  for (size_t i = 0; i < cidrs->len; i++) {
    if (!ms_cidr_parse(ms_string_span(&cidr_items[i]), &level.ranges[level.range_count])) {
      level_free(&level);
      return NULL;
    }
    level.range_count++;
  }
  MsNetFilter *filter = ms_alloc_zeroed(sizeof *filter);
  const size_t before = base == NULL ? 0 : base->count;
  atomic_init(&filter->references, 1);
  filter->levels = ms_alloc((before + 1) * sizeof *filter->levels);
  for (size_t i = 0; i < before; i++) {
    (void)level_copy(&filter->levels[i], &base->levels[i]);
  }
  filter->levels[before] = level;
  filter->count = before + 1;
  return filter;
}

static bool level_allows_host(const Level *level, MsSpan name) {
  for (size_t i = 0; i < level->host_count; i++) {
    if (ms_span_equal(ms_string_span(&level->hosts[i]), name)) {
      return true;
    }
  }
  MsIp literal;
  if (!ms_ip_parse(name, &literal)) {
    return false;
  }
  ms_ip_normalize(&literal);
  for (size_t i = 0; i < level->range_count; i++) {
    if (ms_cidr_contains(&level->ranges[i], &literal)) {
      return true;
    }
  }
  return false;
}

bool ms_net_filter_host_allowed(const MsNetFilter *filter, MsSpan host) {
  if (filter == NULL) {
    return true;
  }
  MsString name = fold(host);
  bool allowed = true;
  for (size_t i = 0; allowed && i < filter->count; i++) {
    allowed = level_allows_host(&filter->levels[i], ms_string_span(&name));
  }
  ms_string_release(&name);
  return allowed;
}

/* The address of a resolver result as an IP (an IPv4-mapped IPv6 address as IPv4). */
static bool ip_of(const struct sockaddr *address, MsIp *out) {
  memset(out, 0, sizeof *out);
  if (address->sa_family == AF_INET) {
    out->v6 = false;
    memcpy(out->b, &((const struct sockaddr_in *)(const void *)address)->sin_addr, 4);
    return true;
  }
  if (address->sa_family == AF_INET6) {
    out->v6 = true;
    memcpy(out->b, &((const struct sockaddr_in6 *)(const void *)address)->sin6_addr, 16);
    ms_ip_normalize(out);
    return true;
  }
  return false;
}

bool ms_net_filter_address_allowed(const MsNetFilter *filter, const struct sockaddr *address) {
  MsIp ip;
  if (filter == NULL) {
    return true;
  }
  if (!ip_of(address, &ip)) {
    return false;
  }
  for (size_t i = 0; i < filter->count; i++) {
    const Level *level = &filter->levels[i];
    bool allowed = level->range_count == 0 && level->host_count > 0;
    for (size_t r = 0; r < level->range_count; r++) {
      allowed = allowed || ms_cidr_contains(&level->ranges[r], &ip);
    }
    if (!allowed) {
      return false;
    }
  }
  return true;
}
