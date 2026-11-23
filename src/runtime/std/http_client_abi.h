/* runtime/std/http_client_abi.h: the HttpClient and response-body natives of @std/net/http over
 * http_client.h. A task that sends or reads parks on a token the engine thread posts, so the scheduler keeps
 * running. */
#ifndef MS_RUNTIME_STD_HTTP_CLIENT_ABI_H
#define MS_RUNTIME_STD_HTTP_CLIENT_ABI_H

#include "abi/status.h"
#include "base/bytes.h"
#include "base/string.h"
#include "runtime/std/http_client.h"

/* A response's head as the program sees it. */
typedef struct MsHttpMetadataOut {
  int64_t status;
  MsObj *headers;
  MsString protocol;
} MsHttpMetadataOut;

/* What a network lets its clients reach: the hosts and addresses allowed, and the owner's reference. */
typedef struct MsHttpPolicy {
  bool (*host_allowed)(void *context, MsSpan host);
  bool (*address_allowed)(void *context, const void *address);
  void *context;
  void *(*retain)(void *context);
  void (*release)(void *context);
} MsHttpPolicy;

/* A handle on `client` (retained); the handle's drop releases it, it never closes the client. The policy, if
 * any, is applied to every request sent through this handle or one shared from it. */
MsObj *ms_http_client_handle(MsHttpClient *client);
MsObj *ms_http_client_handle_with_policy(MsHttpClient *client, const MsHttpPolicy *policy);
/* Sends `request` through the handle's client under the handle's policy (see ms_http_client_send). */
MS_NODISCARD uint8_t ms_http_handle_send(const MsObj *handle, const MsHttpRequest *request,
                                         MsHttpResponse **out, MsString *err);
/* Whether the client behind the handle ended, or this handle is the last that names it. */
bool ms_http_client_handle_closed(const MsObj *handle);

/* Makes http_client.h wait through scheduler tokens. Once per process, before any task runs. */
void ms_http_install_task_waiter(void);
/* Ends the engine thread and frees its loop, for a process that ends with balanced books (MS_FREE_AT_EXIT); a no-op
 * when no request ever ran. */
void ms_http_engine_release_all(void);

/* ms-sig: msstd_http_client_close(handle c: *const ObjCell<ClientH>) @domain=HTTP */
void msstd_http_client_close(const MsObj *c);
/* ms-sig: msstd_http_client_share(handle c: *const ObjCell<ClientH>) -> *mut ObjCell<ClientH>
 * @domain=HTTP @end */
MsObj *msstd_http_client_share(const MsObj *c);
/* ms-sig: msstd_http_client_request_bytes(handle c: *const ObjCell<ClientH>, method: *const StrVal, address:
 * *const StrVal, handle headers: *const ObjCell<HeadersH>, body: *const VecVal, has_max: HasRaw, max: i64,
 * has_timeout: HasRaw, timeout: i64, out: *mut *mut ObjCell<BodyH>, err: ErrSlot) -> u8 @domain=HTTP */
uint8_t msstd_http_client_request_bytes(const MsObj *c, const MsString *method, const MsString *address,
                                        const MsObj *headers, const MsBytes *body, uint8_t has_max,
                                        int64_t max, uint8_t has_timeout, int64_t timeout, MsObj **out,
                                        MsString *err);

/* ms-sig: msstd_http_body_close(handle b: *const ObjCell<BodyH>) @domain=HTTP */
void msstd_http_body_close(const MsObj *b);
/* ms-sig: msstd_http_body_metadata(handle b: *const ObjCell<BodyH>, out: *mut MetadataWire) @domain=HTTP */
void msstd_http_body_metadata(const MsObj *b, MsHttpMetadataOut *out);
/* The end of the body is MS_STATUS_NONE. */
/* ms-sig: msstd_http_body_read(handle b: *const ObjCell<BodyH>, has_max: HasRaw, max: i64, out: *mut VecVal,
 * err: ErrSlot) -> u8 @domain=HTTP */
uint8_t msstd_http_body_read(const MsObj *b, uint8_t has_max, int64_t max, MsBytes *out, MsString *err);
/* ms-sig: msstd_http_body_read_all(handle b: *const ObjCell<BodyH>, out: *mut VecVal, err: ErrSlot) -> u8
 * @domain=HTTP */
uint8_t msstd_http_body_read_all(const MsObj *b, MsBytes *out, MsString *err);

#endif
