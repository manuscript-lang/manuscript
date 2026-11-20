/* The HTTP client engine on libcurl. One driver thread runs every transfer of the process through a single multi
 * handle (curl_multi_poll), so a request costs a transfer and its buffers, not a thread (a cold DNS lookup uses curl's resolver thread). A client holds what is
 * shared by its requests: the connection pool (an HTTP/2 connection carries many requests), cookies, TLS roots and
 * the network filter. A task starts a transfer and parks until the response head arrives; the body is read from a
 * bounded buffer the driver fills, and the transfer is paused while it is full.
 *
 * What curl does, so the standard library does not: redirects (the Location host is checked against the filter before
 * the next hop connects), cookies, content-encoding, HTTP/1.1 or HTTP/2 by ALPN, proxies from the environment, IPv6
 * fallback. Which hosts a client may reach is the filter (net_filter.h): the URL host, every redirect target host and
 * every address curl is about to connect to.
 */
#ifndef MS_NET_CURL_CLIENT_H
#define MS_NET_CURL_CLIENT_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "conn_io.h"
#include "http1.h"
#include "ms_rt/safe.h"

typedef struct MsCurlClient MsCurlClient;
typedef struct MsCurlTransfer MsCurlTransfer;

typedef struct MsCurlClientOptions {
    MsBytes roots_pem;         /* extra trusted roots; empty for the system's */
    MsBytes certificate_pem;   /* a client certificate and its key, or empty */
    MsBytes private_key_pem;
    MsBytes unix_socket;       /* a Unix domain socket every connection uses instead of TCP, or empty; refused (DENIED) once the
                                  filter is narrowed, since the filter cannot judge a path */
    MsBytes resolver;          /* "ip:port" of the DNS server the caller resolves names with, or empty for the system's; the
                                  caller passes each request's addresses in `resolve`, and a redirect may only stay on the
                                  request's host, since the engine cannot resolve another */
    int64_t max_redirects;     /* 0 follows none; negative takes 20 */
    bool cookies;              /* keep cookies for this client's requests */
    bool decompress;           /* ask for gzip and deflate and decode them */
} MsCurlClientOptions;

/* A client with one reference; NULL when out of memory. Each holder of a transfer keeps its own reference. */
MsCurlClient *ms_curl_client_new(const MsCurlClientOptions *options);
void ms_curl_client_retain(MsCurlClient *client);
void ms_curl_client_release(MsCurlClient *client);
/* Narrows the client's filter (net_filter.h); false, changing nothing, for an invalid CIDR. Only before the first
 * request: the driver reads the filter without a lock, so the caller checks ms_curl_client_started first. */
bool ms_curl_client_started(const MsCurlClient *client);
/* Ends every transfer of the client (their reads and a request waiting for its head return MS_NET_CLOSED) and refuses
 * later requests with MS_NET_CLOSED. Idempotent; the client's references are released as usual. */
void ms_curl_client_close(MsCurlClient *client);
bool ms_curl_client_narrow(MsCurlClient *client, const MsBytes *hosts, size_t host_count, const MsBytes *cidrs, size_t cidr_count);

typedef struct MsCurlRequest {
    MsBytes method;
    MsBytes url;
    MsBytes head;               /* the bytes `fields` points into */
    const MsH1Field *fields;
    uint32_t nfields;
    MsBytes body;
    MsBytes resolve;            /* "host:port:address[,address]" for curl's resolve list, or empty to let curl resolve */
} MsCurlRequest;

/* The resolver text the client was made with, NUL-terminated, or NULL. */
const char *ms_curl_client_resolver(const MsCurlClient *client);
/* The most redirects the client follows. */
long ms_curl_client_max_redirects(const MsCurlClient *client);
/* `reference` resolved against `base` as a URL, in memory from malloc (*out); false when either does not parse. */
bool ms_curl_url_resolve(MsBytes base, MsBytes reference, char **out);
/* The host (without brackets) and port of an http or https URL; false when it cannot be parsed. */
bool ms_curl_url_target(MsBytes url, char *host, size_t capacity, uint16_t *port);

/* Why a transfer ended badly, beyond its MsNetStatus. */
typedef enum MsCurlFault { MS_CURL_FAULT_NONE = 0, MS_CURL_FAULT_DENIED, MS_CURL_FAULT_BAD_REQUEST } MsCurlFault;

/* Starts the request and waits for the response head. On MS_NET_OK `*out` is the transfer; otherwise nothing is
 * allocated and `*fault` and `*message` (a static or thread-local text) say more. deadline_ns is absolute monotonic
 * time, negative for none; it covers the whole exchange, body included. */
MS_NODISCARD MsNetStatus ms_curl_start(MsCurlClient *client, const MsCurlRequest *request, int64_t deadline_ns, MsCurlTransfer **out,
                                       MsCurlFault *fault, const char **message);

typedef struct MsCurlHead {
    int status;
    const char *protocol;   /* "HTTP/1.1", "HTTP/2.0", ... */
    MsBytes lines;          /* the final response's header lines, "Name: value\r\n" each, without the status line */
} MsCurlHead;
/* The head, valid until the transfer is closed. */
MsCurlHead ms_curl_head(const MsCurlTransfer *transfer);

/* Reads up to out.len body bytes; *n is 0 at the end of the body. A failed transfer is MS_NET_FAILED (text in
 * ms_curl_message), a deadline MS_NET_TIMEOUT. */
MS_NODISCARD MsNetStatus ms_curl_read(MsCurlTransfer *transfer, MsBytesMut out, int64_t deadline_ns, size_t *n);
const char *ms_curl_message(const MsCurlTransfer *transfer);
MsCurlFault ms_curl_fault(const MsCurlTransfer *transfer);

/* Ends the transfer: an unfinished one is aborted and its connection dropped, a finished one returns its connection to
 * the client's pool. Releases the transfer's reference on the client. */
void ms_curl_close(MsCurlTransfer *transfer);

/* Stops the driver thread and frees libcurl's global state; the next transfer starts it again. For tests and exit. */
void ms_curl_shutdown(void);

#endif
