/* runtime/std/url.h: the @std/net/url natives (src/runtime/std/url*.c), URLs as Go's net/url reads them. A
 * `Url` and a `QueryEntry` are records at their natural layout, fields in declaration order. Strings in a
 * record the natives write are owned by the record. Fallible natives return a status (0 ok, 1 InvalidInput, 3
 * LimitExceeded, 4 InvalidData) and write their result only on success. */
#ifndef MS_RUNTIME_STD_URL_H
#define MS_RUNTIME_STD_URL_H

#include "abi/status.h"
#include "base/bytes.h"
#include "base/string.h"

/* `Int?` inside a record: a presence byte, then the value. */
typedef struct MsUrlPort {
  uint8_t present;
  int64_t value;
} MsUrlPort;

/* `Url`: `scheme, host, path, fragment, query: String?, port: Int?, omit_host`. A `String?` is the string
 * itself; none is the static string with a null pointer, which no present string has. */
typedef struct MsUrl {
  MsString scheme;
  MsString host;
  MsString path;
  MsString fragment;
  MsString query;
  MsUrlPort port;
  uint8_t omit_host;
} MsUrl;

/* `QueryEntry`: `key, value`. */
typedef struct MsQueryEntry {
  MsString key;
  MsString value;
} MsQueryEntry;

/* ms-sig: msstd_url_encode_component(text: *const StrVal, out: *mut StrVal) @domain=URL @leaf */
void msstd_url_encode_component(const MsString *text, MsString *out);
/* ms-sig: msstd_url_decode_component(text: *const StrVal, out: *mut StrVal) -> u8 @domain=URL @leaf */
uint8_t msstd_url_decode_component(const MsString *text, MsString *out);
/* ms-sig: msstd_url_parse(text: *const StrVal, out: *mut UrlType) -> u8 @domain=URL @leaf */
uint8_t msstd_url_parse(const MsString *text, MsUrl *out);
/* ms-sig: msstd_url_resolve(base: *const UrlType, reference: *const StrVal, out: *mut UrlType) -> u8
 * @domain=URL @leaf */
uint8_t msstd_url_resolve(const MsUrl *base, const MsString *reference, MsUrl *out);
/* ms-sig: msstd_url_format(value: *const UrlType, out: *mut StrVal) -> u8 @domain=URL @leaf */
uint8_t msstd_url_format(const MsUrl *value, MsString *out);
/* ms-sig: msstd_url_parse_query(text: *const StrVal, has_max: u8, max: i64, out: *mut VecVal) -> u8
 * @domain=URL @leaf */
uint8_t msstd_url_parse_query(const MsString *text, uint8_t has_max, int64_t max, MsBytes *out);
/* ms-sig: msstd_url_format_query(entries: *const VecVal, out: *mut StrVal) @domain=URL @leaf */
void msstd_url_format_query(const MsBytes *entries, MsString *out);

#endif
