/* compiler/link/glibc_table.h: the parsed table of glibc exports. */
#ifndef MS_COMPILER_LINK_GLIBC_TABLE_H
#define MS_COMPILER_LINK_GLIBC_TABLE_H

#include "base/list.h"
#include "base/safe.h"

/* One line of the table; the spans point into the table text, which outlives the list. */
typedef struct GlibcExport {
  MsSpan soname, version, name;
  bool data;     /* a data symbol, which needs zeroed storage of `size` bytes for copy relocations */
  uint64_t size;
} GlibcExport;

MS_LIST_DEFINE(GlibcExportList, glibc_export_list, GlibcExport)

/* Appends the exports of `text`; comment and blank lines are skipped. */
void glibc_table_parse(MsSpan text, GlibcExportList *out);

#endif
