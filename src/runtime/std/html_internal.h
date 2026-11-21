/* What html.c shares with the generated entity table. */
#ifndef MS_RUNTIME_STD_HTML_INTERNAL_H
#define MS_RUNTIME_STD_HTML_INTERNAL_H

#include <stddef.h>
#include <stdint.h>

/* A named reference: `name` (with its `;` when it has one), its length, and one or two code points (`second`
 * is 0 for a single one). Both tables are sorted bytewise by name. */
typedef struct MsHtmlEntity {
  const char *name;
  uint32_t length;
  uint32_t first;
  uint32_t second;
} MsHtmlEntity;

extern const MsHtmlEntity ms_html_entities[];
extern const size_t ms_html_entity_count;
extern const MsHtmlEntity ms_html_pair_entities[];
extern const size_t ms_html_pair_count;

#endif
