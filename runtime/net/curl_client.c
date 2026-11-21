#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c11 */
/* The HTTP client engine on libcurl (curl_client.h). */
#include "curl_client.h"

#include <curl/curl.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <uv.h>

#include "addr_text.h"
#include "ms_rt/chars.h"
#include "ms_rt/sys.h"
#include "ms_rt/sys_net.h"
#include "ms_sched.h"
#include "net_filter.h"

#if LIBCURL_VERSION_NUM < 0x075500
#error "libcurl 7.85 or newer is required (CURLOPT_PROTOCOLS_STR)"
#endif

enum {
    BUFFER_BYTES = 256 * 1024, /* body bytes buffered per transfer before it is paused */
    DRIVER_STACK = 512 * 1024,
    POLL_MS = 1000,
    DEFAULT_REDIRECTS = 20
};

struct MsCurlClient {
    atomic_uint references;
    CURLSH *share;       /* the client's connection pool, cookies and DNS cache */
    MsNetFilter *filter;
    uint8_t *roots, *certificate, *key; /* owned copies of the PEM texts */
    char *unix_socket;   /* NUL-terminated path, or NULL for TCP */
    char *resolver;      /* NUL-terminated DNS server, or NULL for the system's */
    size_t roots_length, certificate_length, key_length;
    long max_redirects;
    bool cookies, decompress;
    MsCurlClient *next_dead; /* the driver's list of clients to free */
    atomic_bool started; /* a request has been made: the filter is fixed */
    /* guarded by the driver lock */
    bool closed;
    MsCurlTransfer *live; /* the transfers not yet destroyed, newest first */
};

/* What the driver does for a transfer, set under the driver lock. */
enum { WORK_ADD = 1, WORK_UNPAUSE = 2, WORK_REMOVE = 4, WORK_DETACH = 8 };

struct MsCurlTransfer {
    MsCurlTransfer *next_work; /* the driver's work list */
    MsCurlTransfer *live_next, **live_prev; /* the client's list of live transfers (live_prev is NULL when unlinked) */
    unsigned work;
    bool queued;
    bool retired; /* its removal is running: nothing may be posted to it, for it is about to be freed */
    CURL *easy;
    MsCurlClient *client;
    struct curl_slist *fields;
    struct curl_slist *resolve;
    char error[CURL_ERROR_SIZE];
    /* guarded by the driver lock from here */
    uint8_t *buffer;
    size_t start, length;
    bool head_ready, done, paused, closed; /* closed: the client was closed and ended this transfer */
    CURLcode result;
    uint64_t waiter; /* the token of the task parked on this transfer, or 0 */
    MsCurlFault fault;
    int response_code;   /* the status of the response whose lines are being collected */
    MsCurlHead head;
    char *lines;
    size_t lines_length, lines_capacity;
};

/* ---- the driver ---- */

static struct {
    uv_mutex_t lock;
    CURLM *multi;
    MsSysThread *thread;
    bool global; /* curl_global_init has run: libcurl's allocators are set, so every other call may follow */
    MsCurlTransfer *work;
    MsCurlClient *dead; /* released clients the driver frees: a share's connections belong to the driver's multi */
    bool stop;
} driver;

static uv_once_t driver_once = UV_ONCE_INIT;
static void driver_init_lock(void) { uv_mutex_init(&driver.lock); }

static void wake_waiter(MsCurlTransfer *transfer) {
    if (transfer->waiter != 0) {
        msrt_token_post_remote(transfer->waiter, 1);
        transfer->waiter = 0;
    }
}

/* Queues `work` for the driver and wakes it. The caller holds the lock. */
static void post_work(MsCurlTransfer *transfer, unsigned work) {
    if (transfer->retired) {
        return;
    }
    transfer->work |= work;
    if (!transfer->queued) {
        transfer->queued = true;
        transfer->next_work = driver.work;
        driver.work = transfer;
    }
    if (driver.multi != NULL) {
        (void)curl_multi_wakeup(driver.multi);
    }
}

/* Records the head of the response whose first body bytes (or end) have arrived. The caller holds the lock. */
static void finish_head(MsCurlTransfer *transfer) {
    long code = 0, version = 0;
    (void)curl_easy_getinfo(transfer->easy, CURLINFO_RESPONSE_CODE, &code);
    (void)curl_easy_getinfo(transfer->easy, CURLINFO_HTTP_VERSION, &version);
    transfer->head.status = (int)code;
    switch (version) {
    case CURL_HTTP_VERSION_1_0: transfer->head.protocol = "HTTP/1.0"; break;
    case CURL_HTTP_VERSION_2_0: transfer->head.protocol = "HTTP/2.0"; break;
    case CURL_HTTP_VERSION_3: transfer->head.protocol = "HTTP/3.0"; break;
    default: transfer->head.protocol = "HTTP/1.1"; break;
    }
    transfer->head.lines = ms_bytes_of((const uint8_t *)transfer->lines, transfer->lines_length);
    transfer->head_ready = true;
    wake_waiter(transfer);
}

/* `host` without the brackets of an IPv6 literal. */
static MsBytes bare_host(const char *host) {
    size_t length = strlen(host);
    if (length >= 2 && host[0] == '[' && host[length - 1] == ']') {
        return ms_bytes_of((const uint8_t *)host + 1, length - 2);
    }
    return ms_bytes_of((const uint8_t *)host, length);
}

static bool starts_with_fold(const char *line, size_t length, const char *prefix) {
    const size_t n = strlen(prefix);
    return length >= n && ms_ascii_equal_fold(ms_bytes_of((const uint8_t *)line, n), ms_bytes_of((const uint8_t *)prefix, n));
}

/* Collects the header lines of the response in progress; a new status line starts over (redirects and interim
 * responses come first). A Location the client may not follow ends the transfer before the next hop connects. */
static size_t on_header(char *line, size_t size, size_t count, void *argument) {
    MsCurlTransfer *transfer = argument;
    const size_t length = size * count;
    if (starts_with_fold(line, length, "HTTP/")) {
        uv_mutex_lock(&driver.lock);
        transfer->lines_length = 0;
        transfer->response_code = 0;
        int code = 0;
        const char *space = memchr(line, ' ', length);
        for (size_t i = 1; space != NULL && i <= 3 && (size_t)(space - line) + i < length && ms_ascii_is_digit((uint8_t)space[i]); i++) {
            code = code * 10 + (space[i] - '0');
        }
        transfer->response_code = code;
        uv_mutex_unlock(&driver.lock);
        return length;
    }
    uv_mutex_lock(&driver.lock);
    if (!transfer->head_ready && length > 2 && transfer->lines_length + length <= (size_t)256 * 1024) { /* the blank line and trailers are not kept */
        if (transfer->lines_length + length > transfer->lines_capacity) {
            size_t capacity = transfer->lines_capacity == 0 ? 1024 : transfer->lines_capacity * 2;
            while (capacity < transfer->lines_length + length) {
                capacity *= 2;
            }
            char *grown = realloc(transfer->lines, capacity);
            if (grown != NULL) {
                transfer->lines = grown;
                transfer->lines_capacity = capacity;
            }
        }
        if (transfer->lines_length + length <= transfer->lines_capacity) {
            memcpy(transfer->lines + transfer->lines_length, line, length);
            transfer->lines_length += length;
        }
    }
    uv_mutex_unlock(&driver.lock);
    return length;
}

/* Body bytes. Everything is taken or nothing is: a chunk that does not fit pauses the transfer, and curl offers it
 * again after the unpause. */
static size_t on_body(char *data, size_t size, size_t count, void *argument) {
    MsCurlTransfer *transfer = argument;
    const size_t length = size * count;
    uv_mutex_lock(&driver.lock);
    if (transfer->closed) {
        uv_mutex_unlock(&driver.lock);
        return 0; /* a short write aborts the transfer */
    }
    if (!transfer->head_ready) {
        finish_head(transfer);
    }
    size_t taken = length;
    if (BUFFER_BYTES - transfer->length < length) {
        transfer->paused = true;
        taken = (size_t)CURL_WRITEFUNC_PAUSE;
    } else {
        const size_t end = (transfer->start + transfer->length) % BUFFER_BYTES;
        const size_t first = BUFFER_BYTES - end < length ? BUFFER_BYTES - end : length;
        memcpy(transfer->buffer + end, data, first);
        memcpy(transfer->buffer, data + first, length - first);
        transfer->length += length;
        wake_waiter(transfer);
    }
    uv_mutex_unlock(&driver.lock);
    return taken;
}

/* Refuses a connection to an address the client's filter does not allow, before a socket exists. */
static curl_socket_t on_open_socket(void *argument, curlsocktype purpose, struct curl_sockaddr *address) {
    MsCurlTransfer *transfer = argument;
    MsAddr target;
    MsSock socket;
    if (purpose != CURLSOCKTYPE_IPCXN || ms_sys_net_addr_from_raw(&address->addr, address->addrlen, &target) != MS_SYS_OK) {
        return CURL_SOCKET_BAD;
    }
    if (!ms_net_filter_address_allowed(transfer->client->filter, &target)) {
        uv_mutex_lock(&driver.lock);
        transfer->fault = MS_CURL_FAULT_DENIED;
        uv_mutex_unlock(&driver.lock);
        return CURL_SOCKET_BAD;
    }
    return ms_sys_net_tcp_socket(&target, &socket) == MS_SYS_OK ? (curl_socket_t)socket : CURL_SOCKET_BAD;
}

static void finish_transfer(MsCurlTransfer *transfer, CURLcode result) {
    uv_mutex_lock(&driver.lock);
    if (transfer->closed) { /* the client's close already ended it */
        uv_mutex_unlock(&driver.lock);
        return;
    }
    transfer->done = true;
    transfer->result = result;
    if (!transfer->head_ready) {
        finish_head(transfer);
    }
    wake_waiter(transfer);
    uv_mutex_unlock(&driver.lock);
}

static void free_dead(void);

static void destroy_transfer(MsCurlTransfer *transfer) {
    uv_mutex_lock(&driver.lock);
    if (transfer->live_prev != NULL) {
        *transfer->live_prev = transfer->live_next;
        if (transfer->live_next != NULL) {
            transfer->live_next->live_prev = transfer->live_prev;
        }
        transfer->live_prev = NULL;
    }
    uv_mutex_unlock(&driver.lock);
    curl_easy_cleanup(transfer->easy);
    curl_slist_free_all(transfer->fields);
    curl_slist_free_all(transfer->resolve);
    ms_curl_client_release(transfer->client);
    free(transfer->buffer);
    free(transfer->lines);
    free(transfer);
}

/* Runs the work posted since the last pass. A transfer stays marked queued until its turn, so a post that arrives
 * meanwhile only adds to its work; one that arrives after its turn starts the next pass. */
static void run_work(void) {
    uv_mutex_lock(&driver.lock);
    MsCurlTransfer *list = driver.work;
    driver.work = NULL;
    uv_mutex_unlock(&driver.lock);
    while (list != NULL) {
        MsCurlTransfer *transfer = list;
        uv_mutex_lock(&driver.lock);
        list = transfer->next_work;
        const unsigned work = transfer->work;
        transfer->work = 0;
        transfer->queued = false;
        transfer->retired = (work & WORK_REMOVE) != 0;
        uv_mutex_unlock(&driver.lock);
        if ((work & WORK_ADD) != 0 && (curl_easy_setopt(transfer->easy, CURLOPT_SHARE, transfer->client->share) != CURLE_OK ||
                                       curl_multi_add_handle(driver.multi, transfer->easy) != CURLM_OK)) {
            finish_transfer(transfer, CURLE_FAILED_INIT);
        }
        if ((work & WORK_UNPAUSE) != 0) {
            (void)curl_easy_pause(transfer->easy, CURLPAUSE_CONT);
        }
        if ((work & WORK_DETACH) != 0) {
            (void)curl_multi_remove_handle(driver.multi, transfer->easy);
        }
        if ((work & WORK_REMOVE) != 0) {
            (void)curl_multi_remove_handle(driver.multi, transfer->easy); /* harmless when it is already out */
            destroy_transfer(transfer);
        }
    }
}

static void collect_finished(void) {
    int pending;
    CURLMsg *message;
    while ((message = curl_multi_info_read(driver.multi, &pending)) != NULL) {
        if (message->msg != CURLMSG_DONE) {
            continue;
        }
        MsCurlTransfer *transfer = NULL;
        (void)curl_easy_getinfo(message->easy_handle, CURLINFO_PRIVATE, (char **)&transfer);
        (void)curl_multi_remove_handle(driver.multi, message->easy_handle); /* a clean finish returns the connection to the pool */
        finish_transfer(transfer, message->data.result);
    }
}

static void driver_main(void *argument) {
    (void)argument;
    for (;;) {
        run_work();
        free_dead();
        int running = 0;
        (void)curl_multi_perform(driver.multi, &running);
        collect_finished();
        uv_mutex_lock(&driver.lock);
        const bool stop = driver.stop && driver.work == NULL && driver.dead == NULL;
        uv_mutex_unlock(&driver.lock);
        if (stop) {
            return;
        }
        (void)curl_multi_poll(driver.multi, NULL, 0, POLL_MS, NULL);
    }
}

/* Initializes libcurl once. The caller holds the lock. libcurl sets its allocators here, so no other call (not
 * even curl_share_init) is valid before it: on macOS the unset allocator is a null function pointer. */
static bool global_ensure(void) {
    if (!driver.global) {
        driver.global = curl_global_init(CURL_GLOBAL_DEFAULT) == CURLE_OK;
    }
    return driver.global;
}

static bool global_ready(void) {
    uv_once(&driver_once, driver_init_lock);
    uv_mutex_lock(&driver.lock);
    const bool ready = global_ensure();
    uv_mutex_unlock(&driver.lock);
    return ready;
}

/* Starts the driver if it is not running. */
static bool driver_ensure(void) {
    uv_once(&driver_once, driver_init_lock);
    uv_mutex_lock(&driver.lock);
    if (driver.thread == NULL) {
        driver.stop = false;
        if (global_ensure()) {
            driver.multi = curl_multi_init();
        }
        driver.thread = driver.multi == NULL ? NULL : ms_sys_thread_spawn(DRIVER_STACK, driver_main, NULL);
        if (driver.thread == NULL && driver.multi != NULL) {
            curl_multi_cleanup(driver.multi);
            driver.multi = NULL;
        }
    }
    const bool running = driver.thread != NULL;
    uv_mutex_unlock(&driver.lock);
    return running;
}

void ms_curl_shutdown(void) {
    uv_once(&driver_once, driver_init_lock);
    uv_mutex_lock(&driver.lock);
    MsSysThread *thread = driver.thread;
    driver.stop = true;
    if (driver.multi != NULL) {
        (void)curl_multi_wakeup(driver.multi);
    }
    uv_mutex_unlock(&driver.lock);
    if (thread != NULL) {
        ms_sys_thread_join(thread);
        free_dead();
        curl_multi_cleanup(driver.multi);
        curl_global_cleanup();
        uv_mutex_lock(&driver.lock);
        driver.global = false;
        driver.thread = NULL;
        driver.multi = NULL;
        uv_mutex_unlock(&driver.lock);
    }
}

/* ---- clients ---- */

static uint8_t *copy_bytes(MsBytes bytes) {
    uint8_t *copy = malloc(bytes.len == 0 ? 1 : bytes.len);
    if (copy != NULL && bytes.len > 0) {
        memcpy(copy, bytes.ptr, bytes.len);
    }
    return copy;
}

static char *terminated(MsBytes text);

MsCurlClient *ms_curl_client_new(const MsCurlClientOptions *options) {
    if (!global_ready()) {
        return NULL;
    }
    MsCurlClient *client = calloc(1, sizeof *client);
    if (client == NULL) {
        return NULL;
    }
    atomic_init(&client->references, 1);
    client->max_redirects = options->max_redirects < 0 ? DEFAULT_REDIRECTS : (long)options->max_redirects;
    client->cookies = options->cookies;
    client->decompress = options->decompress;
    client->filter = ms_net_filter_new();
    client->roots = copy_bytes(options->roots_pem);
    client->certificate = copy_bytes(options->certificate_pem);
    client->key = copy_bytes(options->private_key_pem);
    client->roots_length = options->roots_pem.len;
    client->certificate_length = options->certificate_pem.len;
    client->key_length = options->private_key_pem.len;
    client->unix_socket = options->unix_socket.len == 0 ? NULL : terminated(options->unix_socket);
    client->resolver = options->resolver.len == 0 ? NULL : terminated(options->resolver);
    client->share = curl_share_init();
    if (client->share != NULL) {
        (void)curl_share_setopt(client->share, CURLSHOPT_SHARE, CURL_LOCK_DATA_CONNECT);
        (void)curl_share_setopt(client->share, CURLSHOPT_SHARE, CURL_LOCK_DATA_DNS);
        (void)curl_share_setopt(client->share, CURLSHOPT_SHARE, CURL_LOCK_DATA_SSL_SESSION);
        if (client->cookies) {
            (void)curl_share_setopt(client->share, CURLSHOPT_SHARE, CURL_LOCK_DATA_COOKIE);
        }
    }
    if (client->filter == NULL || client->share == NULL || client->roots == NULL || client->certificate == NULL || client->key == NULL ||
        (options->unix_socket.len != 0 && client->unix_socket == NULL) || (options->resolver.len != 0 && client->resolver == NULL)) {
        ms_curl_client_release(client);
        return NULL;
    }
    return client;
}

void ms_curl_client_retain(MsCurlClient *client) { atomic_fetch_add(&client->references, 1); }

static void free_client(MsCurlClient *client) {
    if (client->share != NULL) {
        (void)curl_share_cleanup(client->share);
    }
    ms_net_filter_free(client->filter);
    free(client->roots);
    free(client->certificate);
    free(client->key);
    free(client->unix_socket);
    free(client->resolver);
    free(client);
}

/* Frees the clients released since the last pass. */
static void free_dead(void) {
    uv_mutex_lock(&driver.lock);
    MsCurlClient *list = driver.dead;
    driver.dead = NULL;
    uv_mutex_unlock(&driver.lock);
    while (list != NULL) {
        MsCurlClient *client = list;
        list = client->next_dead;
        free_client(client);
    }
}

/* The last reference frees the client. While the driver runs it does that: the share holds connections the driver's multi
 * manages, and cleaning it up from another thread would race with the driver. */
void ms_curl_client_release(MsCurlClient *client) {
    if (client == NULL || atomic_fetch_sub(&client->references, 1) != 1) {
        return;
    }
    uv_once(&driver_once, driver_init_lock);
    uv_mutex_lock(&driver.lock);
    const bool driven = driver.thread != NULL && !driver.stop;
    if (driven) {
        client->next_dead = driver.dead;
        driver.dead = client;
        (void)curl_multi_wakeup(driver.multi);
    }
    uv_mutex_unlock(&driver.lock);
    if (!driven) {
        free_client(client);
    }
}

void ms_curl_client_close(MsCurlClient *client) {
    uv_once(&driver_once, driver_init_lock);
    uv_mutex_lock(&driver.lock);
    client->closed = true;
    for (MsCurlTransfer *transfer = client->live; transfer != NULL; transfer = transfer->live_next) {
        if (transfer->closed || transfer->retired) {
            continue;
        }
        transfer->closed = true;
        if (!transfer->done) { /* the driver stops the transfer; readers see the close at once */
            post_work(transfer, WORK_DETACH);
        }
        transfer->done = true;
        transfer->head_ready = true;
        transfer->length = 0;
        wake_waiter(transfer);
    }
    uv_mutex_unlock(&driver.lock);
}

const char *ms_curl_client_resolver(const MsCurlClient *client) { return client->resolver; }

long ms_curl_client_max_redirects(const MsCurlClient *client) { return client->max_redirects; }

bool ms_curl_url_resolve(MsBytes base, MsBytes reference, char **out) {
    char *base_text = terminated(base), *reference_text = terminated(reference), *found = NULL;
    CURLU *handle = curl_url();
    bool ok = base_text != NULL && reference_text != NULL && handle != NULL && curl_url_set(handle, CURLUPART_URL, base_text, 0) == CURLUE_OK &&
              curl_url_set(handle, CURLUPART_URL, reference_text, 0) == CURLUE_OK && curl_url_get(handle, CURLUPART_URL, &found, 0) == CURLUE_OK;
    *out = ok ? strdup(found) : NULL;
    ok = *out != NULL;
    curl_free(found);
    curl_url_cleanup(handle);
    free(base_text);
    free(reference_text);
    return ok;
}

bool ms_curl_url_target(MsBytes url, char *host, size_t capacity, uint16_t *port) {
    char *text = terminated(url), *found = NULL, *service = NULL;
    CURLU *handle = curl_url();
    const bool ok = text != NULL && handle != NULL && curl_url_set(handle, CURLUPART_URL, text, 0) == CURLUE_OK &&
                    curl_url_get(handle, CURLUPART_HOST, &found, 0) == CURLUE_OK &&
                    curl_url_get(handle, CURLUPART_PORT, &service, CURLU_DEFAULT_PORT) == CURLUE_OK;
    const MsBytes bare = ok ? bare_host(found) : ms_bytes_of(NULL, 0);
    const bool fits = ok && bare.len < capacity;
    if (fits) {
        memcpy(host, bare.ptr, bare.len);
        host[bare.len] = 0;
        *port = (uint16_t)strtoul(service, NULL, 10);
    }
    curl_free(found);
    curl_free(service);
    curl_url_cleanup(handle);
    free(text);
    return fits;
}

bool ms_curl_client_started(const MsCurlClient *client) { return atomic_load(&client->started); }

bool ms_curl_client_narrow(MsCurlClient *client, const MsBytes *hosts, size_t host_count, const MsBytes *cidrs, size_t cidr_count) {
    return ms_net_filter_narrow(client->filter, hosts, host_count, cidrs, cidr_count);
}

/* ---- starting and waiting ---- */

static _Thread_local char last_message[CURL_ERROR_SIZE];

static char *terminated(MsBytes text) {
    char *copy = malloc(text.len + 1);
    if (copy != NULL) {
        memcpy(copy, text.ptr, text.len);
        copy[text.len] = 0;
    }
    return copy;
}

/* The request's method and body on the easy handle. A custom method is used only for the ones curl has no switch
 * for: a custom request would keep the method across a redirect that should turn into a GET. */
static bool set_method(CURL *easy, const MsCurlRequest *request, char **custom) {
    const MsBytes method = request->method;
    *custom = NULL;
    if (ms_bytes_is_text(method, "HEAD")) {
        return curl_easy_setopt(easy, CURLOPT_NOBODY, 1L) == CURLE_OK;
    }
    const bool has_body = request->body.len > 0 || ms_bytes_is_text(method, "POST") || ms_bytes_is_text(method, "PUT") || ms_bytes_is_text(method, "PATCH");
    if (!ms_bytes_is_text(method, "GET") && !ms_bytes_is_text(method, "POST")) {
        *custom = terminated(method);
        if (*custom == NULL || curl_easy_setopt(easy, CURLOPT_CUSTOMREQUEST, *custom) != CURLE_OK) {
            return false;
        }
    }
    if (has_body) {
        return curl_easy_setopt(easy, CURLOPT_POSTFIELDSIZE_LARGE, (curl_off_t)request->body.len) == CURLE_OK &&
               curl_easy_setopt(easy, CURLOPT_COPYPOSTFIELDS, request->body.len == 0 ? "" : (const char *)request->body.ptr) == CURLE_OK;
    }
    return true;
}

static struct curl_slist *request_fields(const MsCurlRequest *request) {
    struct curl_slist *list = NULL;
    for (uint32_t i = 0; i < request->nfields; i++) {
        const MsH1Field *f = &request->fields[i];
        const size_t name = f->name.len, value = f->value.len;
        char *line = malloc(name + value + 3);
        if (line == NULL) {
            curl_slist_free_all(list);
            return NULL;
        }
        memcpy(line, request->head.ptr + f->name.off, name);
        if (value == 0) {
            line[name] = ';'; /* curl sends an empty field for "Name;" and drops the field for "Name:" */
            line[name + 1] = 0;
        } else {
            line[name] = ':';
            line[name + 1] = ' ';
            memcpy(line + name + 2, request->head.ptr + f->value.off, value);
            line[name + 2 + value] = 0;
        }
        struct curl_slist *grown = curl_slist_append(list, line);
        free(line);
        if (grown == NULL) {
            curl_slist_free_all(list);
            return NULL;
        }
        list = grown;
    }
    return list;
}

/* Whether the URL's host passes the client's filter. False also for a URL curl cannot parse. */
static bool url_allowed(const MsCurlClient *client, const char *url, bool *parsed) {
    char *host = NULL;
    CURLU *handle = curl_url();
    *parsed = handle != NULL && curl_url_set(handle, CURLUPART_URL, url, 0) == CURLUE_OK && curl_url_get(handle, CURLUPART_HOST, &host, 0) == CURLUE_OK;
    const bool allowed = *parsed && ms_net_filter_host_allowed(client->filter, bare_host(host));
    curl_free(host);
    curl_url_cleanup(handle);
    return allowed;
}

static bool configure(MsCurlTransfer *transfer, const MsCurlRequest *request, const char *url, int64_t deadline_ns, char **custom) {
    CURL *easy = transfer->easy;
    const MsCurlClient *client = transfer->client;
    const int64_t left = deadline_ns < 0 ? 0 : deadline_ns - ms_sys_monotonic_ns();
    long milliseconds = 0;
    if (deadline_ns >= 0) {
        milliseconds = left <= 0 ? 1 : (long)(left / 1000000 + 1);
    }
    const struct curl_blob roots = {client->roots, client->roots_length, CURL_BLOB_COPY};
    const struct curl_blob certificate = {client->certificate, client->certificate_length, CURL_BLOB_COPY};
    const struct curl_blob key = {client->key, client->key_length, CURL_BLOB_COPY};
    bool ok = curl_easy_setopt(easy, CURLOPT_URL, url) == CURLE_OK && curl_easy_setopt(easy, CURLOPT_PRIVATE, transfer) == CURLE_OK &&
              curl_easy_setopt(easy, CURLOPT_NOSIGNAL, 1L) == CURLE_OK && curl_easy_setopt(easy, CURLOPT_ERRORBUFFER, transfer->error) == CURLE_OK &&
              curl_easy_setopt(easy, CURLOPT_WRITEFUNCTION, on_body) == CURLE_OK && curl_easy_setopt(easy, CURLOPT_WRITEDATA, transfer) == CURLE_OK &&
              curl_easy_setopt(easy, CURLOPT_HEADERFUNCTION, on_header) == CURLE_OK && curl_easy_setopt(easy, CURLOPT_HEADERDATA, transfer) == CURLE_OK &&
              curl_easy_setopt(easy, CURLOPT_PROTOCOLS_STR, "http,https") == CURLE_OK &&
              curl_easy_setopt(easy, CURLOPT_REDIR_PROTOCOLS_STR, "http,https") == CURLE_OK &&
              curl_easy_setopt(easy, CURLOPT_FOLLOWLOCATION, 0L) == CURLE_OK /* the caller follows redirects */ &&
              curl_easy_setopt(easy, CURLOPT_MAXREDIRS, client->max_redirects) == CURLE_OK &&
              curl_easy_setopt(easy, CURLOPT_TIMEOUT_MS, milliseconds) == CURLE_OK && curl_easy_setopt(easy, CURLOPT_USERAGENT, "manuscript") == CURLE_OK &&
              curl_easy_setopt(easy, CURLOPT_PATH_AS_IS, 1L) == CURLE_OK && /* the server sees the path as written */
              curl_easy_setopt(easy, CURLOPT_PROXY, "") == CURLE_OK; /* a proxy would resolve names itself and bypass the address filter */
    /* TCP sockets are opened by on_open_socket so the filter sees the address; a Unix socket has none to judge. */
    ok = ok && (client->unix_socket != NULL ? curl_easy_setopt(easy, CURLOPT_UNIX_SOCKET_PATH, client->unix_socket) == CURLE_OK
                                            : curl_easy_setopt(easy, CURLOPT_OPENSOCKETFUNCTION, on_open_socket) == CURLE_OK &&
                                                  curl_easy_setopt(easy, CURLOPT_OPENSOCKETDATA, transfer) == CURLE_OK);
    ok = ok && (transfer->resolve == NULL || curl_easy_setopt(easy, CURLOPT_RESOLVE, transfer->resolve) == CURLE_OK);
    ok = ok && (!client->decompress || curl_easy_setopt(easy, CURLOPT_ACCEPT_ENCODING, "") == CURLE_OK);
    ok = ok && (!client->cookies || curl_easy_setopt(easy, CURLOPT_COOKIEFILE, "") == CURLE_OK);
    ok = ok && (client->roots_length == 0 || curl_easy_setopt(easy, CURLOPT_CAINFO_BLOB, &roots) == CURLE_OK);
    ok = ok && (client->certificate_length == 0 || (curl_easy_setopt(easy, CURLOPT_SSLCERT_BLOB, &certificate) == CURLE_OK &&
                                                     curl_easy_setopt(easy, CURLOPT_SSLKEY_BLOB, &key) == CURLE_OK));
    return ok && set_method(easy, request, custom) &&
           (transfer->fields == NULL || curl_easy_setopt(easy, CURLOPT_HTTPHEADER, transfer->fields) == CURLE_OK);
}

/* Waits until `ready` holds. The caller holds the lock on entry and on return. */
static MsNetStatus wait_ready(MsCurlTransfer *transfer, bool (*ready)(const MsCurlTransfer *), int64_t deadline_ns) {
    while (!ready(transfer)) {
        const uint64_t token = msrt_token_new(1);
        transfer->waiter = token;
        uv_mutex_unlock(&driver.lock);
        const int64_t left = deadline_ns < 0 ? -1 : deadline_ns - ms_sys_monotonic_ns();
        uint64_t value = 0;
        const uint32_t woken = left == 0 || (deadline_ns >= 0 && left < 0) ? MS_WAIT_TIMEOUT : msrt_token_park(token, left, &value);
        uv_mutex_lock(&driver.lock);
        if (transfer->waiter == token) {
            transfer->waiter = 0;
        }
        msrt_token_free(token);
        if (woken == MS_WAIT_CANCELLED) {
            return MS_NET_CANCELLED;
        }
        if (woken == MS_WAIT_TIMEOUT && !ready(transfer)) {
            return MS_NET_TIMEOUT;
        }
    }
    return MS_NET_OK;
}

static bool head_ready(const MsCurlTransfer *transfer) { return transfer->head_ready; }

static MsNetStatus result_status(const MsCurlTransfer *transfer) {
    if (transfer->closed) {
        return MS_NET_CLOSED;
    }
    if (transfer->result == CURLE_OK) {
        return MS_NET_OK;
    }
    return transfer->result == CURLE_OPERATION_TIMEDOUT ? MS_NET_TIMEOUT : MS_NET_FAILED;
}

static void remember_message(const MsCurlTransfer *transfer) {
    const char *text = transfer->error[0] != 0 ? transfer->error : curl_easy_strerror(transfer->result);
    snprintf(last_message, sizeof last_message, "%s", text);
}

MsNetStatus ms_curl_start(MsCurlClient *client, const MsCurlRequest *request, int64_t deadline_ns, MsCurlTransfer **out, MsCurlFault *fault,
                          const char **message) {
    *fault = MS_CURL_FAULT_NONE;
    *message = "";
    char *url = terminated(request->url), *custom = NULL;
    bool parsed = false;
    if (client->unix_socket != NULL && ms_net_filter_restricted(client->filter)) {
        free(url);
        *fault = MS_CURL_FAULT_DENIED;
        return MS_NET_FAILED;
    }
    if (url == NULL || !ms_h1_is_token(request->method) || !url_allowed(client, url, &parsed)) {
        *fault = parsed ? MS_CURL_FAULT_DENIED : MS_CURL_FAULT_BAD_REQUEST;
        free(url);
        return MS_NET_FAILED;
    }
    MsCurlTransfer *transfer = calloc(1, sizeof *transfer);
    if (transfer == NULL || !driver_ensure()) {
        free(url);
        free(transfer);
        return MS_NET_FAILED;
    }
    atomic_store(&client->started, true);
    ms_curl_client_retain(client);
    transfer->client = client;
    transfer->buffer = malloc(BUFFER_BYTES);
    transfer->easy = curl_easy_init();
    transfer->fields = request_fields(request);
    if (request->resolve.len > 0) {
        char *entry = terminated(request->resolve);
        transfer->resolve = entry == NULL ? NULL : curl_slist_append(NULL, entry);
        free(entry);
    }
    const bool ready = transfer->buffer != NULL && transfer->easy != NULL && (request->nfields == 0 || transfer->fields != NULL) &&
                       (request->resolve.len == 0 || transfer->resolve != NULL);
    const bool configured = ready && configure(transfer, request, url, deadline_ns, &custom);
    free(url);
    free(custom); /* curl copies the strings it is given */
    if (!configured) {
        destroy_transfer(transfer);
        *fault = ready ? MS_CURL_FAULT_BAD_REQUEST : MS_CURL_FAULT_NONE;
        return MS_NET_FAILED;
    }
    uv_mutex_lock(&driver.lock);
    if (client->closed) {
        uv_mutex_unlock(&driver.lock);
        destroy_transfer(transfer);
        return MS_NET_CLOSED;
    }
    transfer->live_next = client->live;
    transfer->live_prev = &client->live;
    if (client->live != NULL) {
        client->live->live_prev = &transfer->live_next;
    }
    client->live = transfer;
    post_work(transfer, WORK_ADD);
    MsNetStatus status = wait_ready(transfer, head_ready, deadline_ns);
    if (status == MS_NET_OK && transfer->done && (transfer->closed || (transfer->result != CURLE_OK && (transfer->head.status == 0 || transfer->fault != MS_CURL_FAULT_NONE)))) {
        status = result_status(transfer);
        *fault = transfer->fault;
        remember_message(transfer);
        *message = last_message;
    }
    uv_mutex_unlock(&driver.lock);
    if (status != MS_NET_OK) {
        ms_curl_close(transfer);
        return status;
    }
    *out = transfer;
    return MS_NET_OK;
}

MsCurlHead ms_curl_head(const MsCurlTransfer *transfer) { return transfer->head; }

MsCurlFault ms_curl_fault(const MsCurlTransfer *transfer) { return transfer->fault; }

const char *ms_curl_message(const MsCurlTransfer *transfer) {
    remember_message(transfer);
    return last_message;
}

static bool readable(const MsCurlTransfer *transfer) { return transfer->length > 0 || transfer->done; }

MsNetStatus ms_curl_read(MsCurlTransfer *transfer, MsBytesMut out, int64_t deadline_ns, size_t *n) {
    *n = 0;
    uv_mutex_lock(&driver.lock);
    MsNetStatus status = wait_ready(transfer, readable, deadline_ns);
    if (status == MS_NET_OK && transfer->length > 0) {
        size_t take = transfer->length < out.len ? transfer->length : out.len;
        const size_t first = BUFFER_BYTES - transfer->start < take ? BUFFER_BYTES - transfer->start : take;
        memcpy(out.ptr, transfer->buffer + transfer->start, first);
        memcpy(out.ptr + first, transfer->buffer, take - first);
        transfer->start = (transfer->start + take) % BUFFER_BYTES;
        transfer->length -= take;
        *n = take;
        if (transfer->paused && transfer->length <= BUFFER_BYTES / 2) {
            transfer->paused = false;
            post_work(transfer, WORK_UNPAUSE);
        }
    } else if (status == MS_NET_OK) {
        status = result_status(transfer); /* drained and done: the end, or why it failed */
    }
    uv_mutex_unlock(&driver.lock);
    return status;
}

void ms_curl_close(MsCurlTransfer *transfer) {
    uv_mutex_lock(&driver.lock);
    post_work(transfer, WORK_REMOVE);
    uv_mutex_unlock(&driver.lock);
}
