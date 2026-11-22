/* tooling/avec.h: growable arrays whose storage lives in an arena, for the tooling models that are built once, read,
 * and dropped with the arena. `MS_AVEC(Name, prefix, T)` defines `Name` and `prefix_push(arena, &list, value)`. */
#ifndef MS_TOOLING_AVEC_H
#define MS_TOOLING_AVEC_H

#include "base/arena.h"

#define MS_AVEC(Name, prefix, T)                                                                             \
  typedef struct Name {                                                                                      \
    T *ptr;                                                                                                  \
    size_t len, cap;                                                                                         \
  } Name;                                                                                                    \
  MS_UNUSED static inline void prefix##_push(MsArena *arena, Name *list, T value) {                          \
    if (list->len == list->cap) {                                                                            \
      const size_t cap = list->cap == 0 ? 4 : list->cap * 2;                                                 \
      T *grown = MS_ARENA_NEW_ARRAY(arena, T, cap);                                                          \
      for (size_t i = 0; i < list->len; i++) {                                                               \
        grown[i] = list->ptr[i];                                                                             \
      }                                                                                                      \
      list->ptr = grown;                                                                                     \
      list->cap = cap;                                                                                       \
    }                                                                                                        \
    list->ptr[list->len++] = value;                                                                          \
  }

MS_AVEC(MsSpans, ms_spans, MsSpan)

#endif
