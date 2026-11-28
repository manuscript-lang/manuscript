/* Owns the erased growable array (see list.h). */
#include "base/list.h"

#include "base/alloc.h"
#include "base/fatal.h"

#define MS_LIST_MIN_CAPACITY 4
#define MS_LIST_MIN_BYTES 32 /* a byte builder starts here, not at 4 bytes and four doublings from the first line */

void ms_list_out_of_range(size_t index, size_t length) {
  (void)index;
  (void)length;
  ms_fatal(MS_FATAL_OUT_OF_RANGE, "list index out of range");
}

static size_t grown_capacity(size_t current, size_t needed, size_t element_size) {
  size_t minimum = element_size != 0 ? MS_LIST_MIN_BYTES / element_size : 0;
  minimum = minimum < MS_LIST_MIN_CAPACITY ? MS_LIST_MIN_CAPACITY : minimum;
  size_t capacity = current < minimum ? minimum : current;
  while (capacity < needed) {
    size_t doubled = 0;
    if (!ms_size_mul(capacity, 2, &doubled)) {
      return needed;
    }
    capacity = doubled;
  }
  return capacity;
}

void ms_list_reserve(MsList *list, size_t element_size, size_t extra) {
  size_t needed = 0;
  if (!ms_size_add(list->len, extra, &needed)) {
    ms_fatal(MS_FATAL_OVERFLOW, "list size overflow");
  }
  if (needed <= list->cap) {
    return;
  }
  const size_t capacity = grown_capacity(list->cap, needed, element_size);
  size_t bytes = 0;
  if (!ms_size_mul(capacity, element_size, &bytes)) {
    ms_fatal(MS_FATAL_OVERFLOW, "list size overflow");
  }
  if (list->cap == 0) { /* empty or a view: copy what a view holds into a new buffer */
    uint8_t *buffer = ms_alloc(bytes);
    if (list->len != 0) {
      __builtin_memcpy(buffer, list->ptr, list->len * element_size);
    }
    list->ptr = buffer;
  } else {
    list->ptr = ms_realloc(list->ptr, bytes);
  }
  list->cap = capacity;
}

/* A stable non-null address for a zero-length extension. Callers write `count` elements and write none. */
static uint8_t ms_list_vacant;

void *ms_list_extend_grow(MsList *list, size_t element_size, size_t count) {
  /* Zero new elements do not allocate. Adding to a null buffer is undefined, and the result must be non-null. */
  if (count == 0) {
    return &ms_list_vacant;
  }
  ms_list_reserve(list, element_size, count);
  uint8_t *first = list->ptr + list->len * element_size;
  list->len += count;
  return first;
}

void ms_list_free(MsList *list) {
  if (list->cap != 0) {
    ms_free(list->ptr);
  }
  *list = (MsList){0};
}
