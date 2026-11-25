/* tooling/json_value.h: a JSON document read into a tree and written back in the CLI's pretty layout. `ms verify`
 * runs each step as a child process and embeds its `--json` result in its own document. Every node lives in the
 * arena. */
#ifndef MS_CLI_JSON_VALUE_H
#define MS_CLI_JSON_VALUE_H

#include "base/arena.h"
#include "base/strbuild.h"

typedef enum MsJsonKind { MS_JSON_NULL, MS_JSON_BOOL, MS_JSON_NUMBER, MS_JSON_STRING, MS_JSON_ARRAY, MS_JSON_OBJECT } MsJsonKind;

typedef struct MsJson MsJson;
struct MsJson {
  MsJsonKind kind;
  MsSpan text;     /* string: decoded; number: as written; bool: "true" or "false" */
  MsSpan *keys;    /* object: one per member */
  MsJson **items;  /* array elements, or object values */
  size_t count;
};

/* Reads one document (surrounding white space is allowed). NULL when `text` is not JSON. */
MsJson *ms_json_parse(MsArena *arena, MsSpan text);

/* The member `key` of an object, or NULL. */
const MsJson *ms_json_member(const MsJson *object, const char *key);

/* Appends the value at `depth` levels, two spaces each a pretty document. */
void ms_json_write(MsStrBuild *out, const MsJson *value, size_t depth);

#endif
