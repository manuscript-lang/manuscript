/* The HTTP client natives of ms_rt/net.h: the client object (ClientH), `msstd_client_fetch` and the response body
 * (BodyH), over the libcurl engine of curl_client.h. */
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../std/abi.h"
#include "addr_text.h"
#include "curl_client.h"
#include "headers.h"
#include "http1.h"
#include "ms_rt/alloc.h"
#include "ms_rt/chars.h"
#include "ms_rt/net.h"
#include "ms_rt/sys.h"
#include "status.h"

enum { READ_DEFAULT = 64 * 1024, READ_ALL_LIMIT = 1 << 30 };

static void release(MsObj *object) {
    if (object != NULL && object->drop != NULL) {
        object->drop(object);
    }
}


/* ---- the client object (ClientH) ---- */

typedef struct ClientObject ClientObject;
struct ClientObject {
    MsObj header;
    ClientObject *self; /* the writable view of the const handle the natives receive */
    MsCurlClient *client;
};

static ClientObject *client_of(const void *handle) { return ((const ClientObject *)handle)->self; }

static void client_drop(MsObj *object) {
    ClientObject *handle = (ClientObject *)object;
    ms_curl_client_release(handle->client);
    msrt_free(handle);
}

/* A handle on `client`, which the caller has retained. */
static MsObj *client_handle(MsCurlClient *client) {
    ClientObject *handle = msrt_alloc_zeroed(sizeof *handle);
    handle->header.drop = client_drop;
    handle->self = handle;
    handle->client = client;
    return &handle->header;
}

uint8_t msstd_client_new(const MsNetHttpOptions *options, void **out, MsStr *err) {
    ms_net_clear_text(err);
    const MsCurlClientOptions settings = {.roots_pem = msrt_str_bytes(&options->roots_pem),
                                          .certificate_pem = msrt_str_bytes(&options->certificate_pem),
                                          .private_key_pem = msrt_str_bytes(&options->private_key_pem),
                                          .unix_socket = msrt_str_bytes(&options->unix_socket),
                                          .resolver = msrt_str_bytes(&options->resolver),
                                          .max_redirects = options->max_redirects,
                                          .cookies = options->cookies != 0,
                                          .decompress = options->decompress != 0};
    MsCurlClient *client = ms_curl_client_new(&settings);
    if (client == NULL) {
        return ms_net_finish(MS_NET_FAILED, 0, err);
    }
    *out = client_handle(client);
    return STATUS_OK;
}

void *msstd_client_share(const void *handle) {
    MsCurlClient *client = client_of(handle)->client;
    ms_curl_client_retain(client);
    return client_handle(client);
}

bool ms_client_same(const void *a, const void *b) { return client_of(a)->client == client_of(b)->client; }

void msstd_client_close(const void *handle) { ms_curl_client_close(client_of(handle)->client); }

uint8_t msstd_client_narrow(const void *handle, const MsVec *hosts, const MsVec *cidrs) {
    const MsStr *host_items = hosts->ptr, *cidr_items = cidrs->ptr;
    MsBytes *host_text = calloc(hosts->len == 0 ? 1 : hosts->len, sizeof *host_text);
    MsBytes *cidr_text = calloc(cidrs->len == 0 ? 1 : cidrs->len, sizeof *cidr_text);
    if (host_text == NULL || cidr_text == NULL) {
        free(host_text);
        free(cidr_text);
        return STATUS_FAILED;
    }
    for (size_t i = 0; i < hosts->len; i++) {
        host_text[i] = msrt_str_bytes(&host_items[i]);
    }
    for (size_t i = 0; i < cidrs->len; i++) {
        cidr_text[i] = msrt_str_bytes(&cidr_items[i]);
    }
    uint8_t status = STATUS_OK;
    if (ms_curl_client_started(client_of(handle)->client)) {
        status = STATUS_BUSY; /* the filter is fixed by the first request */
    }
    if (status == STATUS_OK && !ms_curl_client_narrow(client_of(handle)->client, host_text, hosts->len, cidr_text, cidrs->len)) {
        status = STATUS_INVALID_INPUT;
    }
    free(host_text);
    free(cidr_text);
    return status;
}

/* ---- the body object (BodyH) ---- */

typedef struct BodyObject BodyObject;
struct BodyObject {
    MsObj header;
    BodyObject *self;
    MsCurlTransfer *transfer; /* NULL once closed */
    MsObj *headers;           /* the response's, kept for `metadata` after the close */
    int64_t status;
    const char *protocol;
    int64_t deadline_ns;      /* one deadline covers the head and the whole body */
};

static BodyObject *body_of(const void *handle) { return ((const BodyObject *)handle)->self; }

static void body_end(BodyObject *body) {
    if (body->transfer != NULL) {
        ms_curl_close(body->transfer);
        body->transfer = NULL;
    }
}

static void body_drop(MsObj *object) {
    BodyObject *body = (BodyObject *)object;
    body_end(body);
    release(body->headers);
    msrt_free(body);
}

/* The text of a failed transfer through `err`. */
static uint8_t body_failure(BodyObject *body, MsNetStatus status, MsStr *err) {
    if (status == MS_NET_FAILED && err != NULL) {
        ms_net_write_text(err, ms_curl_message(body->transfer));
        return STATUS_FAILED;
    }
    return ms_net_finish(status, 0, err);
}

/* One read of at most `capacity` bytes into `buffer`; *n is 0 at the end of the body. */
static uint8_t body_read_some(BodyObject *body, uint8_t *buffer, size_t capacity, size_t *n, MsStr *err) {
    *n = 0;
    if (body->transfer == NULL) {
        return STATUS_CLOSED;
    }
    const MsNetStatus status = ms_curl_read(body->transfer, ms_bytes_mut(buffer, capacity), body->deadline_ns, n);
    return status == MS_NET_OK ? STATUS_OK : body_failure(body, status, err);
}

uint8_t msstd_body_read(const void *handle, uint8_t has_max, int64_t max, MsVec *out, MsStr *err) {
    ms_net_clear_text(err); /* the caller takes the slot for every status; only STATUS_FAILED writes text */
    BodyObject *body = body_of(handle);
    if (has_max != 0 && max <= 0) {
        return STATUS_INVALID_INPUT;
    }
    const size_t capacity = has_max != 0 && max < READ_DEFAULT ? (size_t)max : READ_DEFAULT;
    uint8_t *buffer = malloc(capacity);
    if (buffer == NULL) {
        return ms_net_finish(MS_NET_FAILED, 0, err);
    }
    size_t count = 0;
    uint8_t status = body_read_some(body, buffer, capacity, &count, err);
    if (status == STATUS_OK) {
        status = count > 0 ? STATUS_OK : STATUS_NONE;
        if (count > 0) {
            msrt_write_bytes(out, buffer, count);
        }
    }
    free(buffer);
    return status;
}

uint8_t msstd_body_read_all(const void *handle, uint8_t has_max, int64_t max, MsVec *out, MsStr *err) {
    ms_net_clear_text(err); /* the caller takes the slot for every status; only STATUS_FAILED writes text */
    BodyObject *body = body_of(handle);
    if (has_max != 0 && max < 0) {
        return STATUS_INVALID_INPUT;
    }
    const size_t limit = has_max != 0 ? (size_t)max : READ_ALL_LIMIT;
    uint8_t *data = NULL;
    size_t used = 0, capacity = 0;
    uint8_t status = STATUS_OK;
    for (;;) {
        if (used == capacity) {
            const size_t grown = capacity == 0 ? READ_DEFAULT : capacity * 2;
            uint8_t *bigger = realloc(data, grown);
            if (bigger == NULL) {
                status = ms_net_finish(MS_NET_FAILED, 0, err);
                break;
            }
            data = bigger;
            capacity = grown;
        }
        size_t count = 0;
        status = body_read_some(body, data + used, capacity - used, &count, err);
        if (status != STATUS_OK || count == 0) {
            break;
        }
        used += count;
        if (used > limit) {
            status = STATUS_LIMIT_EXCEEDED;
            break;
        }
    }
    if (status == STATUS_OK) {
        msrt_write_bytes(out, data, used);
    }
    free(data);
    return status;
}

void msstd_body_metadata(const void *handle, MsNetBodyMetadata *out) {
    const BodyObject *body = body_of(handle);
    out->status = body->status;
    out->headers = msstd_headers_clone(body->headers);
    ms_net_write_text(&out->protocol, body->protocol);
}

void msstd_body_close(const void *handle) { body_end(body_of(handle)); }

/* ---- the request ---- */

/* The request's fields as one block of bytes with spans, the shape the engine takes. */
typedef struct Block {
    uint8_t *bytes;
    MsH1Field *fields;
    size_t count, length;
} Block;

/* Fields the engine writes itself, which a caller does not set. */
static bool field_refused(MsBytes name) {
    static const char *const written[] = {"host", "content-length", "transfer-encoding"};
    for (size_t i = 0; i < sizeof written / sizeof written[0]; i++) {
        if (ms_ascii_equal_fold(name, ms_bytes_of((const uint8_t *)written[i], strlen(written[i])))) {
            return true;
        }
    }
    return false;
}

/* A hop to another host does not carry the caller's credentials, as in curl. */
static bool credential_field(MsBytes name) {
    return ms_ascii_equal_fold(name, ms_bytes_of((const uint8_t *)"authorization", 13)) || ms_ascii_equal_fold(name, ms_bytes_of((const uint8_t *)"cookie", 6));
}

/* A request that lost its body does not describe one. */
static bool entity_field(MsBytes name) {
    static const char *const names[] = {"content-type", "content-length", "content-encoding", "content-language"};
    for (size_t i = 0; i < sizeof names / sizeof names[0]; i++) {
        if (ms_ascii_equal_fold(name, ms_bytes_of((const uint8_t *)names[i], strlen(names[i])))) {
            return true;
        }
    }
    return false;
}

/* STATUS_INVALID_INPUT for a refused field, a name that is not a token, or a value that could split the head. */
static uint8_t block_make(const MsHeaders *table, bool strip_credentials, bool strip_entity, Block *block) {
    const size_t count = ms_headers_count(table);
    size_t total = 0;
    for (size_t i = 0; i < count; i++) {
        MsBytes name, value;
        ms_headers_field(table, i, &name, &value);
        if (field_refused(name) || !ms_h1_is_token(name) || memchr(value.ptr, '\r', value.len) != NULL ||
            memchr(value.ptr, '\n', value.len) != NULL || (value.len > 0 && memchr(value.ptr, 0, value.len) != NULL)) {
            return STATUS_INVALID_INPUT;
        }
        total += name.len + value.len;
    }
    block->bytes = malloc(total == 0 ? 1 : total);
    block->fields = calloc(count == 0 ? 1 : count, sizeof *block->fields);
    block->length = 0;
    block->count = 0;
    if (block->bytes == NULL || block->fields == NULL) {
        return STATUS_FAILED;
    }
    uint32_t at = 0;
    for (size_t i = 0; i < count; i++) {
        MsBytes name, value;
        ms_headers_field(table, i, &name, &value);
        if ((strip_credentials && credential_field(name)) || (strip_entity && entity_field(name))) {
            continue;
        }
        MsH1Field *field = &block->fields[block->count++];
        memcpy(block->bytes + at, name.ptr, name.len);
        field->name = (MsSpan){at, (uint32_t)name.len};
        at += (uint32_t)name.len;
        if (value.len > 0) {
            memcpy(block->bytes + at, value.ptr, value.len);
        }
        field->value = (MsSpan){at, (uint32_t)value.len};
        at += (uint32_t)value.len;
    }
    block->length = at;
    return STATUS_OK;
}

static void block_free(Block *block) {
    free(block->bytes);
    free(block->fields);
}

/* The header lines of a response ("Name: value\r\n" each) as a table, names in canonical form. NULL when out of
 * memory or past the table's limits. */
static MsObj *response_headers(MsBytes lines) {
    MsHeaders *table = ms_headers_new();
    size_t at = 0;
    while (table != NULL && at < lines.len) {
        const uint8_t *end = memchr(lines.ptr + at, '\n', lines.len - at);
        const size_t stop = end == NULL ? lines.len : (size_t)(end - lines.ptr);
        const uint8_t *colon = memchr(lines.ptr + at, ':', stop - at);
        if (colon != NULL && colon > lines.ptr + at) {
            const uint8_t *value = colon + 1, *limit = lines.ptr + stop;
            while (value < limit && (*value == ' ' || *value == '\t')) {
                value++;
            }
            while (limit > value && (limit[-1] == '\r' || limit[-1] == ' ' || limit[-1] == '\t')) {
                limit--;
            }
            if (!ms_headers_add_canonical(table, ms_bytes_of(lines.ptr + at, (size_t)(colon - (lines.ptr + at))), ms_bytes_of(value, (size_t)(limit - value)))) {
                release(ms_headers_object(table));
                return NULL;
            }
        }
        at = stop + 1;
    }
    return table == NULL ? NULL : ms_headers_object(table);
}

/* The status of a request that did not start: a refused host, a bad request, or the transfer's failure. */
static uint8_t start_failure(MsNetStatus status, MsCurlFault fault, const char *message, MsStr *err) {
    if (fault == MS_CURL_FAULT_DENIED) {
        ms_net_write_text(err, "the network does not allow this host");
        return STATUS_PERMISSION_DENIED;
    }
    if (fault == MS_CURL_FAULT_BAD_REQUEST) {
        return STATUS_INVALID_INPUT;
    }
    if (status == MS_NET_FAILED && message[0] != 0) {
        ms_net_write_text(err, message);
        return STATUS_FAILED;
    }
    return ms_net_finish(status, 0, err);
}

/* The text of one address for curl's resolve list: IPv6 in brackets. */
static void add_address(char **list, size_t *length, const MsStr *address) {
    const bool v6 = memchr(msrt_str_data(address), ':', msrt_str_len(address)) != NULL;
    const size_t extra = msrt_str_len(address) + 4;
    char *grown = realloc(*list, *length + extra);
    if (grown == NULL) {
        return;
    }
    *list = grown;
    *length += (size_t)snprintf(*list + *length, extra, "%s%s%.*s%s", *length > 0 ? "," : "", v6 ? "[" : "",
                                (int)msrt_str_len(address), msrt_str_data(address), v6 ? "]" : "");
}

static void record_drop(const uint8_t *slot) {
    MsNetDnsRecord record;
    memcpy(&record, slot, sizeof record);
    msrt_string_free(&record.value);
}

static void record_copy(const uint8_t *source, uint8_t *destination) {
    MsNetDnsRecord record;
    memcpy(&record, source, sizeof record);
    MsNetDnsRecord copy = record;
    msrt_string_clone(&record.value, &copy.value);
    memcpy(destination, &copy, sizeof copy);
}

/* How a `List[DnsRecord]` from `msstd_dns_query` is dropped. */
static const MsTypeDesc record_desc = {
    .size = sizeof(MsNetDnsRecord),
    .align = _Alignof(MsNetDnsRecord),
    .kind = MS_TYPE_KIND_CUSTOM,
    .drop = record_drop,
    .copy = record_copy,
};

/* With a client that has its own resolver, "host:port:address,..." for the URL's host from that server; *entry stays NULL
 * for the system's resolver and for an IP literal. */
static uint8_t resolve_entry(const MsCurlClient *client, MsBytes url, int64_t deadline, char **entry, MsStr *err) {
    const char *resolver = ms_curl_client_resolver(client);
    char host[256];
    uint16_t port = 0;
    if (resolver == NULL) {
        return STATUS_OK;
    }
    if (!ms_curl_url_target(url, host, sizeof host, &port)) {
        return STATUS_INVALID_INPUT;
    }
    MsAddr literal;
    char wrapped[sizeof host + 8];
    (void)snprintf(wrapped, sizeof wrapped, strchr(host, ':') != NULL ? "[%s]:1" : "%s:1", host);
    if (ms_net_addr_parse(ms_bytes_of((const uint8_t *)wrapped, strlen(wrapped)), &literal)) {
        return STATUS_OK;
    }
    char *list = NULL;
    size_t length = 0;
    uint8_t status = STATUS_OK;
    MsStr server, name;
    msrt_string_from_bytes((const uint8_t *)resolver, strlen(resolver), &server);
    msrt_string_from_bytes((const uint8_t *)host, strlen(host), &name);
    const int64_t kinds[] = {0, 1}; /* DnsKind.A, DnsKind.AAAA */
    for (size_t i = 0; i < 2 && status == STATUS_OK; i++) {
        const int64_t left = deadline < 0 ? 0 : deadline - ms_sys_monotonic_ns();
        MsVec records;
        msrt_list_with_capacity(&record_desc, 0, &records);
        const uint8_t found = msstd_dns_query(&server, &name, kinds[i], deadline >= 0, left > 0 ? left : 1, &records, err);
        if (found == STATUS_OK) {
            const MsNetDnsRecord *items = records.ptr;
            for (size_t k = 0; k < records.len; k++) {
                add_address(&list, &length, &items[k].value);
            }
        } else if (found != STATUS_NONE) {
            status = found;
        }
        msrt_list_drop(&records, &record_desc);
    }
    ms_str_release(&server);
    ms_str_release(&name);
    if (status == STATUS_OK && length == 0) {
        ms_net_write_text(err, "cannot resolve host");
        status = STATUS_FAILED;
    }
    if (status == STATUS_OK) {
        const size_t size = strlen(host) + length + 16;
        *entry = malloc(size);
        if (*entry == NULL) {
            status = STATUS_FAILED;
        } else {
            (void)snprintf(*entry, size, "%s:%u:%.*s", host, (unsigned)port, (int)length, list);
        }
    }
    free(list);
    return status;
}

/* The Location of a redirect in the response's header lines, or empty. */
static MsBytes location_of(MsBytes lines) {
    size_t at = 0;
    while (at < lines.len) {
        const uint8_t *end = memchr(lines.ptr + at, '\n', lines.len - at);
        const size_t stop = end == NULL ? lines.len : (size_t)(end - lines.ptr);
        if (stop - at > 9 && ms_ascii_equal_fold(ms_bytes_of(lines.ptr + at, 9), ms_bytes_of((const uint8_t *)"location:", 9))) {
            size_t from = at + 9, to = stop;
            while (from < to && (lines.ptr[from] == ' ' || lines.ptr[from] == '\t')) {
                from++;
            }
            while (to > from && (lines.ptr[to - 1] == '\r' || lines.ptr[to - 1] == ' ' || lines.ptr[to - 1] == '\t')) {
                to--;
            }
            return ms_bytes_of(lines.ptr + from, to - from);
        }
        at = stop + 1;
    }
    return ms_bytes_of(NULL, 0);
}

static bool same_target_host(MsBytes a, MsBytes b) {
    char first[256], second[256];
    uint16_t port = 0;
    return ms_curl_url_target(a, first, sizeof first, &port) && ms_curl_url_target(b, second, sizeof second, &port) && strcmp(first, second) == 0;
}

static bool is_redirect(int status) { return status == 301 || status == 302 || status == 303 || status == 307 || status == 308; }

/* Takes one redirect: closes `transfer`, then replaces `*current` with `location` resolved against it and applies the
 * method rewrite (301 and 302 turn a POST into a GET, 303 any method but HEAD) and the credential rule for the next
 * request. On a failure `*current` is unchanged. */
static uint8_t redirect_step(MsCurlClient *engine, MsCurlTransfer *transfer, int status, long hops, MsBytes location, char **current,
                             MsBytes *verb, MsBytes *payload, bool *strip, MsStr *err) {
    char *next = NULL;
    const bool exhausted = hops >= ms_curl_client_max_redirects(engine);
    const MsBytes from = ms_bytes_of((const uint8_t *)*current, strlen(*current));
    const bool resolved = !exhausted && ms_curl_url_resolve(from, location, &next);
    ms_curl_close(transfer);
    if (!resolved) {
        ms_net_write_text(err, exhausted ? "too many redirects" : "invalid redirect location");
        return STATUS_FAILED;
    }
    const bool post = verb->len == 4 && memcmp(verb->ptr, "POST", 4) == 0;
    if (status == 303 || ((status == 301 || status == 302) && post)) {
        if (!(verb->len == 4 && memcmp(verb->ptr, "HEAD", 4) == 0)) {
            *verb = ms_bytes_of((const uint8_t *)"GET", 3);
        }
        *payload = ms_bytes_of(NULL, 0);
    }
    *strip = *strip || !same_target_host(from, ms_bytes_of((const uint8_t *)next, strlen(next)));
    free(*current);
    *current = next;
    return STATUS_OK;
}

uint8_t msstd_client_fetch(const void *handle, const MsStr *method, const MsStr *url, const void *headers, const MsVec *body,
                           uint8_t has_timeout, int64_t timeout, void **out, MsStr *err) {
    ms_net_clear_text(err);
    MsCurlClient *engine = client_of(handle)->client;
    const int64_t deadline = ms_net_deadline_of(has_timeout, timeout);
    /* Redirects are followed here, so each hop is checked against the filter, resolved through the client's own server when
       it has one, and sent without the headers of a body it no longer carries. */
    const bool follow = ms_curl_client_max_redirects(engine) > 0;
    char *current = malloc(msrt_str_len(url) + 1);
    if (current == NULL) {
        return ms_net_finish(MS_NET_FAILED, 0, err);
    }
    memcpy(current, msrt_str_data(url), msrt_str_len(url));
    current[msrt_str_len(url)] = 0;
    MsBytes verb = msrt_str_bytes(method), payload = ms_bytes_of(body->ptr, body->len);
    bool strip = false, bodiless = false;
    long hops = 0;
    for (;;) {
        const MsBytes target = ms_bytes_of((const uint8_t *)current, strlen(current));
        Block block = {NULL, NULL, 0, 0};
        uint8_t status = block_make(ms_headers_of(headers), strip, bodiless, &block);
        char *entry = NULL;
        if (status == STATUS_OK) {
            status = resolve_entry(engine, target, deadline, &entry, err);
        }
        if (status != STATUS_OK) {
            block_free(&block);
            free(current);
            return status;
        }
        const MsCurlRequest request = {.method = verb, .url = target, .head = ms_bytes_of(block.bytes, block.length),
                                       .fields = block.fields, .nfields = (uint32_t)block.count, .body = payload,
                                       .resolve = entry == NULL ? ms_bytes_of(NULL, 0) : ms_bytes_of((const uint8_t *)entry, strlen(entry))};
        MsCurlTransfer *transfer = NULL;
        MsCurlFault fault = MS_CURL_FAULT_NONE;
        const char *message = "";
        const MsNetStatus started = ms_curl_start(engine, &request, deadline, &transfer, &fault, &message);
        block_free(&block);
        free(entry);
        if (started != MS_NET_OK) {
            free(current);
            return start_failure(started, fault, message, err);
        }
        const MsCurlHead head = ms_curl_head(transfer);
        const MsBytes location = follow && is_redirect(head.status) ? location_of(head.lines) : ms_bytes_of(NULL, 0);
        if (location.len > 0) {
            const uint8_t failed = redirect_step(engine, transfer, head.status, hops, location, &current, &verb, &payload, &strip, err);
            if (failed != STATUS_OK) {
                free(current);
                return failed;
            }
            bodiless = bodiless || (payload.len == 0 && body->len > 0);
            hops++;
            continue;
        }
        free(current);
        MsObj *received = response_headers(head.lines);
        BodyObject *object = received == NULL ? NULL : msrt_alloc_zeroed(sizeof *object);
        if (object == NULL) {
            release(received);
            ms_curl_close(transfer);
            return ms_net_finish(MS_NET_FAILED, 0, err);
        }
        object->header.drop = body_drop;
        object->self = object;
        object->transfer = transfer;
        object->headers = received;
        object->status = head.status;
        object->protocol = head.protocol;
        object->deadline_ns = deadline;
        *out = &object->header;
        return STATUS_OK;
    }
}
