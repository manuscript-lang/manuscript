/* runtime/std/path_internal.h: what the glob compiler (path_glob.c) and its brace expansion (path_brace.c)
 * share. */
#ifndef MS_RUNTIME_STD_PATH_INTERNAL_H
#define MS_RUNTIME_STD_PATH_INTERNAL_H

#include <string.h>

#include "base/alloc.h"
#include "base/chars.h"
#include "base/safe.h"
#include "runtime/std/path.h"

enum {
  MAX_PATTERN_BYTES = 4096,
  MAX_BRACE_RESULTS = 1025,
  MAX_BRACE_RANGE = 1024,
  MAX_NESTING = 64,
  INLINE_WORDS = 2, /* position sets for up to 127 positions live on the stack */
};

/* How a step of parsing or expansion ended. */
typedef enum MsPathResult {
  PATH_OK,
  PATH_INVALID,
  PATH_NO_MEMORY,
} MsPathResult;

/* A zeroed array of `count` elements of `size` bytes; NULL on overflow. Owned by the caller. */
void *path_array_new(size_t count, size_t size);

/* Replaces *array (capacity *capacity) with a zeroed one of at least `needed` elements, keeping `count` of
 * them. False on overflow, leaving the old array in place. */
MS_NODISCARD bool path_array_reserve(void **array, size_t *capacity, size_t count, size_t needed,
                                     size_t size);

/* Owned byte strings: the alternatives a brace expansion produced. */
typedef struct MsText {
  char *ptr; /* owned */
  size_t len;
} MsText;

typedef struct MsTextList {
  MsText *items; /* owned, each item owned */
  size_t count;
  size_t capacity;
} MsTextList;

void path_text_list_free(MsTextList *list);

/* bytes[start..end], or an empty span when the range is out of bounds. */
MsSpan path_span_range(MsSpan bytes, size_t start, size_t end);

/* Expands every `{a,b}` and `{1..3}` of `pattern` into `out`; PATH_INVALID for a pattern past a limit. */
MsPathResult path_expand_braces(MsSpan pattern, size_t depth, MsTextList *out);


/* ---- glob syntax tree (path_syntax.c) ---- */

typedef struct MsChars {
  const uint32_t *ptr; /* borrowed */
  size_t len;
} MsChars;

typedef struct MsRange {
  uint32_t low;
  uint32_t high;
} MsRange;

typedef enum MsAtomKind {
  ATOM_STAR,
  ATOM_ANY,
  ATOM_CLASS,
  ATOM_LITERAL,
  ATOM_GROUP,
} MsAtomKind;

typedef struct MsAtom MsAtom;

typedef struct MsSeq {
  MsAtom *atoms; /* owned */
  size_t count;
  size_t capacity;
} MsSeq;

struct MsAtom {
  MsAtomKind kind;
  uint32_t literal; /* ATOM_LITERAL */
  bool negated;     /* ATOM_CLASS */
  MsRange *ranges;  /* ATOM_CLASS, owned */
  size_t range_count;
  uint32_t group_kind; /* ATOM_GROUP: one of @ + ? ! * */
  MsSeq *alternatives; /* ATOM_GROUP, owned, each owned */
  size_t alternative_count;
};

void path_seq_free(MsSeq *seq);

/* Parses `pattern` (one segment's code points) into `seq`. */
MsPathResult path_parse_sequence(MsChars pattern, size_t depth, MsSeq *seq);

#endif
