/* runtime/std/http.h: the @std/net/http natives that need neither the scheduler nor the event loop: the
 * HttpHeaders object (http_abi.c over http_headers.c). */
#ifndef MS_RUNTIME_STD_HTTP_H
#define MS_RUNTIME_STD_HTTP_H

#include "abi/status.h"
#include "base/list.h"
#include "base/string.h"
#include "runtime/std/http_headers.h"

/* ms-sig: msstd_http_headers_new() -> *mut ObjCell<Headers> @handle @domain=HTTP @leaf */
MsObj *msstd_http_headers_new(void);
/* ms-sig: msstd_http_headers_append(handle h: *const ObjCell<Headers>, name: *const StrVal, value: *const
 * VecVal) -> u8 @domain=HTTP @leaf */
uint8_t msstd_http_headers_append(const MsObj *h, const MsString *name, const MsBytes *value);
/* 1 and the values (a list of Bytes) when the name exists, 0 otherwise. */
/* ms-sig: msstd_http_headers_values(handle h: *const ObjCell<Headers>, name: *const StrVal, out: *mut VecVal)
 * -> u8 @domain=HTTP @leaf */
uint8_t msstd_http_headers_values(const MsObj *h, const MsString *name, MsList *out);
/* ms-sig: msstd_http_headers_names(handle h: *const ObjCell<Headers>, out: *mut VecVal) @domain=HTTP @leaf */
void msstd_http_headers_names(const MsObj *h, MsList *out);
/* ms-sig: msstd_http_headers_remove(handle h: *const ObjCell<Headers>, name: *const StrVal) -> u8
 * @domain=HTTP
 * @leaf */
uint8_t msstd_http_headers_remove(const MsObj *h, const MsString *name);
/* ms-sig: msstd_http_headers_clone(handle h: *const ObjCell<Headers>) -> *mut ObjCell<Headers> @handle
 * @domain=HTTP @leaf */
MsObj *msstd_http_headers_clone(const MsObj *h);

#endif
