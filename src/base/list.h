/* base/list.h: growable arrays, in two tiers over one design.
 *
 * MsList is the erased array: `{ptr, len, cap}` is the layout of every Manuscript List and of Bytes, and the
 * element size is passed in. MS_LIST_DEFINE makes a typed wrapper of the same layout whose functions are
 * inline and know the element size, for the compiler's token, node and instruction arrays.
 *
 * Ownership: the list owns its buffer (freed with ms_list_free). A view has cap 0 with a ptr, borrows its
 * elements and frees nothing. Elements that own memory are dropped by the caller (loop over the list before
 * freeing) or through a TypeDesc (base/value, for runtime lists). Growth doubles; sizes are checked and
 * failure reports through ms_fatal. */
#ifndef MS_BASE_LIST_H
#define MS_BASE_LIST_H

#include "base/safe.h"

typedef struct MsList {
  uint8_t *ptr; /* owned when cap != 0; NULL while cap is 0 and the list is empty */
  size_t len;
  size_t cap;
} MsList;

_Static_assert(sizeof(MsList) == 24, "list layout is ABI");

/* Makes room for `extra` more elements of `element_size` bytes. */
void ms_list_reserve(MsList *list, size_t element_size, size_t extra);

/* Appends `count` uninitialised elements and returns the address of the first, growing the buffer first. The
 * inline `ms_list_extend` takes this only when the buffer has no room (or the list is a view, whose cap is 0). */
MS_RETURNS_NONNULL void *ms_list_extend_grow(MsList *list, size_t element_size, size_t count);

/* Appends `count` uninitialised elements and returns the address of the first. A list that owns a buffer with
 * room for them takes no call. */
MS_RETURNS_NONNULL static inline void *ms_list_extend(MsList *list, size_t element_size, size_t count) {
  if (list->cap == 0 || count > list->cap - list->len) {
    return ms_list_extend_grow(list, element_size, count);
  }
  uint8_t *const first = list->ptr + list->len * element_size;
  list->len += count;
  return first;
}

/* Appends one element (a copy of `element_size` bytes at `element`). */
static inline void ms_list_push(MsList *list, size_t element_size, const void *element) {
  ms_copy_slot(ms_list_extend(list, element_size, 1), element, element_size);
}

/* Frees the buffer of an owning list and leaves it empty; a view just becomes empty. */
void ms_list_free(MsList *list);

/* The address of element `index`; false when out of range. */
MS_NODISCARD MS_NONNULL static inline bool ms_list_at(const MsList *list, size_t element_size, size_t index,
                                                      void **out) {
  if (index >= list->len) {
    return false;
  }
  *out = list->ptr + index * element_size;
  return true;
}

/* A typed growable array. `Name` is the struct, `prefix` the function prefix, `T` the element type:
 *   MS_LIST_DEFINE(TokenList, token_list, Token)
 * defines token_list_push, _pop, _get, _at, _last, _clear, _truncate, _reserve, _free, _span. `_at` is
 * checked and reports through ms_fatal; `_get` returns false when out of range. */
#define MS_LIST_DEFINE(Name, prefix, T)                                                                      \
  typedef struct Name {                                                                                      \
    T *ptr;                                                                                                  \
    size_t len;                                                                                              \
    size_t cap;                                                                                              \
  } Name;                                                                                                    \
  _Static_assert(sizeof(Name) == sizeof(MsList), "typed list matches the erased layout");                    \
  MS_UNUSED static inline MsList *prefix##_erased(Name *list) {                                              \
    return (MsList *)(void *)list;                                                                           \
  }                                                                                                          \
  MS_UNUSED static inline void prefix##_reserve(Name *list, size_t extra) {                                  \
    ms_list_reserve(prefix##_erased(list), sizeof(T), extra);                                                \
  }                                                                                                          \
  MS_UNUSED static inline void prefix##_push(Name *list, T value) {                                          \
    if (list->len < list->cap) { /* room: the common case stores in place, with no call */                  \
      list->ptr[list->len++] = value;                                                                        \
      return;                                                                                                \
    }                                                                                                        \
    ms_list_push(prefix##_erased(list), sizeof(T), &value);                                                  \
  }                                                                                                          \
  MS_UNUSED static inline T *prefix##_extend(Name *list, size_t count) {                                     \
    return (T *)ms_list_extend(prefix##_erased(list), sizeof(T), count);                                     \
  }                                                                                                          \
  MS_UNUSED MS_NODISCARD static inline bool prefix##_get(const Name *list, size_t index, T *out) {           \
    if (index >= list->len) {                                                                                \
      return false;                                                                                          \
    }                                                                                                        \
    *out = list->ptr[index];                                                                                 \
    return true;                                                                                             \
  }                                                                                                          \
  MS_UNUSED static inline T *prefix##_at(Name *list, size_t index) {                                         \
    if (index >= list->len) {                                                                                \
      ms_list_out_of_range(index, list->len);                                                                \
    }                                                                                                        \
    return &list->ptr[index];                                                                                \
  }                                                                                                          \
  MS_UNUSED static inline T *prefix##_last(Name *list) {                                                     \
    return prefix##_at(list, list->len - 1);                                                                 \
  }                                                                                                          \
  MS_UNUSED MS_NODISCARD static inline bool prefix##_pop(Name *list, T *out) {                               \
    if (list->len == 0) {                                                                                    \
      return false;                                                                                          \
    }                                                                                                        \
    list->len--;                                                                                             \
    *out = list->ptr[list->len];                                                                             \
    return true;                                                                                             \
  }                                                                                                          \
  MS_UNUSED static inline void prefix##_truncate(Name *list, size_t length) {                                \
    if (length < list->len) {                                                                                \
      list->len = length;                                                                                    \
    }                                                                                                        \
  }                                                                                                          \
  MS_UNUSED static inline void prefix##_clear(Name *list) {                                                  \
    list->len = 0;                                                                                           \
  }                                                                                                          \
  MS_UNUSED static inline void prefix##_free(Name *list) {                                                   \
    ms_list_free(prefix##_erased(list));                                                                     \
  }

/* Reports an out-of-range index through ms_fatal; never returns. */
MS_NORETURN void ms_list_out_of_range(size_t index, size_t length);

#endif
