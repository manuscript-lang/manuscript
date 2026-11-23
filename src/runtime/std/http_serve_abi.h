/* runtime/std/http_serve_abi.h: the natives of the server half of @std/net/http.ms: `serve`'s serving, its
 * workers and the exchange a handler receives (http_serve_abi.c). The handler is a closure over `fn(var
 * NativeExchange) Void!`; the runtime calls it with the exchange handle and never builds an Error itself. */
#ifndef MS_RUNTIME_STD_HTTP_SERVE_ABI_H
#define MS_RUNTIME_STD_HTTP_SERVE_ABI_H

#include "base/bytes.h"
#include "base/list.h"
#include "runtime/std/http_headers.h"
#include "runtime/std/http_serve.h"

/* HttpServerOptions as the compiler lays it out: each Int? is a presence byte and a naturally aligned value,
 * the TlsOptions? is a presence byte then its leaves inline, and `cores` (read by `serve` itself) follows. */
typedef struct MsOptionalInt {
  uint8_t present;
  int64_t value;
} MsOptionalInt;

typedef struct MsHttpServerOptionsWire {
  MsOptionalInt max_requests;
  MsOptionalInt max_body_bytes;
  MsOptionalInt max_response_bytes;
  MsOptionalInt max_header_bytes;
  MsOptionalInt timeout;
  MsOptionalInt grace;
  uint8_t tls_present;
  MsString tls_server_name;
  MsString tls_roots_pem;
  MsString tls_certificate_pem;
  MsString tls_private_key_pem;
  MsList tls_alpn;
  uint8_t tls_require_client_certificate;
  uint8_t cores_present;
  int64_t cores;
} MsHttpServerOptionsWire;

_Static_assert(offsetof(MsHttpServerOptionsWire, tls_present) == 96,
               "the compiler packs the leaves in order");
_Static_assert(offsetof(MsHttpServerOptionsWire, tls_server_name) == 104,
               "the compiler packs the leaves in order");
_Static_assert(offsetof(MsHttpServerOptionsWire, tls_require_client_certificate) == 192,
               "the compiler packs the leaves in order");

/* ms-sig: msstd_http_serving_new(address: *const StrVal, opts: *const HttpServerOptionsWire, handler: *mut
 * Closure, out: *mut *mut ObjCell<ServingH>, err: ErrSlot) -> u8 @domain=HTTP */
uint8_t msstd_http_serving_new(const MsString *address, const MsHttpServerOptionsWire *options,
                               MsObj *handler, MsObj **out, MsString *err);
/* ms-sig: msstd_http_serving_spec(handle s: *const ObjCell<ServingH>) -> *mut ObjCell<SpecH>
 * @domain=HTTP @end */
MsObj *msstd_http_serving_spec(const MsObj *serving);
/* ms-sig: msstd_http_serving_address(handle s: *const ObjCell<ServingH>, out: *mut StrVal) @domain=HTTP */
void msstd_http_serving_address(const MsObj *serving, MsString *out);
/* ms-sig: msstd_http_serving_accept(handle s: *const ObjCell<ServingH>, out: *mut i64, err: ErrSlot) -> u8
 * @domain=HTTP */
uint8_t msstd_http_serving_accept(const MsObj *serving, int64_t *out, MsString *err);
/* ms-sig: msstd_http_serving_worker(handle s: *const ObjCell<SpecH>, out: *mut *mut ObjCell<WorkerH>, err:
 * ErrSlot) -> u8 @domain=HTTP */
uint8_t msstd_http_serving_worker(const MsObj *spec, MsObj **out, MsString *err);
/* ms-sig: msstd_http_worker_adopt(handle w: *const ObjCell<WorkerH>, connection: i64) @domain=HTTP */
void msstd_http_worker_adopt(const MsObj *worker, int64_t connection);
/* ms-sig: msstd_http_worker_close(handle w: *const ObjCell<WorkerH>) @domain=HTTP */
void msstd_http_worker_close(const MsObj *worker);
/* ms-sig: msstd_http_serving_release(handle s: *const ObjCell<ServingH>) @domain=HTTP */
void msstd_http_serving_release(const MsObj *serving);

/* ms-sig: msstd_http_exchange_close(handle x: *const ObjCell<ExchH>) @domain=HTTP */
void msstd_http_exchange_close(const MsObj *exchange);
/* ms-sig: msstd_http_exchange_headers(handle x: *const ObjCell<ExchH>) -> *mut ObjCell<HeadersH>
 * @domain=HTTP @end */
MsObj *msstd_http_exchange_headers(const MsObj *exchange);
/* ms-sig: msstd_http_exchange_method(handle x: *const ObjCell<ExchH>, out: *mut StrVal) @domain=HTTP */
void msstd_http_exchange_method(const MsObj *exchange, MsString *out);
/* ms-sig: msstd_http_exchange_path(handle x: *const ObjCell<ExchH>, out: *mut StrVal) @domain=HTTP */
void msstd_http_exchange_path(const MsObj *exchange, MsString *out);
/* ms-sig: msstd_http_exchange_protocol(handle x: *const ObjCell<ExchH>, out: *mut StrVal) @domain=HTTP */
void msstd_http_exchange_protocol(const MsObj *exchange, MsString *out);
/* ms-sig: msstd_http_exchange_query(handle x: *const ObjCell<ExchH>, out: *mut StrVal) @domain=HTTP */
void msstd_http_exchange_query(const MsObj *exchange, MsString *out);
/* ms-sig: msstd_http_exchange_read(handle x: *const ObjCell<ExchH>, has_max: HasRaw, max: i64, out: *mut
 * VecVal, err: ErrSlot) -> u8 @domain=HTTP */
uint8_t msstd_http_exchange_read(const MsObj *exchange, uint8_t has_max, int64_t max, MsBytes *out,
                                 MsString *err);
/* ms-sig: msstd_http_exchange_send_headers(handle x: *const ObjCell<ExchH>, status: i64, handle headers:
 * *const ObjCell<HeadersH>, err: ErrSlot) -> u8 @domain=HTTP */
uint8_t msstd_http_exchange_send_headers(const MsObj *exchange, int64_t status, const MsObj *headers,
                                         MsString *err);
/* ms-sig: msstd_http_exchange_send(handle x: *const ObjCell<ExchH>, status: i64, handle headers: *const
 * ObjCell<HeadersH>, body: *const VecVal, err: ErrSlot) -> u8 @domain=HTTP */
uint8_t msstd_http_exchange_send(const MsObj *exchange, int64_t status, const MsObj *headers,
                                 const MsBytes *body, MsString *err);
/* ms-sig: msstd_http_exchange_write(handle x: *const ObjCell<ExchH>, data: *const StrVal, err: ErrSlot) -> u8
 * @domain=HTTP */
uint8_t msstd_http_exchange_write(const MsObj *exchange, const MsString *data, MsString *err);
/* ms-sig: msstd_http_exchange_write_bytes(handle x: *const ObjCell<ExchH>, data: *const VecVal, err: ErrSlot)
 * -> u8 @domain=HTTP */
uint8_t msstd_http_exchange_write_bytes(const MsObj *exchange, const MsBytes *data, MsString *err);

/* ms-sig: msstd_http_exchange_upgrade(handle x: *const ObjCell<ExchH>, origins: *const VecVal, subprotocols:
 * *const VecVal, has_max: HasRaw, max: i64, out: *mut *mut ObjCell<SocketH>, err: ErrSlot) -> u8 @domain=HTTP
 */
uint8_t msstd_http_exchange_upgrade(const MsObj *exchange, const MsList *origins, const MsList *subprotocols,
                                    uint8_t has_max, int64_t max, MsObj **out, MsString *err);

#endif
