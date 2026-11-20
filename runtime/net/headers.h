/* The header table the standard library holds (HeadersH): an ordered multimap with ASCII case-insensitive names.
 * Values with one name stay together, in the order added, and names keep the spelling of their first use. Values are
 * bytes. The natives of ms_rt/net.h (`msstd_headers_*`) are built on these calls, and so are the exchange natives,
 * which read the request fields from one and fill another with a response's.
 */
#ifndef MS_NET_HEADERS_H
#define MS_NET_HEADERS_H

#include <stdbool.h>
#include <stddef.h>

#include "ms_rt/base.h"
#include "ms_rt/safe.h"

typedef struct MsHeaders MsHeaders;

enum { MS_HEADERS_MAX_FIELDS = 1024, MS_HEADERS_MAX_BYTES = 1 << 20 };

/* An empty table, a heap object the runtime drops; NULL when out of memory. */
MsHeaders *ms_headers_new(void);
/* The table behind a handle the runtime passes to a native. */
MsHeaders *ms_headers_of(const void *handle);
static inline MsObj *ms_headers_object(MsHeaders *table) { return (MsObj *)table; }

/* Adds `value` under `name`, after the values already there. False when the table is full (MS_HEADERS_MAX_FIELDS
 * fields or MS_HEADERS_MAX_BYTES of text) or out of memory; nothing changes then. The name is not checked here. */
MS_NODISCARD bool ms_headers_add(MsHeaders *table, MsBytes name, MsBytes value);
/* Like add, with `name` in canonical form (Content-Type): how a received field is stored, whichever way the
 * protocol spelled it. */
MS_NODISCARD bool ms_headers_add_canonical(MsHeaders *table, MsBytes name, MsBytes value);

/* The fields in table order: names grouped, first use first. `i` below ms_headers_count. */
size_t ms_headers_count(const MsHeaders *table);
void ms_headers_field(const MsHeaders *table, size_t i, MsBytes *name, MsBytes *value);

#endif
