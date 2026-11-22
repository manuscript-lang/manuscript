/* The Network handle and the natives that open sockets through it (see net_network.h). */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include "runtime/std/net_network.h"

#include <stdatomic.h>
#include <string.h>

#include "base/alloc.h"
#include "runtime/std/http_client_abi.h"
#include "runtime/std/net_conn.h"
#include "runtime/std/net_core.h"
#include "runtime/std/net_dns.h"
#include "runtime/std/net_filter.h"
#include "runtime/std/net_ip.h"

/* ---- the network ---- */

typedef struct Member {
  MsObj *object;
  bool network; /* a network derived from this one, not a socket */
  bool client;  /* an HTTP client handle, not a socket */
} Member;

typedef struct Network {
  atomic_uint handles;
  uv_mutex_t lock;
  bool closed;
  MsNetFilter *filter; /* NULL: unrestricted */
  bool allow_listen;
  MsString resolver; /* "ip:port" of the DNS server, or empty for the host's */
  Member *members;
  size_t count;
  size_t capacity;
} Network;

typedef struct NetworkHandle {
  MsObj header;
  Network *network;
} NetworkHandle;

static Network *network_of(const MsObj *handle) { return ((const NetworkHandle *)handle)->network; }

static void drop_object(MsObj *object) { object->drop(object); }

static void network_free(Network *network) {
  for (size_t i = 0; i < network->count; i++) {
    drop_object(network->members[i].object);
  }
  ms_free(network->members);
  ms_net_filter_release(network->filter);
  ms_string_release(&network->resolver);
  uv_mutex_destroy(&network->lock);
  ms_free(network);
}

static void handle_drop(MsObj *object) {
  NetworkHandle *handle = (NetworkHandle *)object;
  Network *network = handle->network;
  ms_free(handle);
  if (atomic_fetch_sub(&network->handles, 1) == 1) {
    network_free(network);
  }
}

static MsObj *handle_new(Network *network) {
  NetworkHandle *handle = ms_alloc_zeroed(sizeof *handle);
  atomic_fetch_add(&network->handles, 1);
  handle->header.drop = handle_drop;
  handle->network = network;
  return &handle->header;
}

static Network *network_new(MsNetFilter *filter, bool allow_listen, MsString resolver) {
  Network *network = ms_alloc_zeroed(sizeof *network);
  atomic_init(&network->handles, 0);
  (void)uv_mutex_init(&network->lock);
  network->filter = filter;
  network->allow_listen = allow_listen;
  network->resolver = resolver;
  return network;
}

MsObj *msstd_net_network(void) { return handle_new(network_new(NULL, true, ms_string_empty())); }

/* Drops the members whose socket has closed, so a long-lived network does not collect them. */
static void sweep(Network *network) {
  size_t kept = 0;
  for (size_t i = 0; i < network->count; i++) {
    const Member member = network->members[i];
    const bool gone = member.client ? ms_http_client_handle_closed(member.object)
                                    : !member.network && atomic_load(&ms_net_handle_core(member.object)->closed);
    if (gone) {
      drop_object(member.object);
    } else {
      network->members[kept++] = member;
    }
  }
  network->count = kept;
}

/* Records `object`, a handle the network now owns; false (the caller closes it) when the network is closed. */
static bool track(Network *network, MsObj *object, bool is_network, bool is_client) {
  uv_mutex_lock(&network->lock);
  const bool open = !network->closed;
  if (open) {
    if (network->count == network->capacity) {
      sweep(network);
    }
    if (network->count == network->capacity) {
      network->capacity = network->capacity == 0 ? 8 : network->capacity * 2;
      network->members = ms_realloc(network->members, network->capacity * sizeof *network->members);
    }
    network->members[network->count++] = (Member){.object = object, .network = is_network, .client = is_client};
  }
  uv_mutex_unlock(&network->lock);
  return open;
}

static void close_network(Network *network);

static void close_member(Member member) {
  if (member.client) {
    msstd_http_client_close(member.object);
  } else if (member.network) {
    close_network(network_of(member.object));
  } else {
    ms_net_handle_close(member.object);
  }
}

static void close_network(Network *network) {
  uv_mutex_lock(&network->lock);
  const bool first = !network->closed;
  network->closed = true;
  Member *members = network->members;
  const size_t count = network->count;
  network->members = NULL;
  network->count = 0;
  network->capacity = 0;
  uv_mutex_unlock(&network->lock);
  if (!first) {
    return;
  }
  for (size_t i = 0; i < count; i++) {
    close_member(members[i]);
    drop_object(members[i].object);
  }
  ms_free(members);
}

void msstd_net_network_close(const MsObj *net) { close_network(network_of(net)); }

static bool is_open(Network *network) {
  uv_mutex_lock(&network->lock);
  const bool open = !network->closed;
  uv_mutex_unlock(&network->lock);
  return open;
}

/* Hands `socket` to the caller and keeps the network's own handle on it; a closed network closes it instead. */
static uint8_t adopt(Network *network, MsObj *socket, MsObj **out) {
  if (!track(network, ms_net_handle_alias(socket), false, false)) {
    ms_net_handle_close(socket);
    drop_object(socket);
    return MS_STATUS_CLOSED;
  }
  *out = socket;
  return MS_STATUS_OK;
}

/* ---- opening sockets ---- */

uint8_t msstd_net_network_connect(const MsObj *net, const MsString *address, uint8_t has_timeout, int64_t timeout,
                                  MsObj **out, MsString *err) {
  Network *network = network_of(net);
  MsSpan host = {0};
  MsSpan port = {0};
  MsObj *socket = NULL;
  *err = ms_string_empty();
  if (!is_open(network)) {
    return MS_STATUS_CLOSED;
  }
  if (ms_split_host_port(ms_string_span(address), &host, &port) && !ms_net_filter_host_allowed(network->filter, host)) {
    return MS_STATUS_PERMISSION_DENIED;
  }
  const uint8_t status = ms_net_dial(ms_string_span(address), network->filter, ms_net_timeout(has_timeout, timeout),
                                     &socket, err);
  return status == MS_STATUS_OK ? adopt(network, socket, out) : status;
}

uint8_t msstd_net_network_connect_unix(const MsObj *net, const MsString *path, uint8_t has_timeout, int64_t timeout,
                                       MsObj **out, MsString *err) {
  Network *network = network_of(net);
  MsObj *socket = NULL;
  *err = ms_string_empty();
  if (!is_open(network)) {
    return MS_STATUS_CLOSED;
  }
  if (network->filter != NULL) {
    return MS_STATUS_PERMISSION_DENIED;
  }
  const uint8_t status = ms_net_dial_unix(ms_string_span(path), ms_net_timeout(has_timeout, timeout), &socket, err);
  return status == MS_STATUS_OK ? adopt(network, socket, out) : status;
}

/* Whether `network` may listen or bind on the IP literal `address`. */
static bool may_listen(const Network *network, MsSpan address) {
  struct sockaddr_storage parsed;
  if (network->filter == NULL) {
    return true;
  }
  return network->allow_listen && ms_net_parse_literal(address, &parsed) &&
         ms_net_filter_address_allowed(network->filter, (const struct sockaddr *)(const void *)&parsed);
}

uint8_t msstd_net_network_listen(const MsObj *net, const MsString *address, MsObj **out, MsString *err) {
  Network *network = network_of(net);
  MsObj *socket = NULL;
  *err = ms_string_empty();
  if (!is_open(network)) {
    return MS_STATUS_CLOSED;
  }
  if (!may_listen(network, ms_string_span(address))) {
    return MS_STATUS_PERMISSION_DENIED;
  }
  const uint8_t status = ms_net_listen(ms_string_span(address), &socket, err);
  return status == MS_STATUS_OK ? adopt(network, socket, out) : status;
}

uint8_t msstd_net_network_listen_unix(const MsObj *net, const MsString *path, MsObj **out, MsString *err) {
  Network *network = network_of(net);
  MsObj *socket = NULL;
  *err = ms_string_empty();
  if (!is_open(network)) {
    return MS_STATUS_CLOSED;
  }
  if (network->filter != NULL) {
    return MS_STATUS_PERMISSION_DENIED;
  }
  const uint8_t status = ms_net_listen_unix(ms_string_span(path), &socket, err);
  return status == MS_STATUS_OK ? adopt(network, socket, out) : status;
}

uint8_t msstd_net_network_bind_datagram(const MsObj *net, const MsString *address, MsObj **out, MsString *err) {
  Network *network = network_of(net);
  MsObj *socket = NULL;
  *err = ms_string_empty();
  if (!is_open(network)) {
    return MS_STATUS_CLOSED;
  }
  if (!may_listen(network, ms_string_span(address))) {
    return MS_STATUS_PERMISSION_DENIED;
  }
  const uint8_t status = ms_net_bind_datagram(ms_string_span(address), &socket, err);
  return status == MS_STATUS_OK ? adopt(network, socket, out) : status;
}

/* ---- names ---- */

typedef struct LookupOp {
  MsNetOp op;
  char *name;
  int family; /* AF_UNSPEC, AF_INET or AF_INET6 */
  uv_getaddrinfo_t request;
  MsNetFilter *filter; /* a reference, or NULL */
  size_t limit;        /* the most addresses to keep */
  MsList found;        /* strings */
} LookupOp;

static void lookup_release(MsNetOp *op) {
  LookupOp *lookup = (LookupOp *)op;
  MsString *items = (MsString *)(void *)lookup->found.ptr;
  for (size_t i = 0; i < lookup->found.len; i++) {
    ms_string_release(&items[i]);
  }
  ms_list_free(&lookup->found);
  ms_net_filter_release(lookup->filter);
  ms_free(lookup->name);
}

static bool seen(const MsList *found, MsSpan text) {
  const MsString *items = (const MsString *)(const void *)found->ptr;
  for (size_t i = 0; i < found->len; i++) {
    if (ms_span_equal(ms_string_span(&items[i]), text)) {
      return true;
    }
  }
  return false;
}

static void on_lookup(uv_getaddrinfo_t *request, int status, struct addrinfo *result) {
  LookupOp *lookup = request->data;
  for (const struct addrinfo *entry = result; status == 0 && entry != NULL && lookup->found.len < lookup->limit;
       entry = entry->ai_next) {
    char text[INET6_ADDRSTRLEN + 1];
    if (!ms_net_filter_address_allowed(lookup->filter, entry->ai_addr) || uv_ip_name(entry->ai_addr, text, sizeof text) != 0) {
      continue;
    }
    const MsSpan name = ms_span_of_text(text);
    if (!seen(&lookup->found, name)) {
      MsString item = ms_string_from_span(name);
      ms_list_push(&lookup->found, sizeof item, &item);
    }
  }
  if (result != NULL) {
    uv_freeaddrinfo(result);
  }
  ms_net_op_done(&lookup->op, status == 0 && lookup->found.len == 0 ? UV_EAI_NONAME : status);
}

static void lookup_start(MsNetOp *op) {
  LookupOp *lookup = (LookupOp *)op;
  lookup->request.data = lookup;
  const struct addrinfo hints = {.ai_family = lookup->family, .ai_socktype = SOCK_STREAM};
  const int code = uv_getaddrinfo(ms_net_loop(), &lookup->request, on_lookup, lookup->name, NULL, &hints);
  if (code != 0) {
    ms_net_op_done(op, code);
  }
}

static void lookup_abandon(MsNetOp *op) { (void)uv_cancel((uv_req_t *)&((LookupOp *)op)->request); }

static uint8_t lookup_run(const MsObj *net, const MsString *name, int family, uint8_t has_max, int64_t max,
                          uint8_t has_timeout, int64_t timeout, MsList *out, MsString *err) {
  Network *network = network_of(net);
  const MsSpan text = ms_string_span(name);
  *err = ms_string_empty();
  if (!is_open(network)) {
    return MS_STATUS_CLOSED;
  }
  if (text.len == 0 || memchr(text.ptr, 0, text.len) != NULL || (has_max != 0 && max < 0)) {
    return MS_STATUS_INVALID_INPUT;
  }
  if (!ms_net_filter_host_allowed(network->filter, text)) {
    return MS_STATUS_PERMISSION_DENIED;
  }
  LookupOp *lookup = ms_net_op_new(sizeof *lookup, lookup_start, lookup_abandon, lookup_release);
  lookup->name = ms_alloc(text.len + 1);
  memcpy(lookup->name, text.ptr, text.len);
  lookup->name[text.len] = 0;
  lookup->family = family;
  lookup->filter = ms_net_filter_retain(network->filter);
  lookup->limit = has_max != 0 ? (size_t)max : SIZE_MAX;
  const MsNetWait wait = ms_net_run(&lookup->op, ms_net_timeout(has_timeout, timeout));
  const uint8_t status = ms_net_finish(wait, wait == MS_NET_WAIT_DONE ? lookup->op.status : 0, "lookup", err);
  if (wait != MS_NET_WAIT_DONE) {
    return status;
  }
  if (status == MS_STATUS_OK) {
    *out = lookup->found;
    lookup->found = (MsList){0};
  }
  ms_net_op_free(&lookup->op);
  return status;
}

uint8_t msstd_net_network_lookup(const MsObj *net, const MsString *name, uint8_t has_max, int64_t max,
                                 uint8_t has_timeout, int64_t timeout, MsList *out, MsString *err) {
  return lookup_run(net, name, AF_UNSPEC, has_max, max, has_timeout, timeout, out, err);
}

/* Whether the address text of a record may be used under the network's filter. */
static bool record_allowed(const MsNetFilter *filter, int64_t kind, MsSpan text) {
  struct sockaddr_storage address;
  char zeroed[INET6_ADDRSTRLEN + 1];
  if (kind != MS_DNS_KIND_A && kind != MS_DNS_KIND_AAAA) {
    return true;
  }
  if (text.len >= sizeof zeroed) {
    return false;
  }
  memcpy(zeroed, text.ptr, text.len);
  zeroed[text.len] = 0;
  const int code = kind == MS_DNS_KIND_A ? uv_ip4_addr(zeroed, 0, (struct sockaddr_in *)(void *)&address)
                                         : uv_ip6_addr(zeroed, 0, (struct sockaddr_in6 *)(void *)&address);
  return code == 0 && ms_net_filter_address_allowed(filter, (const struct sockaddr *)(const void *)&address);
}

/* Keeps at most `limit` of `records` that the filter allows. */
static void keep_allowed(const MsNetFilter *filter, MsList *records, size_t limit) {
  MsDnsRecord *items = (MsDnsRecord *)(void *)records->ptr;
  size_t kept = 0;
  for (size_t i = 0; i < records->len; i++) {
    if (kept < limit && record_allowed(filter, items[i].kind, ms_string_span(&items[i].value))) {
      items[kept++] = items[i];
    } else {
      ms_string_release(&items[i].value);
    }
  }
  records->len = kept;
}

uint8_t msstd_net_network_resolve(const MsObj *net, const MsString *name, int64_t kind, uint8_t has_max, int64_t max,
                                  uint8_t has_timeout, int64_t timeout, MsList *out, MsString *err) {
  Network *network = network_of(net);
  const MsSpan text = ms_string_span(name);
  *err = ms_string_empty();
  if (!is_open(network)) {
    return MS_STATUS_CLOSED;
  }
  if (ms_dns_type_of_kind(kind) == 0 || text.len == 0 || memchr(text.ptr, 0, text.len) != NULL ||
      (has_max != 0 && max < 0)) {
    return MS_STATUS_INVALID_INPUT;
  }
  if (kind != MS_DNS_KIND_PTR && !ms_net_filter_host_allowed(network->filter, text)) {
    return MS_STATUS_PERMISSION_DENIED;
  }
  const size_t limit = has_max != 0 ? (size_t)max : SIZE_MAX;
  const bool addresses = kind == MS_DNS_KIND_A || kind == MS_DNS_KIND_AAAA;
  MsList found = {0};
  uint8_t status = MS_STATUS_OK;
  if (addresses && ms_string_span(&network->resolver).len == 0) { /* the system resolver answers addresses */
    status = lookup_run(net, name, kind == MS_DNS_KIND_A ? AF_INET : AF_INET6, has_max, max, has_timeout, timeout, &found, err);
    MsString *strings = (MsString *)(void *)found.ptr;
    MsList records = {0};
    for (size_t i = 0; status == MS_STATUS_OK && i < found.len; i++) {
      const MsDnsRecord record = {.kind = kind, .value = strings[i]};
      ms_list_push(&records, sizeof record, &record);
    }
    ms_list_free(&found);
    *out = records;
    return status;
  }
  status = ms_dns_resolve(ms_string_span(&network->resolver), text, kind, ms_net_timeout(has_timeout, timeout), &found, err);
  if (status != MS_STATUS_OK) {
    return status;
  }
  keep_allowed(network->filter, &found, limit);
  *out = found;
  return MS_STATUS_OK;
}

/* ---- restrict ---- */

uint8_t msstd_net_network_restrict(const MsObj *net, const MsList *hosts, const MsList *cidrs, uint8_t allow_listen,
                                   MsObj **out, MsString *err) {
  Network *network = network_of(net);
  *err = ms_string_empty();
  if (!is_open(network)) {
    return MS_STATUS_CLOSED;
  }
  MsNetFilter *filter = ms_net_filter_narrow(network->filter, hosts, cidrs);
  if (filter == NULL) {
    return MS_STATUS_INVALID_INPUT;
  }
  MsObj *child = handle_new(network_new(filter, network->allow_listen && allow_listen != 0, ms_string_clone(&network->resolver)));
  if (!track(network, handle_new(network_of(child)), true, false)) {
    close_network(network_of(child));
  }
  *out = child;
  return MS_STATUS_OK;
}

uint8_t msstd_net_network_with_resolver(const MsObj *net, const MsString *address, MsObj **out, MsString *err) {
  Network *network = network_of(net);
  struct sockaddr_storage parsed;
  *err = ms_string_empty();
  if (!is_open(network)) {
    return MS_STATUS_CLOSED;
  }
  MsSpan host, port;
  uint16_t number;
  MsIp ip;
  const MsSpan text = ms_string_span(address);
  if (!ms_split_host_port(text, &host, &port) || !ms_ip_parse(host, &ip) || !ms_parse_port(port, &number) ||
      !ms_net_parse_literal(text, &parsed)) {
    return MS_STATUS_INVALID_INPUT;
  }
  if (!ms_net_filter_host_allowed(network->filter, host) ||
      !ms_net_filter_address_allowed(network->filter, (const struct sockaddr *)(const void *)&parsed)) {
    return MS_STATUS_PERMISSION_DENIED;
  }
  MsObj *child = handle_new(network_new(ms_net_filter_retain(network->filter), network->allow_listen, ms_string_clone(address)));
  if (!track(network, handle_new(network_of(child)), true, false)) {
    close_network(network_of(child));
  }
  *out = child;
  return MS_STATUS_OK;
}

/* ---- what the HTTP clients of this network may reach ---- */

MsNetFilter *ms_net_network_filter(const MsObj *net) {
  Network *network = network_of(net);
  return network->filter != NULL ? ms_net_filter_retain(network->filter) : NULL;
}

bool ms_net_network_adopt_client(const MsObj *net, MsObj *client) {
  return track(network_of(net), client, false, true);
}
