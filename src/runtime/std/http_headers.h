/* runtime/std/http_headers.h: HttpHeaders, an ordered multimap of names to byte values (http_headers.c), and
 * the field text rules. Names fold ASCII case and keep the spelling of their first use; a name's values
 * keep append order. Built headers list names in order of first use; headers made from received fields
 * (ms_headers_from_received) have canonical names sorted bytewise. One owner: copying is explicit. */
#ifndef MS_RUNTIME_STD_HTTP_HEADERS_H
#define MS_RUNTIME_STD_HTTP_HEADERS_H

#include "abi/status.h"
#include "base/bytes.h"
#include "base/desc.h"
#include "base/strbuild.h"

typedef struct MsHeaders MsHeaders;

/* RFC 9110 token bytes; a name must be a non-empty token. */
bool ms_header_valid_name(MsSpan name);
/* Outgoing values are UTF-8 with no control byte besides tab, and no DEL. */
bool ms_header_valid_value(MsSpan value);
/* Go's CanonicalMIMEHeaderKey: `content-TYPE` to `Content-Type`; a name that is not a token is unchanged. */
void ms_header_canonical(MsSpan name, MsStrBuild *out);

MsHeaders *ms_headers_new(void);
MsHeaders *ms_headers_copy(const MsHeaders *headers);
void ms_headers_free(MsHeaders *headers);
/* Handle objects over the header (the header is the first member): clone is null, drop frees. */
MsObj *ms_headers_object(MsHeaders *headers);
const MsHeaders *ms_headers_of(const MsObj *object);

/* Adds a value; the name must be a token (MS_STATUS_INVALID_INPUT otherwise). */
uint8_t ms_headers_append(MsHeaders *headers, MsSpan name, MsSpan value);
/* Adds a value without checking the name. */
void ms_headers_add(MsHeaders *headers, MsSpan name, MsSpan value);
/* Replaces every value of `name` with one, adding the name when absent. */
void ms_headers_set(MsHeaders *headers, MsSpan name, MsSpan value);
bool ms_headers_remove(MsHeaders *headers, MsSpan name);
bool ms_headers_is_empty(const MsHeaders *headers);

/* The first value of `name`; false when there is none. */
bool ms_headers_first(const MsHeaders *headers, MsSpan name, MsSpan *out);
/* Every value of `name` in order; false (and *out untouched) when the name is absent. */
bool ms_headers_values(const MsHeaders *headers, MsSpan name, MsList *out /* owned MsBytes elements */);
/* The values of `name` as text: false when absent; MS_STATUS_INVALID_DATA, with nothing in *out, when one is
 * not UTF-8. */
uint8_t ms_headers_text(const MsHeaders *headers, MsSpan name, bool *found, MsList *out /* MsString */);
/* Frees a list of MsBytes elements or of MsString elements. */
void ms_bytes_list_free(MsList *list);

/* Groups in order: one per name. */
size_t ms_headers_group_count(const MsHeaders *headers);
MsSpan ms_headers_group_name(const MsHeaders *headers, size_t group);
size_t ms_headers_group_size(const MsHeaders *headers, size_t group);
MsSpan ms_headers_group_value(const MsHeaders *headers, size_t group, size_t index);

/* Received fields as a handler sees them: canonical names, sorted, values in arrival order. */
typedef struct MsHeaderField {
  MsSpan name;
  MsSpan value;
} MsHeaderField;
MsHeaders *ms_headers_from_received(const MsHeaderField *fields, size_t count);
/* Orders the groups by case-folded name (stable). */
void ms_headers_sort(MsHeaders *headers);
/* Whether every value is UTF-8. */
bool ms_headers_is_text(const MsHeaders *headers);

#endif
