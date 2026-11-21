/* runtime/std/http_abi.c: the HttpHeaders natives. A handle is borrowed and mutated in place (the type has
 * one owner, so no other reference sees the write). */
#include "runtime/std/http.h"

#include "base/alloc.h"

static MsHeaders *mutable_of(const MsObj *object) {
  return (MsHeaders *)(void *)(uintptr_t)object;
}

MsObj *msstd_http_headers_new(void) {
  return ms_headers_object(ms_headers_new());
}

uint8_t msstd_http_headers_append(const MsObj *h, const MsString *name, const MsBytes *value) {
  return ms_headers_append(mutable_of(h), ms_string_span(name), ms_bytes_span(value));
}

uint8_t msstd_http_headers_values(const MsObj *h, const MsString *name, MsList *out) {
  return ms_headers_values(ms_headers_of(h), ms_string_span(name), out);
}

void msstd_http_headers_names(const MsObj *h, MsList *out) {
  const MsHeaders *headers = ms_headers_of(h);
  *out = (MsList){0};
  for (size_t i = 0; i < ms_headers_group_count(headers); i++) {
    const MsString name = ms_string_from_span(ms_headers_group_name(headers, i));
    ms_list_push(out, sizeof name, &name);
  }
}

uint8_t msstd_http_headers_remove(const MsObj *h, const MsString *name) {
  return ms_headers_remove(mutable_of(h), ms_string_span(name));
}

MsObj *msstd_http_headers_clone(const MsObj *h) {
  return ms_headers_object(ms_headers_copy(ms_headers_of(h)));
}
