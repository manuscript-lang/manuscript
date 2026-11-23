/* runtime/std/http_headers.c: the header multimap. A group is a name and its values; lookups scan the
 * groups, which is right for the tens of fields a head may carry (a head is bounded by the server limit). */
#include "runtime/std/http_headers.h"

#include "base/alloc.h"
#include "base/utf8.h"

typedef struct MsHeaderGroup {
  MsString name; /* the spelling of the first use */
  MsList values; /* MsBytes elements, owned */
} MsHeaderGroup;

struct MsHeaders {
  MsObj object;
  MsList groups; /* MsHeaderGroup elements */
};

static bool is_token_byte(uint8_t b) {
  if ((b >= '0' && b <= '9') || (b >= 'a' && b <= 'z') || (b >= 'A' && b <= 'Z')) {
    return true;
  }
  return b != 0 && ms_span_find(ms_span_of_text("!#$%&'*+-.^_`|~"), ms_span_of(&b, 1), &(size_t){0});
}

bool ms_header_valid_name(MsSpan name) {
  for (size_t i = 0; i < name.len; i++) {
    if (!is_token_byte(name.ptr[i])) {
      return false;
    }
  }
  return name.len > 0;
}

bool ms_header_valid_value(MsSpan value) {
  for (size_t i = 0; i < value.len; i++) {
    const uint8_t b = value.ptr[i];
    if ((b < 32 && b != '\t') || b == 127) {
      return false;
    }
  }
  return ms_utf8_is_valid(value.ptr, value.len);
}

void ms_header_canonical(MsSpan name, MsStrBuild *out) {
  const bool token = ms_header_valid_name(name);
  bool upper = true;
  for (size_t i = 0; i < name.len; i++) {
    uint8_t b = name.ptr[i];
    if (token) {
      const bool is_lower = b >= 'a' && b <= 'z';
      const bool is_upper = b >= 'A' && b <= 'Z';
      b = (uint8_t)(upper && is_lower ? b - 32 : !upper && is_upper ? b + 32 : b);
      upper = name.ptr[i] == '-';
    }
    ms_strbuild_append_byte(out, b);
  }
}

static uint8_t fold(uint8_t b) {
  return (uint8_t)(b >= 'A' && b <= 'Z' ? b + 32 : b);
}

/* Compares ASCII case-insensitively: negative, zero or positive like memcmp. */
static int fold_compare(MsSpan a, MsSpan b) {
  const size_t n = a.len < b.len ? a.len : b.len;
  for (size_t i = 0; i < n; i++) {
    const int d = (int)fold(a.ptr[i]) - (int)fold(b.ptr[i]);
    if (d != 0) {
      return d;
    }
  }
  return a.len == b.len ? 0 : a.len < b.len ? -1 : 1;
}

static MsHeaderGroup *group_at(const MsHeaders *headers, size_t index) {
  return (MsHeaderGroup *)(void *)headers->groups.ptr + index;
}

static MsHeaderGroup *find_group(const MsHeaders *headers, MsSpan name) {
  for (size_t i = 0; i < headers->groups.len; i++) {
    MsHeaderGroup *group = group_at(headers, i);
    if (fold_compare(ms_string_span(&group->name), name) == 0) {
      return group;
    }
  }
  return NULL;
}

static void group_free(MsHeaderGroup *group) {
  ms_bytes_list_free(&group->values);
  ms_string_release(&group->name);
}

void ms_bytes_list_free(MsList *list) {
  for (size_t i = 0; i < list->len; i++) {
    MsBytes *bytes = (MsBytes *)(void *)list->ptr + i;
    ms_bytes_free(bytes);
  }
  ms_list_free(list);
}

static void push_value(MsHeaderGroup *group, MsSpan value) {
  const MsBytes copy = ms_bytes_from_span(value);
  ms_list_push(&group->values, sizeof copy, &copy);
}

static void headers_drop(MsObj *object) {
  MsHeaders *headers = (MsHeaders *)(void *)object;
  ms_headers_free(headers);
}

/* The copy a record's `.clone()` makes of the headers it holds; headers have one owner, so nothing else copies them. */
static MsObj *headers_clone(MsObj *object) {
  return &ms_headers_copy((const MsHeaders *)(const void *)object)->object;
}

MsHeaders *ms_headers_new(void) {
  MsHeaders *headers = ms_alloc(sizeof *headers);
  *headers = (MsHeaders){.object = {.clone = headers_clone, .drop = headers_drop}};
  return headers;
}

void ms_headers_free(MsHeaders *headers) {
  for (size_t i = 0; i < headers->groups.len; i++) {
    group_free(group_at(headers, i));
  }
  ms_list_free(&headers->groups);
  ms_free(headers);
}

MsObj *ms_headers_object(MsHeaders *headers) {
  return &headers->object;
}

const MsHeaders *ms_headers_of(const MsObj *object) {
  return (const MsHeaders *)(const void *)object;
}

static MsHeaderGroup *new_group(MsHeaders *headers, MsSpan name) {
  const MsHeaderGroup group = {.name = ms_string_from_span(name)};
  ms_list_push(&headers->groups, sizeof group, &group);
  return group_at(headers, headers->groups.len - 1);
}

MsHeaders *ms_headers_copy(const MsHeaders *headers) {
  MsHeaders *copy = ms_headers_new();
  for (size_t g = 0; g < headers->groups.len; g++) {
    const MsHeaderGroup *group = group_at(headers, g);
    MsHeaderGroup *into = new_group(copy, ms_string_span(&group->name));
    for (size_t v = 0; v < group->values.len; v++) {
      const MsBytes *value = (const MsBytes *)(const void *)group->values.ptr + v;
      push_value(into, ms_bytes_span(value));
    }
  }
  return copy;
}

void ms_headers_add(MsHeaders *headers, MsSpan name, MsSpan value) {
  MsHeaderGroup *group = find_group(headers, name);
  push_value(group != NULL ? group : new_group(headers, name), value);
}

uint8_t ms_headers_append(MsHeaders *headers, MsSpan name, MsSpan value) {
  if (!ms_header_valid_name(name)) {
    return MS_STATUS_INVALID_INPUT;
  }
  ms_headers_add(headers, name, value);
  return MS_STATUS_OK;
}

void ms_headers_set(MsHeaders *headers, MsSpan name, MsSpan value) {
  MsHeaderGroup *group = find_group(headers, name);
  if (group == NULL) {
    ms_headers_add(headers, name, value);
    return;
  }
  ms_bytes_list_free(&group->values);
  push_value(group, value);
}

bool ms_headers_remove(MsHeaders *headers, MsSpan name) {
  for (size_t i = 0; i < headers->groups.len; i++) {
    if (fold_compare(ms_string_span(&group_at(headers, i)->name), name) != 0) {
      continue;
    }
    group_free(group_at(headers, i));
    headers->groups.len--;
    __builtin_memmove(group_at(headers, i), group_at(headers, i + 1),
                      (headers->groups.len - i) * sizeof(MsHeaderGroup));
    return true;
  }
  return false;
}

bool ms_headers_is_empty(const MsHeaders *headers) {
  return headers->groups.len == 0;
}

bool ms_headers_first(const MsHeaders *headers, MsSpan name, MsSpan *out) {
  const MsHeaderGroup *group = find_group(headers, name);
  if (group == NULL) {
    return false;
  }
  *out = ms_bytes_span((const MsBytes *)(const void *)group->values.ptr);
  return true;
}

bool ms_headers_values(const MsHeaders *headers, MsSpan name, MsList *out) {
  const MsHeaderGroup *group = find_group(headers, name);
  if (group == NULL) {
    return false;
  }
  *out = (MsList){0};
  for (size_t v = 0; v < group->values.len; v++) {
    const MsBytes *value = (const MsBytes *)(const void *)group->values.ptr + v;
    const MsBytes copy = ms_bytes_from_span(ms_bytes_span(value));
    ms_list_push(out, sizeof copy, &copy);
  }
  return true;
}

uint8_t ms_headers_text(const MsHeaders *headers, MsSpan name, bool *found, MsList *out) {
  const MsHeaderGroup *group = find_group(headers, name);
  *found = group != NULL;
  if (group == NULL) {
    return MS_STATUS_OK;
  }
  for (size_t v = 0; v < group->values.len; v++) {
    const MsBytes *value = (const MsBytes *)(const void *)group->values.ptr + v;
    if (!ms_utf8_is_valid(value->ptr, value->len)) {
      return MS_STATUS_INVALID_DATA;
    }
  }
  *out = (MsList){0};
  for (size_t v = 0; v < group->values.len; v++) {
    const MsBytes *value = (const MsBytes *)(const void *)group->values.ptr + v;
    const MsString text = ms_string_from_span(ms_bytes_span(value));
    ms_list_push(out, sizeof text, &text);
  }
  return MS_STATUS_OK;
}

size_t ms_headers_group_count(const MsHeaders *headers) {
  return headers->groups.len;
}

MsSpan ms_headers_group_name(const MsHeaders *headers, size_t group) {
  return ms_string_span(&group_at(headers, group)->name);
}

size_t ms_headers_group_size(const MsHeaders *headers, size_t group) {
  return group_at(headers, group)->values.len;
}

MsSpan ms_headers_group_value(const MsHeaders *headers, size_t group, size_t index) {
  return ms_bytes_span((const MsBytes *)(const void *)group_at(headers, group)->values.ptr + index);
}

/* Inserts a group at `at`. */
static MsHeaderGroup *insert_group(MsHeaders *headers, size_t at, MsSpan name) {
  (void)new_group(headers, name);
  MsHeaderGroup *last = group_at(headers, headers->groups.len - 1);
  const MsHeaderGroup moved = *last;
  __builtin_memmove(group_at(headers, at + 1), group_at(headers, at),
                    (headers->groups.len - 1 - at) * sizeof moved);
  *group_at(headers, at) = moved;
  return group_at(headers, at);
}

MsHeaders *ms_headers_from_received(const MsHeaderField *fields, size_t count) {
  MsHeaders *headers = ms_headers_new();
  for (size_t i = 0; i < count; i++) {
    MsStrBuild name = ms_strbuild_new();
    ms_header_canonical(fields[i].name, &name);
    const MsString text = ms_strbuild_finish(&name);
    ms_strbuild_free(&name);
    MsHeaderGroup *group = find_group(headers, ms_string_span(&text));
    if (group == NULL) {
      size_t at = 0;
      while (at < headers->groups.len && ms_string_compare(&group_at(headers, at)->name, &text) <= 0) {
        at++;
      }
      group = insert_group(headers, at, ms_string_span(&text));
    }
    push_value(group, fields[i].value);
    MsString owned = text;
    ms_string_release(&owned);
  }
  return headers;
}

void ms_headers_sort(MsHeaders *headers) {
  for (size_t i = 1; i < headers->groups.len; i++) {
    const MsHeaderGroup moved = *group_at(headers, i);
    size_t at = i;
    while (at > 0 &&
           fold_compare(ms_string_span(&group_at(headers, at - 1)->name), ms_string_span(&moved.name)) > 0) {
      *group_at(headers, at) = *group_at(headers, at - 1);
      at--;
    }
    *group_at(headers, at) = moved;
  }
}

bool ms_headers_is_text(const MsHeaders *headers) {
  for (size_t g = 0; g < headers->groups.len; g++) {
    const MsHeaderGroup *group = group_at(headers, g);
    for (size_t v = 0; v < group->values.len; v++) {
      const MsBytes *value = (const MsBytes *)(const void *)group->values.ptr + v;
      if (!ms_utf8_is_valid(value->ptr, value->len)) {
        return false;
      }
    }
  }
  return true;
}
