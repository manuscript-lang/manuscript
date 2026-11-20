/* The HTTP/1 server exchange natives of ms_rt/xchg.h: one request and its response on a connection row.
 *
 * Request. `next` reads bytes with ms_conn_read until llhttp (http1.c) has a complete head, copies the head and the
 * bytes read past it into the exchange, and leaves llhttp's parser in the exchange to frame the body (length or
 * chunked, trailers dropped). Bytes read ahead of the body stay in the exchange and go back to the row with
 * ms_conn_unread when the exchange ends or hands the connection on, so the next request, or the WebSocket
 * reader, sees them first.
 *
 * Response. `send_head` writes the status line and fields in one call and decides the framing: a declared length,
 * chunked (HTTP/1.1) or running to the close (HTTP/1.0). Whether the connection can carry another request is the
 * request's keep-alive, the response being framed, and the request body having been read to its end.
 *
 * The exchange is owned by one task at a time: the handler's. It has no locks. */
#include <llhttp.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

#include "../std/abi.h"
#include "conn_object.h"
#include "exchange_h2.h"
#include "headers.h"
#include "http1.h"
#include "ms_rt/alloc.h"
#include "ms_rt/chars.h"
#include "ms_rt/obj.h"
#include "ms_rt/safe.h"
#include "ms_rt/xchg.h"
#include "status.h"

enum {
    HEAD_LIMIT_DEFAULT = 64 * 1024,
    HEAD_LIMIT_MAX = 1024 * 1024,
    HEAD_READ = 4096,
    FIELDS_MAX = 128, /* more request fields than this are refused with 431 */
    READ_DEFAULT = 64 * 1024,
    READ_LIMIT = 1024 * 1024,
    HEAD_BUFFER_START = 1024,
    CHUNK_FRAME = 32, /* room for a chunk's size line and the line ends */
};

typedef struct MsExchange {
    atomic_uint handles; /* ExchH handles on this exchange; it ends with the last */
    MsXchgH2 *h2;     /* set for a request on an HTTP/2 stream: every call goes to exchange_h2.c */
    MsObj *conn;      /* an alias handle on the connection (not a stream end) */
    uint8_t *head;    /* the request head, as read; the spans below are offsets into it */
    MsH1Field *fields;
    uint32_t field_count;
    MsSpan target;
    uint8_t method;   /* llhttp's code */
    uint8_t minor;
    MsH1Reader reader;
    uint8_t *input;   /* bytes read from the row and not yet consumed by the body parser */
    size_t input_length;
    size_t input_position;
    size_t input_capacity;
    uint8_t request_keep_alive;
    uint8_t body_done;
    uint8_t head_sent;      /* a final (non-1xx) response head went out */
    uint8_t body_allowed;   /* the response may carry a body: not HEAD, 204, 304 */
    uint8_t chunked;
    uint8_t has_length;
    uint8_t response_keep;  /* the response framing lets the connection go on */
    uint8_t spent;          /* finished or handed on */
    uint64_t remaining;     /* bytes of the declared length not written yet */
} MsExchange;

/* What the standard library holds (ExchH): a handle on the shared exchange state. */
typedef struct ExchHandle {
    MsObj header;
    MsExchange *state;
} ExchHandle;

static void state_free(MsExchange *exchange) {
    if (exchange->h2 != NULL) {
        ms_xchg_h2_drop(exchange->h2);
    }
    if (exchange->conn != NULL) {
        msrt_obj_drop(exchange->conn);
    }
    free(exchange->head);
    free(exchange->fields);
    free(exchange->input);
    msrt_free(exchange);
}

static void handle_drop(MsObj *object) {
    ExchHandle *handle = (ExchHandle *)object;
    if (atomic_fetch_sub(&handle->state->handles, 1) == 1) {
        state_free(handle->state);
    }
    msrt_free(handle);
}

/* A handle on `state`, which the caller has already counted. */
static MsObj *handle_new(MsExchange *state) {
    ExchHandle *handle = msrt_alloc(sizeof *handle);
    handle->header.clone = NULL;
    handle->header.drop = handle_drop;
    handle->state = state;
    return &handle->header;
}

/* The reason phrases of the registered status codes (RFC 9110), sorted: llhttp names statuses by enum, not by phrase. */
static const struct { uint16_t status; const char *phrase; } reasons[] = {
    {100, "Continue"},
    {101, "Switching Protocols"},
    {102, "Processing"},
    {103, "Early Hints"},
    {200, "OK"},
    {201, "Created"},
    {202, "Accepted"},
    {203, "Non-Authoritative Information"},
    {204, "No Content"},
    {205, "Reset Content"},
    {206, "Partial Content"},
    {207, "Multi-Status"},
    {208, "Already Reported"},
    {226, "IM Used"},
    {300, "Multiple Choices"},
    {301, "Moved Permanently"},
    {302, "Found"},
    {303, "See Other"},
    {304, "Not Modified"},
    {305, "Use Proxy"},
    {307, "Temporary Redirect"},
    {308, "Permanent Redirect"},
    {400, "Bad Request"},
    {401, "Unauthorized"},
    {402, "Payment Required"},
    {403, "Forbidden"},
    {404, "Not Found"},
    {405, "Method Not Allowed"},
    {406, "Not Acceptable"},
    {407, "Proxy Authentication Required"},
    {408, "Request Timeout"},
    {409, "Conflict"},
    {410, "Gone"},
    {411, "Length Required"},
    {412, "Precondition Failed"},
    {413, "Content Too Large"},
    {414, "URI Too Long"},
    {415, "Unsupported Media Type"},
    {416, "Range Not Satisfiable"},
    {417, "Expectation Failed"},
    {418, "I'm a teapot"},
    {421, "Misdirected Request"},
    {422, "Unprocessable Content"},
    {423, "Locked"},
    {424, "Failed Dependency"},
    {425, "Too Early"},
    {426, "Upgrade Required"},
    {428, "Precondition Required"},
    {429, "Too Many Requests"},
    {431, "Request Header Fields Too Large"},
    {451, "Unavailable For Legal Reasons"},
    {500, "Internal Server Error"},
    {501, "Not Implemented"},
    {502, "Bad Gateway"},
    {503, "Service Unavailable"},
    {504, "Gateway Timeout"},
    {505, "HTTP Version Not Supported"},
    {506, "Variant Also Negotiates"},
    {507, "Insufficient Storage"},
    {508, "Loop Detected"},
    {510, "Not Extended"},
    {511, "Network Authentication Required"},
};

/* The phrase for a status; empty for one that is not registered, which clients ignore anyway. */
static const char *reason_of(unsigned status) {
    for (size_t i = 0; i < MS_COUNT_OF(reasons); i++) {
        if (reasons[i].status == status) {
            return reasons[i].phrase;
        }
    }
    return "";
}

static MsExchange *exchange_of(const void *handle) { return ((const ExchHandle *)handle)->state; }

MsObj *ms_exchange_from_h2(MsXchgH2 *request) {
    MsExchange *exchange = msrt_alloc_zeroed(sizeof *exchange);
    if (exchange == NULL) {
        return NULL;
    }
    atomic_init(&exchange->handles, 1);
    exchange->h2 = request;
    return handle_new(exchange);
}


static MsConnTable *table_of(const MsExchange *exchange) { return ms_netconn_table(ms_netconn_of(exchange->conn)); }
static MsConnId id_of(const MsExchange *exchange) { return ms_netconn_id(ms_netconn_of(exchange->conn)); }

static uint8_t finish_status(const MsExchange *exchange, MsNetStatus status, MsStr *err) {
    return ms_net_finish(status, ms_conn_error_code(table_of(exchange), id_of(exchange)), err);
}

/* ---- request head ---- */

/* Appends what a read brought to `*buffer`, growing it to `limit` plus a read at most. */
static bool buffer_room(uint8_t **buffer, size_t *capacity, size_t length, size_t wanted) {
    if (length + wanted <= *capacity) {
        return true;
    }
    size_t grown = *capacity == 0 ? HEAD_BUFFER_START : *capacity;
    while (grown < length + wanted) {
        grown *= 2;
    }
    uint8_t *bigger = realloc(*buffer, grown);
    if (bigger == NULL) {
        return false;
    }
    *buffer = bigger;
    *capacity = grown;
    return true;
}

/* Copies the parsed head and the bytes after it into a new exchange. */
static MsExchange *exchange_new(const void *conn, const uint8_t *buffer, size_t length, const MsH1Request *request,
                                const MsH1Reader *reader) {
    MsExchange *exchange = msrt_alloc_zeroed(sizeof *exchange);
    atomic_init(&exchange->handles, 1);
    exchange->conn = ms_netconn_alias(conn);
    exchange->head = malloc(request->head_len);
    exchange->fields = malloc((request->nfields + 1) * sizeof *exchange->fields);
    const size_t rest = length - request->head_len;
    exchange->input = malloc(rest + 1);
    if (exchange->conn == NULL || exchange->head == NULL || exchange->fields == NULL || exchange->input == NULL) {
        state_free(exchange);
        return NULL;
    }
    memcpy(exchange->head, buffer, request->head_len);
    memcpy(exchange->fields, request->fields, request->nfields * sizeof *exchange->fields);
    memcpy(exchange->input, buffer + request->head_len, rest);
    exchange->input_length = rest;
    exchange->input_capacity = rest + 1;
    exchange->field_count = request->nfields;
    exchange->target = request->target;
    exchange->method = request->method;
    exchange->minor = request->minor;
    exchange->request_keep_alive = request->keep_alive;
    exchange->reader = *reader;
    ms_h1_reader_moved(&exchange->reader);
    /* A request without a body is complete now: no read of it will ever happen. */
    MsSpan none;
    size_t used = 0;
    exchange->body_done = ms_h1_read_body(&exchange->reader, "", 0, &none, &used) == MS_H1_BODY_DONE;
    return exchange;
}

uint8_t msstd_xchg_next(const void *conn, int64_t head_limit, uint8_t has_timeout, int64_t timeout, void **out, MsStr *err) {
    ms_net_clear_text(err);
    ms_conn_set_refusal(ms_netconn_table(ms_netconn_of(conn)), ms_netconn_id(ms_netconn_of(conn)), 0);
    const MsNetConn *core = ms_netconn_of(conn);
    MsConnTable *table = ms_netconn_table(core);
    const MsConnId id = ms_netconn_id(core);
    const int64_t deadline = ms_net_deadline_of(has_timeout, timeout);
    size_t limit = head_limit > 0 ? (size_t)head_limit : HEAD_LIMIT_DEFAULT;
    limit = limit > HEAD_LIMIT_MAX ? HEAD_LIMIT_MAX : limit;
    uint8_t *buffer = NULL;
    size_t capacity = 0;
    size_t length = 0;
    MsH1Field fields[FIELDS_MAX];
    MsH1Request request = {.fields = fields};
    MsH1Reader reader;
    for (;;) {
        if (!buffer_room(&buffer, &capacity, length, HEAD_READ)) {
            free(buffer);
            return ms_net_finish(MS_NET_FAILED, 0, err);
        }
        size_t count = 0;
        const MsNetStatus status = ms_conn_read(table, id, buffer + length, capacity - length, deadline, &count);
        if (status != MS_NET_OK) {
            free(buffer);
            return ms_net_finish(status, ms_conn_error_code(table, id), err);
        }
        if (count == 0) {
            const bool nothing = length == 0;
            free(buffer);
            return nothing ? STATUS_NONE : ms_net_finish(MS_NET_CLOSED, 0, err);
        }
        length += count;
        const int parsed = ms_h1_parse_request_body(&reader, (const char *)buffer, length, limit, &request, FIELDS_MAX);
        if (parsed == MS_H1_BAD) {
            free(buffer);
            ms_conn_set_refusal(table, id, request.status);
            return STATUS_INVALID_DATA;
        }
        if (parsed == MS_H1_COMPLETE) {
            break;
        }
    }
    MsExchange *exchange = exchange_new(conn, buffer, length, &request, &reader);
    free(buffer);
    if (exchange == NULL) {
        return ms_net_finish(MS_NET_FAILED, 0, err);
    }
    *out = handle_new(exchange);
    return STATUS_OK;
}

int64_t msstd_xchg_reject_status(const void *conn) {
    const MsNetConn *core = ms_netconn_of(conn);
    return ms_conn_refusal(ms_netconn_table(core), ms_netconn_id(core));
}

uint8_t msstd_xchg_reject(const void *conn, int64_t status, uint8_t has_timeout, int64_t timeout, MsStr *err) {
    ms_net_clear_text(err);
    if (status < 400 || status > 599) {
        return STATUS_INVALID_INPUT;
    }
    char text[160];
    size_t used = 0;
    const char *reason = reason_of((unsigned)status);
    if (ms_h1_write_status(text, sizeof text, &used, 1, (unsigned)status, reason, strlen(reason)) != 0 ||
        ms_h1_write_field(text, sizeof text, &used, "Connection", 10, "close", 5) != 0 ||
        ms_h1_write_field(text, sizeof text, &used, "Content-Length", 14, "0", 1) != 0 ||
        ms_h1_write_head_end(text, sizeof text, &used) != 0) {
        return STATUS_FAILED;
    }
    const MsNetConn *core = ms_netconn_of(conn);
    const MsNetStatus sent = ms_conn_write(ms_netconn_table(core), ms_netconn_id(core), (const uint8_t *)text, used, ms_net_deadline_of(has_timeout, timeout));
    return ms_net_finish(sent, ms_conn_error_code(ms_netconn_table(core), ms_netconn_id(core)), err);
}

void msstd_xchg_method(const void *handle, MsStr *out) {
    if (exchange_of(handle)->h2 != NULL) {
        const MsBytes text = (ms_xchg_h2_method(exchange_of(handle)->h2));
        msrt_string_from_bytes(text.ptr, text.len, out);
        return;
    }
    const char *name = llhttp_method_name((llhttp_method_t)exchange_of(handle)->method);
    msrt_string_from_bytes((const uint8_t *)name, strlen(name), out);
}

void msstd_xchg_target(const void *handle, MsStr *out) {
    const MsExchange *exchange = exchange_of(handle);
    if (exchange->h2 != NULL) {
        const MsBytes text = (ms_xchg_h2_target(exchange->h2));
        msrt_string_from_bytes(text.ptr, text.len, out);
        return;
    }
    msrt_string_from_bytes(exchange->head + exchange->target.off, exchange->target.len, out);
}

void msstd_xchg_protocol(const void *handle, MsStr *out) {
    if (exchange_of(handle)->h2 != NULL) {
        const MsBytes text = (ms_xchg_h2_protocol(exchange_of(handle)->h2));
        msrt_string_from_bytes(text.ptr, text.len, out);
        return;
    }
    const char *version = exchange_of(handle)->minor == 0 ? "HTTP/1.0" : "HTTP/1.1";
    msrt_string_from_bytes((const uint8_t *)version, strlen(version), out);
}

void *msstd_xchg_headers(const void *handle) {
    const MsExchange *exchange = exchange_of(handle);
    if (exchange->h2 != NULL) {
        MsHeaders *table = ms_xchg_h2_headers(exchange->h2);
        return table == NULL ? NULL : ms_headers_object(table);
    }
    MsHeaders *table = ms_headers_new();
    for (uint32_t i = 0; table != NULL && i < exchange->field_count; i++) {
        const MsH1Field *field = &exchange->fields[i];
        const MsBytes field_name = ms_bytes_of(exchange->head + field->name.off, field->name.len);
        const MsBytes field_value = ms_bytes_of(exchange->head + field->value.off, field->value.len);
        if (!ms_headers_add_canonical(table, field_name, field_value)) {
            msrt_obj_drop(ms_headers_object(table));
            table = NULL;
        }
    }
    return table == NULL ? NULL : ms_headers_object(table);
}

void *msstd_xchg_share(const void *handle) {
    MsExchange *exchange = exchange_of(handle);
    atomic_fetch_add(&exchange->handles, 1);
    return handle_new(exchange);
}

/* ---- request body ---- */

/* Makes room for a read of up to `wanted` bytes with nothing pending. */
static bool input_reset(MsExchange *exchange, size_t wanted) {
    exchange->input_length = 0;
    exchange->input_position = 0;
    return buffer_room(&exchange->input, &exchange->input_capacity, 0, wanted);
}

/* The next piece of body into `out` (at most `capacity` bytes; dropped when `out` is NULL) or STATUS_NONE at its end. */
static uint8_t read_piece(MsExchange *exchange, size_t capacity, int64_t deadline, MsVec *out, size_t *count_out, MsStr *err) {
    for (;;) {
        if (exchange->body_done) {
            return STATUS_NONE;
        }
        const size_t available = exchange->input_length - exchange->input_position;
        if (available == 0 && exchange->input_length > 0) {
            exchange->input_length = 0;
            exchange->input_position = 0;
        }
        /* A request with no body answers at once, with or without bytes; the fed length stays zero then. */
        const size_t feed = available < capacity ? available : capacity;
        const uint8_t *base = exchange->input + exchange->input_position;
        MsSpan span = {0, 0};
        size_t used = 0;
        const int result = ms_h1_read_body(&exchange->reader, (const char *)base, feed, &span, &used);
        exchange->input_position += used;
        if (result == MS_H1_BODY_DATA) {
            if (out != NULL) {
                msrt_write_bytes(out, base + span.off, span.len);
            }
            *count_out = span.len;
            return STATUS_OK;
        }
        if (result == MS_H1_BODY_DONE) {
            exchange->body_done = 1;
            return STATUS_NONE;
        }
        if (result == MS_H1_BODY_BAD) {
            return STATUS_INVALID_DATA;
        }
        if (feed < available) {
            continue; /* the parser took what it was given and wants more; more is already here */
        }
        if (!input_reset(exchange, capacity < READ_DEFAULT ? capacity : READ_DEFAULT)) {
            return ms_net_finish(MS_NET_FAILED, 0, err);
        }
        size_t count = 0;
        const MsNetStatus status = ms_conn_read(table_of(exchange), id_of(exchange), exchange->input, exchange->input_capacity, deadline, &count);
        if (status != MS_NET_OK) {
            return finish_status(exchange, status, err);
        }
        if (count == 0) {
            if (ms_h1_read_body_eof(&exchange->reader) == MS_H1_BODY_DONE) {
                exchange->body_done = 1;
                return STATUS_NONE;
            }
            return STATUS_INVALID_DATA;
        }
        exchange->input_length = count;
    }
}

uint8_t msstd_xchg_read(const void *handle, uint8_t has_max, int64_t max, uint8_t has_timeout, int64_t timeout, MsVec *out, MsStr *err) {
    ms_net_clear_text(err);
    MsExchange *exchange = exchange_of(handle);
    if (exchange->h2 != NULL) {
        return ms_xchg_h2_read(exchange->h2, has_max, max, has_timeout, timeout, out, err);
    }
    if (has_max != 0 && max < 0) {
        return STATUS_INVALID_INPUT;
    }
    if (exchange->spent) {
        return STATUS_INVALID_INPUT;
    }
    size_t capacity = READ_DEFAULT;
    if (has_max != 0) {
        capacity = max > READ_LIMIT ? READ_LIMIT : (size_t)max;
    }
    if (capacity == 0) {
        msrt_write_bytes(out, NULL, 0);
        return STATUS_OK;
    }
    size_t taken = 0;
    return read_piece(exchange, capacity, ms_net_deadline_of(has_timeout, timeout), out, &taken, err);
}

uint8_t msstd_xchg_reset(const void *handle, int64_t max, uint8_t has_timeout, int64_t timeout, MsStr *err) {
    ms_net_clear_text(err);
    MsExchange *exchange = exchange_of(handle);
    if (exchange->h2 != NULL) {
        return ms_xchg_h2_reset(exchange->h2, max, has_timeout, timeout, err);
    }
    if (exchange->spent) {
        return STATUS_INVALID_INPUT;
    }
    const int64_t deadline = ms_net_deadline_of(has_timeout, timeout);
    int64_t dropped = 0;
    for (;;) {
        size_t taken = 0;
        const uint8_t status = read_piece(exchange, READ_DEFAULT, deadline, NULL, &taken, err);
        if (status == STATUS_NONE) {
            return STATUS_OK;
        }
        if (status != STATUS_OK) {
            return status;
        }
        dropped += (int64_t)taken;
        if (dropped > max) {
            return STATUS_LIMIT_EXCEEDED;
        }
    }
}

uint8_t msstd_xchg_wait_gone(const void *handle, MsStr *err) {
    ms_net_clear_text(err);
    MsExchange *exchange = exchange_of(handle);
    if (exchange->h2 != NULL) {
        return ms_xchg_h2_wait_gone(exchange->h2, err);
    }
    const MsNetStatus status = ms_conn_wait_gone(table_of(exchange), id_of(exchange), &exchange->spent);
    return status == MS_NET_RESET || status == MS_NET_CLOSED ? STATUS_OK : finish_status(exchange, status, err);
}

/* ---- response ---- */

static bool field_is(const MsBytes name, const char *expected) {
    return ms_ascii_equal_fold(name, ms_bytes_of((const uint8_t *)expected, strlen(expected)));
}

/* Builds the head into `dst`; -1 when it does not fit, -2 when a field is unsafe. `*keep` says the connection goes on. */
static int build_head(char *dst, size_t cap, size_t *used, const MsExchange *exchange, unsigned status, const MsHeaders *headers,
                      bool framed, bool chunked, uint64_t length, bool keep, bool close_header) {
    *used = 0;
    const char *reason = reason_of(status);
    if (ms_h1_write_status(dst, cap, used, 1, status, reason, strlen(reason)) != 0) {
        return -1;
    }
    const size_t count = headers == NULL ? 0 : ms_headers_count(headers);
    for (size_t i = 0; i < count; i++) {
        MsBytes name, value;
        ms_headers_field(headers, i, &name, &value);
        /* A 101 head names the protocol it switches to (`Connection: Upgrade`); every other head lets the framing say it. */
        if (field_is(name, "content-length") || field_is(name, "transfer-encoding") || (field_is(name, "connection") && status != 101)) {
            continue;
        }
        const int written = ms_h1_write_field(dst, cap, used, (const char *)name.ptr, name.len, (const char *)value.ptr, value.len);
        if (written != 0) {
            return written;
        }
    }
    int written = 0;
    if (framed && chunked) {
        written = ms_h1_write_field(dst, cap, used, "Transfer-Encoding", 17, "chunked", 7);
    } else if (framed) {
        char digits[24];
        size_t count_digits = 0;
        uint64_t rest = length;
        do {
            digits[sizeof digits - 1 - count_digits++] = (char)('0' + rest % 10);
            rest /= 10;
        } while (rest > 0);
        written = ms_h1_write_field(dst, cap, used, "Content-Length", 14, digits + sizeof digits - count_digits, count_digits);
    }
    if (written == 0 && close_header) {
        written = ms_h1_write_field(dst, cap, used, "Connection", 10, keep ? "keep-alive" : "close", keep ? 10 : 5);
    }
    if (written != 0) {
            return written;
    }
    (void)exchange;
    return ms_h1_write_head_end(dst, cap, used);
}

/* Whether the response fields ask for the connection to close. */
static bool headers_ask_close(const MsHeaders *headers) {
    const size_t count = headers == NULL ? 0 : ms_headers_count(headers);
    for (size_t i = 0; i < count; i++) {
        MsBytes name, value;
        ms_headers_field(headers, i, &name, &value);
        if (field_is(name, "connection") && ms_h1_value_has_token(value, ms_bytes_of((const uint8_t *)"close", 5))) {
            return true;
        }
    }
    return false;
}

uint8_t msstd_xchg_send_head(const void *handle, int64_t status, const void *headers_handle, uint8_t has_length, int64_t length, uint8_t has_timeout, int64_t timeout, MsStr *err) {
    ms_net_clear_text(err);
    MsExchange *exchange = exchange_of(handle);
    if (exchange->h2 != NULL) {
        return ms_xchg_h2_send_head(exchange->h2, status, headers_handle == NULL ? NULL : ms_headers_of(headers_handle), has_length, length, err);
    }
    if (exchange->spent || exchange->head_sent || status < 100 || status > 999 || (has_length != 0 && length < 0)) {
        return STATUS_INVALID_INPUT;
    }
    const MsHeaders *headers = headers_handle == NULL ? NULL : ms_headers_of(headers_handle);
    const bool informational = status < 200;
    const bool bodiless = informational || status == 204 || status == 304;
    const bool head_request = exchange->method == HTTP_HEAD;
    /* A 1xx head carries no framing, and a 204 or 304 has no body to frame. */
    const bool framed = !bodiless && (has_length != 0 || exchange->minor >= 1);
    const bool chunked = framed && has_length == 0;
    const bool keep = !informational && exchange->request_keep_alive != 0 && (framed || bodiless) && !headers_ask_close(headers);
    /* HTTP/1.1 keeps by default; only an HTTP/1.0 keep-alive or a close needs saying. */
    const bool close_header = !informational && (exchange->minor == 0 ? keep : !keep);
    size_t capacity = HEAD_BUFFER_START;
    uint8_t *buffer = NULL;
    size_t used = 0;
    int built = -1;
    while (built == -1) {
        uint8_t *bigger = realloc(buffer, capacity);
        if (bigger == NULL) {
            free(buffer);
            return ms_net_finish(MS_NET_FAILED, 0, err);
        }
        buffer = bigger;
        built = build_head((char *)buffer, capacity, &used, exchange, (unsigned)status, headers, framed, chunked,
                           has_length != 0 ? (uint64_t)length : 0, keep, close_header);
        capacity *= 2;
    }
    if (built != 0) {
            free(buffer);
        return STATUS_INVALID_INPUT;
    }
    const MsNetStatus sent = ms_conn_write(table_of(exchange), id_of(exchange), buffer, used, ms_net_deadline_of(has_timeout, timeout));
    free(buffer);
    if (sent != MS_NET_OK) {
        return finish_status(exchange, sent, err);
    }
    if (informational) {
        return STATUS_OK;
    }
    exchange->head_sent = 1;
    exchange->body_allowed = !bodiless && !head_request;
    exchange->chunked = chunked;
    exchange->has_length = has_length != 0 && exchange->body_allowed;
    exchange->remaining = has_length != 0 ? (uint64_t)length : 0;
    exchange->response_keep = keep;
    return STATUS_OK;
}

uint8_t msstd_xchg_write(const void *handle, const MsVec *data, uint8_t has_timeout, int64_t timeout, MsStr *err) {
    ms_net_clear_text(err);
    MsExchange *exchange = exchange_of(handle);
    if (exchange->h2 != NULL) {
        return ms_xchg_h2_write(exchange->h2, ms_bytes_of(data->ptr, data->len), has_timeout, timeout, err);
    }
    if (exchange->spent || !exchange->head_sent) {
        return STATUS_INVALID_INPUT;
    }
    if (data->len == 0) {
        return STATUS_OK;
    }
    if (!exchange->body_allowed) {
        /* A HEAD answer drops its body; a 204 or 304 may not have one. */
        return exchange->method == HTTP_HEAD ? STATUS_OK : STATUS_INVALID_INPUT;
    }
    if (exchange->has_length) {
        if (data->len > exchange->remaining) {
            return STATUS_OUT_OF_RANGE;
        }
        exchange->remaining -= data->len;
    }
    const int64_t deadline = ms_net_deadline_of(has_timeout, timeout);
    MsNetStatus sent;
    if (exchange->chunked) {
        size_t used = 0;
        char *frame = malloc(data->len + CHUNK_FRAME);
        if (frame == NULL) {
            return ms_net_finish(MS_NET_FAILED, 0, err);
        }
        if (ms_h1_write_chunk(frame, data->len + CHUNK_FRAME, &used, (const char *)data->ptr, data->len) != 0) {
            free(frame);
            return STATUS_FAILED;
        }
        sent = ms_conn_write(table_of(exchange), id_of(exchange), (const uint8_t *)frame, used, deadline);
        free(frame);
    } else {
        sent = ms_conn_write(table_of(exchange), id_of(exchange), data->ptr, data->len, deadline);
    }
    return sent == MS_NET_OK ? STATUS_OK : finish_status(exchange, sent, err);
}

/* Gives the bytes read ahead back to the row. */
static MsNetStatus unread_input(MsExchange *exchange) {
    const size_t pending = exchange->input_length - exchange->input_position;
    const MsNetStatus status = ms_conn_unread(table_of(exchange), id_of(exchange), exchange->input + exchange->input_position, pending);
    exchange->input_length = 0;
    exchange->input_position = 0;
    return status;
}

uint8_t msstd_xchg_finish(const void *handle, uint8_t has_timeout, int64_t timeout, uint8_t *keep, MsStr *err) {
    ms_net_clear_text(err);
    MsExchange *exchange = exchange_of(handle);
    if (exchange->h2 != NULL) {
        return ms_xchg_h2_finish(exchange->h2, has_timeout, timeout, keep, err);
    }
    *keep = 0;
    if (exchange->spent || !exchange->head_sent) {
        return STATUS_INVALID_INPUT;
    }
    exchange->spent = 1;
    if (exchange->has_length && exchange->remaining != 0) {
        return STATUS_INVALID_DATA;
    }
    if (exchange->chunked && exchange->body_allowed) {
        char last[8];
        size_t used = 0;
        if (ms_h1_write_chunk(last, sizeof last, &used, NULL, 0) != 0) {
            return STATUS_FAILED;
        }
        const MsNetStatus sent = ms_conn_write(table_of(exchange), id_of(exchange), (const uint8_t *)last, used, ms_net_deadline_of(has_timeout, timeout));
        if (sent != MS_NET_OK) {
            return finish_status(exchange, sent, err);
        }
    }
    if (exchange->response_keep && exchange->body_done) {
        const MsNetStatus returned = unread_input(exchange);
        if (returned != MS_NET_OK) {
            return finish_status(exchange, returned, err);
        }
        *keep = 1;
    }
    return STATUS_OK;
}

uint8_t msstd_xchg_take_conn(const void *handle, void **out) {
    MsExchange *exchange = exchange_of(handle);
    if (exchange->h2 != NULL || exchange->spent || exchange->head_sent) { /* an upgrade is HTTP/1 only */
        return STATUS_INVALID_INPUT;
    }
    if (unread_input(exchange) != MS_NET_OK) {
        return STATUS_FAILED;
    }
    exchange->spent = 1;
    *out = ms_netconn_share(exchange->conn);
    return *out == NULL ? STATUS_FAILED : STATUS_OK;
}
