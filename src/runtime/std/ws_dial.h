/* runtime/std/ws_dial.h: Network.web_socket, the client opening handshake (ws_dial.c). */
#ifndef MS_RUNTIME_STD_WS_DIAL_H
#define MS_RUNTIME_STD_WS_DIAL_H

#include "abi/status.h"
#include "base/list.h"
#include "base/string.h"
#include "runtime/std/http_headers.h"

/* WebSocketWire: the TLS options inline, then the settings; each Int? is a presence byte and a naturally
 * aligned value. */
typedef struct MsWebSocketOptionsWire {
  MsString tls_server_name;
  MsString tls_roots_pem;
  MsString tls_certificate_pem;
  MsString tls_private_key_pem;
  MsList tls_alpn;
  uint8_t tls_require_client_certificate;
  uint8_t compression;
  uint8_t max_message_bytes_present;
  int64_t max_message_bytes;
  uint8_t timeout_present;
  int64_t timeout;
} MsWebSocketOptionsWire;

/* The head of an HTTP response in `buf`: PARTIAL until its blank line, BAD when malformed; on COMPLETE the
 * status, the fields (owned) and the bytes the head took. */
typedef enum MsResponseHead { MS_RESPONSE_PARTIAL, MS_RESPONSE_COMPLETE, MS_RESPONSE_BAD } MsResponseHead;

/* ms-sig: msstd_net_network_web_socket(handle net: *const ObjCell<NetH>, address: *const StrVal, handle
 * headers: *const ObjCell<HeadersH>, subprotocols: *const VecVal, opts: *const WebSocketOptionsWire, out:
 * *mut *mut ObjCell<SocketH>, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_net_network_web_socket(const MsObj *net, const MsString *address, const MsObj *headers,
                                     const MsList *subprotocols, const MsWebSocketOptionsWire *options,
                                     MsObj **out, MsString *err);

#endif
