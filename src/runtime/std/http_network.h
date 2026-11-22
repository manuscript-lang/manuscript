/* runtime/std/http_network.h: the HTTP client natives of a Network (http_network.c): clients and one-shot
 * requests that obey the network's restrictions and close with it. */
#ifndef MS_RUNTIME_STD_HTTP_NETWORK_H
#define MS_RUNTIME_STD_HTTP_NETWORK_H

#include "abi/status.h"
#include "base/bytes.h"
#include "base/list.h"
#include "base/string.h"
#include "runtime/std/http_client_abi.h"

/* HttpClientOptions with each Int? as a presence byte and a naturally aligned value, and `tls` inline. */
typedef struct MsHttpClientOptionsWire {
  uint8_t max_redirects_present;
  int64_t max_redirects;
  uint8_t max_idle_present;
  int64_t max_idle_connections;
  uint8_t max_header_present;
  int64_t max_header_bytes;
  uint8_t idle_timeout_present;
  int64_t idle_timeout;
  uint8_t decompress;
  uint8_t cookies;
  MsString tls_server_name;
  MsString tls_roots_pem;
  MsString tls_certificate_pem;
  MsString tls_private_key_pem;
  MsList tls_alpn;
  uint8_t tls_require_client_certificate;
} MsHttpClientOptionsWire;

/* ClientResponse flattened. */
typedef struct MsClientResponseWire {
  int64_t status;
  MsObj *headers;
  MsString protocol;
  MsBytes body;
} MsClientResponseWire;

/* ms-sig: msstd_net_network_http_client(handle net: *const ObjCell<NetH>, opts: *const HttpClientOptionsWire,
 * out: *mut *mut ObjCell<ClientH>, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_net_network_http_client(const MsObj *net, const MsHttpClientOptionsWire *options, MsObj **out,
                                      MsString *err);
/* ms-sig: msstd_net_network_request_bytes(handle net: *const ObjCell<NetH>, method: *const StrVal, address:
 * *const StrVal, handle headers: *const ObjCell<HeadersH>, body: *const VecVal, has_max: HasRaw, max: i64,
 * has_timeout: HasRaw, timeout: i64, out: *mut ClientResponseWire, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_net_network_request_bytes(const MsObj *net, const MsString *method, const MsString *address,
                                        const MsObj *headers, const MsBytes *body, uint8_t has_max,
                                        int64_t max, uint8_t has_timeout, int64_t timeout,
                                        MsClientResponseWire *out, MsString *err);

#endif
