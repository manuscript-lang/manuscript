/* compiler/project/toml.h: the subset of TOML that ms.toml uses: `[table]` headers and `key = value` lines
 * whose values are strings. Any other value is kept as raw text so the manifest can name its key in the
 * error. Arrays, inline tables, dotted keys, multi-line strings and array tables are not parsed yet. */
#ifndef MS_PROJECT_TOML_H
#define MS_PROJECT_TOML_H

#include "base/arena.h"
#include "base/list.h"
#include "compiler/syntax/pos.h"

typedef struct TomlTable {
  MsSpan name;
  MsPos at; /* the `[` of the header */
} TomlTable;

typedef struct TomlEntry {
  int32_t table; /* index in the document's tables, or -1 before the first header */
  MsSpan key;
  MsSpan text;    /* the string value decoded, or the raw text of any other value */
  bool is_string; /* the value is a string */
  MsPos key_at, value_at;
} TomlEntry;

MS_LIST_DEFINE(TomlTableList, toml_table_list, TomlTable)
MS_LIST_DEFINE(TomlEntryList, toml_entry_list, TomlEntry)

typedef struct TomlDocument {
  TomlTableList tables; /* in document order */
  TomlEntryList entries; /* in document order */
} TomlDocument;

/* Parses `text` (after any byte-order mark; `bom` bytes were skipped, so positions add them back). On a syntax
 * error returns false with the position and message ("invalid ms.toml: ..."). Texts live in `arena`. */
MS_NODISCARD bool toml_parse(MsArena *arena, MsSpan text, size_t bom, TomlDocument *out, MsPos *error_at,
                             MsSpan *error_text);

void toml_free(TomlDocument *document);

#endif
