/* The DNS client: asks a server over UDP, over TCP when the answer is truncated, and walks the search list (see
 * net_dns.h). It runs on the calling task and uses the datagram and connection natives, so a wait parks only the task. */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include <string.h>
#include <uv.h>
#ifdef _WIN32
#include <iphlpapi.h>
#endif

#include "base/alloc.h"
#include "base/bytes.h"
#include "base/file.h"
#include "base/strbuild.h"
#include "runtime/core/unwind.h"
#include "runtime/std/net_conn.h"
#include "runtime/std/net_core.h"
#include "runtime/std/net_dgram.h"
#include "runtime/std/net_dns.h"
#include "runtime/std/net_ip.h"
#include "runtime/std/net_network.h"

static const int64_t DEFAULT_TIMEOUT_NS = 5000000000LL;

enum {
  ATTEMPT_NS = 2000000000LL, /* one server's turn before the next is tried */
  UDP_MAX = 4096,
  TCP_MAX = 65535
};

/* The time left until `deadline` (a uv_hrtime value); 0 when it has passed. */
static int64_t remaining(uint64_t deadline) {
  const uint64_t now = uv_hrtime();
  return now >= deadline ? 0 : (int64_t)(deadline - now);
}

static int64_t turn(uint64_t deadline) {
  const int64_t left = remaining(deadline);
  return left < ATTEMPT_NS ? left : ATTEMPT_NS;
}

/* Whether `sender` ("ip:port") is the server "ip:port", compared as addresses. */
static bool same_peer(MsSpan sender, MsSpan server) {
  MsSpan sh, sp, vh, vp;
  MsIp a, b;
  uint16_t pa, pb;
  return ms_split_host_port(sender, &sh, &sp) && ms_split_host_port(server, &vh, &vp) && ms_ip_parse(sh, &a) &&
         ms_ip_parse(vh, &b) && ms_parse_port(sp, &pa) && ms_parse_port(vp, &pb) && pa == pb && a.v6 == b.v6 &&
         ms_span_equal(ms_span_of(a.b, a.v6 ? 16 : 4), ms_span_of(b.b, b.v6 ? 16 : 4));
}

static uint16_t random_id(void) {
  uint16_t id = 0;
  (void)uv_random(NULL, NULL, &id, sizeof id, 0, NULL);
  return id;
}

/* What a query holds across a wait. A cancel unwinds out of the datagram and connection natives (`ms_cancelled`
 * never returns), so each resource is registered as a cleanup before the first wait and discarded when the
 * function ends normally; without it a cancelled lookup leaked its socket and buffers. */
static void close_socket(uint8_t *held) {
  MsObj *socket = *(MsObj **)(void *)held;
  msstd_net_datagram_close(socket);
  socket->drop(socket);
}

static void close_connection(uint8_t *held) {
  MsObj *connection = *(MsObj **)(void *)held;
  msstd_net_connection_close(connection);
  connection->drop(connection);
}

static void free_string_held(uint8_t *held) { ms_string_release((MsString *)(void *)held); }

static void free_bytes_held(uint8_t *held) { ms_bytes_free((MsBytes *)(void *)held); }

/* One query over UDP: false on a status other than a matching answer; `*status` is then the reason. */
static uint8_t exchange_udp(MsSpan server, MsBytes query, uint16_t id, uint64_t deadline, MsBytes *reply, MsString *err) {
  MsSpan host, port;
  MsIp ip;
  if (!ms_split_host_port(server, &host, &port) || !ms_ip_parse(host, &ip)) {
    return MS_STATUS_INVALID_INPUT;
  }
  MsObj *socket = NULL;
  uint8_t status = ms_net_bind_datagram(ms_span_of_text(ip.v6 ? "[::]:0" : "0.0.0.0:0"), &socket, err);
  if (status != MS_STATUS_OK) {
    return status;
  }
  MsString target = ms_string_from_span(server);
  const size_t held = ms_cleanup_push(free_string_held, (uint8_t *)(void *)&target);
  (void)ms_cleanup_push(close_socket, (uint8_t *)(void *)&socket);
  status = msstd_net_datagram_send_bytes(socket, &query, &target, 1, turn(deadline), err);
  while (status == MS_STATUS_OK) {
    MsDatagramWire wire = {0};
    status = msstd_net_datagram_receive(socket, 1, UDP_MAX, 1, turn(deadline), &wire, err);
    if (status != MS_STATUS_OK) {
      break;
    }
    const bool mine = wire.data.len >= 2 && same_peer(ms_string_span(&wire.sender), server) &&
                      ((uint16_t)(wire.data.ptr[0] << 8 | wire.data.ptr[1])) == id;
    ms_string_release(&wire.sender);
    if (mine) {
      *reply = wire.data;
      break;
    }
    ms_bytes_free(&wire.data);
  }
  ms_cleanup_discard(held);
  msstd_net_datagram_close(socket);
  socket->drop(socket);
  ms_string_release(&target);
  return status;
}

/* Reads exactly `count` bytes from the connection onto `out`. */
static uint8_t read_exact(const MsObj *connection, size_t count, uint64_t deadline, MsBytes *out, MsString *err) {
  while (out->len < count) {
    MsBytes chunk = {0};
    const uint8_t status = msstd_net_connection_read(connection, 1, (int64_t)(count - out->len), 1, remaining(deadline),
                                                     &chunk, err);
    if (status != MS_STATUS_OK) {
      return status;
    }
    if (chunk.len == 0) {
      return MS_STATUS_CLOSED;
    }
    for (size_t i = 0; i < chunk.len; i++) {
      ms_list_push(out, 1, &chunk.ptr[i]);
    }
    ms_bytes_free(&chunk);
  }
  return MS_STATUS_OK;
}

/* One query over TCP: a two-byte length before each message. */
static uint8_t exchange_tcp(MsSpan server, MsBytes query, uint64_t deadline, MsBytes *reply, MsString *err) {
  MsObj *connection = NULL;
  uint8_t status = ms_net_dial(server, NULL, remaining(deadline), &connection, err);
  if (status != MS_STATUS_OK) {
    return status;
  }
  const size_t held = ms_cleanup_push(close_connection, (uint8_t *)(void *)&connection);
  MsBytes framed = {0};
  MsBytes head = {0};
  (void)ms_cleanup_push(free_bytes_held, (uint8_t *)(void *)&framed);
  (void)ms_cleanup_push(free_bytes_held, (uint8_t *)(void *)&head);
  const uint8_t prefix[2] = {(uint8_t)(query.len >> 8), (uint8_t)query.len};
  ms_list_push(&framed, 1, &prefix[0]);
  ms_list_push(&framed, 1, &prefix[1]);
  for (size_t i = 0; i < query.len; i++) {
    ms_list_push(&framed, 1, &query.ptr[i]);
  }
  status = msstd_net_connection_write_bytes(connection, &framed, 1, remaining(deadline), err);
  ms_bytes_free(&framed);
  status = status == MS_STATUS_OK ? read_exact(connection, 2, deadline, &head, err) : status;
  if (status == MS_STATUS_OK) {
    status = read_exact(connection, (size_t)(head.ptr[0] << 8 | head.ptr[1]), deadline, reply, err);
  }
  ms_cleanup_discard(held);
  ms_bytes_free(&head);
  msstd_net_connection_close(connection);
  connection->drop(connection);
  return status;
}

static uint8_t unreachable(MsString *err, const char *text) {
  ms_string_release(err);
  *err = ms_string_from_span(ms_span_of_text(text));
  return MS_STATUS_FAILED;
}

/* Asks one server about `name` and parses the answer; an answer with an error code of the server's is a failure. */
static uint8_t ask(MsSpan server, MsSpan name, uint16_t type, int64_t kind, uint64_t deadline, MsDnsAnswer *answer,
                   MsString *err) {
  uint8_t packet[MS_DNS_QUERY_MAX];
  const uint16_t id = random_id();
  const size_t size = ms_dns_build_query(packet, id, name, type);
  if (size == 0) {
    return MS_STATUS_INVALID_INPUT;
  }
  const MsBytes query = ms_bytes_view(ms_span_of(packet, size));
  MsBytes reply = {0};
  const size_t held = ms_cleanup_push(free_bytes_held, (uint8_t *)(void *)&reply);
  uint8_t status = exchange_udp(server, query, id, deadline, &reply, err);
  bool parsed = status == MS_STATUS_OK && ms_dns_parse(ms_bytes_span(&reply), type, kind, answer);
  if (parsed && answer->truncated) {
    ms_dns_answer_free(answer);
    ms_bytes_free(&reply);
    status = exchange_tcp(server, query, deadline, &reply, err);
    parsed = status == MS_STATUS_OK && ms_dns_parse(ms_bytes_span(&reply), type, kind, answer);
  }
  ms_cleanup_discard(held);
  ms_bytes_free(&reply);
  if (status != MS_STATUS_OK) {
    return status;
  }
  return parsed ? MS_STATUS_OK : unreachable(err, "malformed DNS response");
}

/* Tries each server in turn for one name; ENOTFOUND-style answers stop the walk (`*exists` false). */
static uint8_t ask_servers(const MsList *servers, MsSpan name, uint16_t type, int64_t kind, uint64_t deadline,
                           MsList *out, bool *exists, MsString *err) {
  const MsString *items = (const MsString *)(const void *)servers->ptr;
  uint8_t status = MS_STATUS_FAILED;
  for (size_t i = 0; i < servers->len && remaining(deadline) > 0; i++) {
    MsDnsAnswer answer = {0};
    ms_string_release(err);
    status = ask(ms_string_span(&items[i]), name, type, kind, deadline, &answer, err);
    if (status == MS_STATUS_OK && answer.rcode != 0 && answer.rcode != MS_DNS_RCODE_NAME_ERROR) {
      ms_dns_answer_free(&answer);
      status = unreachable(err, "DNS server refused the query");
      continue;
    }
    if (status == MS_STATUS_OK) {
      *exists = answer.rcode == 0;
      *out = answer.records;
      return MS_STATUS_OK;
    }
    ms_dns_answer_free(&answer);
    if (status == MS_STATUS_INVALID_INPUT || status == MS_STATUS_CLOSED) {
      break;
    }
  }
  return remaining(deadline) == 0 && status != MS_STATUS_INVALID_INPUT ? MS_STATUS_TIMED_OUT : status;
}

/* The names to ask for `name`: as given, or with each search suffix, in the order the host's rules give. */
static void candidates(MsSpan name, const MsDnsConfig *config, MsList *out) {
  size_t dots = 0;
  for (size_t i = 0; i < name.len; i++) {
    dots += name.ptr[i] == '.';
  }
  const bool rooted = name.len > 0 && name.ptr[name.len - 1] == '.';
  const bool first = rooted || (int)dots >= config->ndots;
  MsString own = ms_string_from_span(name);
  if (first) {
    ms_list_push(out, sizeof own, &own);
  }
  const MsString *suffixes = (const MsString *)(const void *)config->search.ptr;
  for (size_t i = 0; !rooted && i < config->search.len; i++) {
    MsStrBuild joined = ms_strbuild_new();
    ms_strbuild_append(&joined, name);
    ms_strbuild_append_byte(&joined, '.');
    ms_strbuild_append_string(&joined, &suffixes[i]);
    MsString full = ms_strbuild_finish(&joined);
    ms_list_push(out, sizeof full, &full);
  }
  if (!first) {
    ms_list_push(out, sizeof own, &own);
  }
}

static void free_names(MsList *names) {
  MsString *items = (MsString *)(void *)names->ptr;
  for (size_t i = 0; i < names->len; i++) {
    ms_string_release(&items[i]);
  }
  ms_list_free(names);
}

static void free_names_held(uint8_t *held) { free_names((MsList *)(void *)held); }

static void free_config_held(uint8_t *held) { ms_dns_config_free((MsDnsConfig *)(void *)held); }

#ifdef _WIN32
/* Windows has no resolv.conf: the servers and the primary domain come from the network parameters. */
static void read_host_config(MsDnsConfig *config) {
  ULONG size = 0;
  *config = (MsDnsConfig){.ndots = 1};
  if (GetNetworkParams(NULL, &size) != ERROR_BUFFER_OVERFLOW || size == 0) {
    return;
  }
  FIXED_INFO *info = ms_alloc(size);
  if (GetNetworkParams(info, &size) == NO_ERROR) {
    MsStrBuild text = ms_strbuild_new();
    for (const IP_ADDR_STRING *server = &info->DnsServerList; server != NULL; server = server->Next) {
      ms_strbuild_append_text(&text, "nameserver ");
      ms_strbuild_append_text(&text, server->IpAddress.String);
      ms_strbuild_append_byte(&text, '\n');
    }
    if (info->DomainName[0] != 0) {
      ms_strbuild_append_text(&text, "search ");
      ms_strbuild_append_text(&text, info->DomainName);
      ms_strbuild_append_byte(&text, '\n');
    }
    ms_dns_config_parse(ms_strbuild_span(&text), config);
    ms_strbuild_free(&text);
  }
  ms_free(info);
}
#else
static void read_host_config(MsDnsConfig *config) {
  MsBytes text = {0};
  *config = (MsDnsConfig){.ndots = 1};
  if (ms_file_read(ms_span_of_text("/etc/resolv.conf"), &text)) {
    ms_dns_config_parse(ms_bytes_span(&text), config);
  }
  ms_bytes_free(&text);
}
#endif

uint8_t ms_dns_resolve(MsSpan server, MsSpan name, int64_t kind, int64_t timeout_ns, MsList *out, MsString *err) {
  const uint16_t type = ms_dns_type_of_kind(kind);
  const uint64_t deadline = uv_hrtime() + (uint64_t)(timeout_ns < 0 ? DEFAULT_TIMEOUT_NS : timeout_ns);
  MsDnsConfig config = {.ndots = 1};
  MsList names = {0};
  MsStrBuild reverse = ms_strbuild_new();
  *err = ms_string_empty();
  if (type == 0 || name.len == 0) {
    return MS_STATUS_INVALID_INPUT;
  }
  if (server.len > 0) {
    MsString only = ms_string_from_span(server);
    ms_list_push(&config.servers, sizeof only, &only);
  } else {
    read_host_config(&config);
  }
  if (config.servers.len == 0) {
    ms_dns_config_free(&config);
    return MS_STATUS_UNSUPPORTED; /* the host lists no nameserver */
  }
  MsDnsConfig own = {.ndots = server.len > 0 ? 0 : config.ndots}; /* a chosen server gets the name as written */
  if (kind == MS_DNS_KIND_PTR && ms_dns_reverse_name(name, &reverse)) {
    MsString arpa = ms_strbuild_finish(&reverse);
    ms_list_push(&names, sizeof arpa, &arpa);
  } else {
    candidates(name, server.len > 0 ? &own : &config, &names);
  }
  ms_strbuild_free(&reverse);
  const size_t held = ms_cleanup_push(free_config_held, (uint8_t *)(void *)&config);
  (void)ms_cleanup_push(free_names_held, (uint8_t *)(void *)&names);
  uint8_t status = MS_STATUS_FAILED;
  bool found = false;
  const MsString *tries = (const MsString *)(const void *)names.ptr;
  for (size_t i = 0; i < names.len; i++) {
    bool exists = false;
    MsList records = {0};
    status = ask_servers(&config.servers, ms_string_span(&tries[i]), type, kind, deadline, &records, &exists, err);
    if (status != MS_STATUS_OK) {
      break;
    }
    found = found || exists;
    if (records.len > 0 || (exists && i + 1 == names.len)) {
      *out = records;
      ms_cleanup_discard(held);
      free_names(&names);
      ms_dns_config_free(&config);
      return MS_STATUS_OK;
    }
    ms_dns_records_free(&records);
  }
  ms_cleanup_discard(held);
  free_names(&names);
  ms_dns_config_free(&config);
  if (status == MS_STATUS_OK) {
    if (found) {
      *out = (MsList){0};
      return MS_STATUS_OK; /* the name exists but holds no data of this kind */
    }
    ms_string_release(err);
    *err = ms_string_from_span(ms_span_of_text("cannot resolve host"));
    return MS_STATUS_FAILED;
  }
  return status;
}
