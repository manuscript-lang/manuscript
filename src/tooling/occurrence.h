/* tooling/occurrence.h: the occurrence index: every resolved declaration and use in the user's modules, keyed by
 * identity so that references, hover and type hints group by what a name denotes. Port of the occurrence index of
 * crates/ms-lsp/src/index.rs, read from the checker's facts. The key spelling (`symbol:<file>:<offset>`, `field:`,
 * `case:`, `method:`, `operation:`, `parameter:`, `binding:`) is the oracle's, so entries sort as it sorts them.
 *
 * Ownership: every text lives in the arena the caller gives; the program must outlive the index. */
#ifndef MS_TOOLING_OCCURRENCE_H
#define MS_TOOLING_OCCURRENCE_H

#include "compiler/check/program.h"
#include "tooling/avec.h"

typedef struct MsOccurrence {
  MsSpan key;      /* equal keys name the same declaration across files */
  MsSpan name;     /* the written name */
  uint32_t module; /* index in the program's modules */
  uint32_t offset, end; /* byte range of the name */
  bool declaration;
  bool write;
  MsTy ty;         /* MS_TY_NONE when the checker has no type for it */
  MsSymbolId symbol; /* the module symbol it denotes, or 0 */
  bool method;       /* it denotes a method or an operation */
} MsOccurrence;

MS_AVEC(MsOccurrences, ms_occurrences, MsOccurrence)

/* One written type of a user module: where its name starts and what it resolved to, `Int` and type variables included. */
typedef struct MsWrittenType {
  uint32_t module, offset;
  MsTy ty;
  bool named; /* a named type, not a function type */
} MsWrittenType;

MS_AVEC(MsWrittenTypes, ms_written_types, MsWrittenType)

/* The index of the user's modules, sorted by file name, offset and key, one entry per (file, offset, key). */
MsOccurrences ms_occurrence_index(MsArena *arena, MsCheckProgram *program);
/* The same, and every written type of the user's modules whose type resolved, in `written` when it is not NULL. */
MsOccurrences ms_occurrence_index_with_types(MsArena *arena, MsCheckProgram *program, MsWrittenTypes *written);

/* The checked type of one identifier, for the html map: a zero-based line and a UTF-16 column. */
typedef struct MsTypeHint {
  MsSpan file, ty;
  size_t line, col, len;
} MsTypeHint;

MS_AVEC(MsTypeHints, ms_type_hints, MsTypeHint)

/* The type of every identifier of the user's modules whose type resolved, in index order. */
MsTypeHints ms_occurrence_type_hints(MsArena *arena, const MsCheckProgram *program, const MsOccurrences *index);

/* The zero-based line and UTF-16 column of the byte `offset` of `source`. */
void ms_source_position(MsSpan source, size_t offset, size_t *line, size_t *column);

#endif
