/* Unit test of the shape walkers on hand-built tables (the compiler builds them for real programs). */
#include <stdio.h>
#include <stdlib.h>

#include "base/alloc.h"
#include "base/list.h"
#include "base/map.h"
#include "runtime/std/shape_json.h"
#include "runtime/std/shape_text.h"

enum { MAX_SHAPES = 16, MAX_MEMBERS = 16, MAX_STRINGS = 512 };

/* A table under construction: arrays that finish() lays out as one flat image. */
typedef struct Builder {
  MsShape shapes[MAX_SHAPES];
  MsShapeMember members[MAX_MEMBERS];
  char strings[MAX_STRINGS];
  uint32_t shape_count, member_count, string_size;
  uint8_t *image;
} Builder;

static uint32_t text(Builder *b, const char *value) {
  const uint32_t at = b->string_size;
  while (*value != 0) {
    b->strings[b->string_size++] = *value++;
  }
  b->strings[b->string_size++] = 0;
  return at;
}

static uint32_t shape(Builder *b, MsShape value) {
  b->shapes[b->shape_count] = value;
  return b->shape_count++;
}

static uint32_t scalar(Builder *b, MsShapeKind kind, uint32_t size) {
  return shape(b, (MsShape){.kind = (uint8_t)kind,
                            .size = size,
                            .align = (uint16_t)(size == 0 ? 1 : size),
                            .name = MS_SHAPE_NONE,
                            .elem = MS_SHAPE_NONE,
                            .value = MS_SHAPE_NONE});
}

static uint32_t member(Builder *b, const char *name, uint32_t shape_index, uint32_t offset) {
  b->members[b->member_count] =
      (MsShapeMember){.name = text(b, name), .shape = shape_index, .offset = offset};
  return b->member_count++;
}

static MsShapeTable finish(Builder *b, uint32_t root) {
  const size_t shapes_at = sizeof(MsShapeImage);
  const size_t members_at = shapes_at + b->shape_count * sizeof(MsShape);
  const size_t strings_at = members_at + b->member_count * sizeof(MsShapeMember);
  b->image = calloc(1, strings_at + b->string_size);
  const MsShapeImage header = {.magic = MS_SHAPE_MAGIC,
                               .shapes_at = (uint32_t)shapes_at,
                               .shape_count = b->shape_count,
                               .members_at = (uint32_t)members_at,
                               .member_count = b->member_count,
                               .strings_at = (uint32_t)strings_at,
                               .strings_size = b->string_size,
                               .root = root};
  __builtin_memcpy(b->image, &header, sizeof header);
  __builtin_memcpy(b->image + shapes_at, b->shapes, b->shape_count * sizeof(MsShape));
  __builtin_memcpy(b->image + members_at, b->members, b->member_count * sizeof(MsShapeMember));
  __builtin_memcpy(b->image + strings_at, b->strings, b->string_size);
  return (MsShapeTable){.image = (const MsShapeImage *)(const void *)b->image};
}

static int failures;

static void json(const char *what, const MsShapeTable *table, const void *value, const char *wanted) {
  MsString out = ms_string_empty();
  const uint8_t status = msstd_json_stringify(table, value, 0, 0, 0, 0, 0, &out);
  if (status != 0) {
    printf("FAIL %s: status %u\n", what, (unsigned)status);
    failures++;
    return;
  }
  const MsSpan got = ms_string_span(&out);
  if (!ms_span_is_text(got, wanted)) {
    printf("FAIL %s: got '%.*s', wanted '%s'\n", what, (int)got.len, (const char *)got.ptr, wanted);
    failures++;
  }
  ms_string_release(&out);
}

static void expect(const char *what, MsString *actual, const char *wanted) {
  const MsSpan got = ms_string_span(actual);
  if (!ms_span_is_text(got, wanted)) {
    printf("FAIL %s: got '%.*s', wanted '%s'\n", what, (int)got.len, (const char *)got.ptr, wanted);
    failures++;
  }
  ms_string_release(actual);
}

typedef struct Person {
  MsString name;
  int64_t age;
} Person;

static void test_record(void) {
  Builder b = {0};
  const uint32_t string_shape = scalar(&b, MS_SHAPE_STRING, sizeof(MsString));
  const uint32_t int_shape = scalar(&b, MS_SHAPE_INT, 8);
  const uint32_t first = member(&b, "name", string_shape, offsetof(Person, name));
  member(&b, "age", int_shape, offsetof(Person, age));
  const uint32_t root = shape(&b, (MsShape){.kind = MS_SHAPE_RECORD,
                                            .size = sizeof(Person),
                                            .align = 8,
                                            .name = text(&b, "Person"),
                                            .first = first,
                                            .count = 2,
                                            .elem = MS_SHAPE_NONE,
                                            .value = MS_SHAPE_NONE});
  const MsShapeTable table = finish(&b, root);
  Person person = {.name = ms_string_from_span(ms_span_of_text("Al")), .age = 3};
  MsString out;
  ms_shape_text_of(&table, &person, true, &out);
  expect("record repr", &out, "Person(name: \"Al\", age: 3)");
  ms_shape_text_of(&table, &person, false, &out);
  expect("record plain", &out, "Person(age: 3, name: Al)");
  json("record json", &table, &person, "{\"name\":\"Al\",\"age\":3}");
  ms_string_release(&person.name);
  free(b.image);
}

static void test_list_and_optional(void) {
  Builder b = {0};
  const uint32_t string_shape = scalar(&b, MS_SHAPE_STRING, sizeof(MsString));
  const uint32_t optional = shape(&b, (MsShape){.kind = MS_SHAPE_OPTIONAL,
                                                .flags = MS_SHAPE_NULLABLE,
                                                .size = sizeof(MsString),
                                                .align = 8,
                                                .name = MS_SHAPE_NONE,
                                                .elem = string_shape,
                                                .value = MS_SHAPE_NONE});
  const uint32_t root = shape(&b, (MsShape){.kind = MS_SHAPE_LIST,
                                            .size = sizeof(MsList),
                                            .align = 8,
                                            .name = MS_SHAPE_NONE,
                                            .elem = optional,
                                            .value = MS_SHAPE_NONE});
  const MsShapeTable table = finish(&b, root);
  MsString items[2] = {ms_string_from_span(ms_span_of_text("a")), {0}};
  MsList list = {.ptr = (uint8_t *)(void *)items, .len = 2, .cap = 2};
  MsString out;
  ms_shape_text_of(&table, &list, false, &out);
  expect("list plain", &out, "[some(a), none]");
  ms_shape_text_of(&table, &list, true, &out);
  expect("list repr", &out, "[some(\"a\"), none]");
  json("list json", &table, &list, "[\"a\",null]");
  free(b.image);
}

typedef struct Figure {
  int64_t tag;
  int64_t radius;
} Figure;

static void test_alternative(void) {
  Builder b = {0};
  const uint32_t int_shape = scalar(&b, MS_SHAPE_INT, 8);
  const uint32_t circle_field = member(&b, "radius", int_shape, offsetof(Figure, radius));
  const uint32_t circle = member(&b, "Circle", MS_SHAPE_NONE, 0);
  b.members[circle].first = circle_field;
  b.members[circle].count = 1;
  const uint32_t dot = member(&b, "Dot", MS_SHAPE_NONE, 0);
  b.members[dot].tag = 1;
  const uint32_t root = shape(&b, (MsShape){.kind = MS_SHAPE_ALTERNATIVE,
                                            .size = sizeof(Figure),
                                            .align = 8,
                                            .name = text(&b, "Figure"),
                                            .first = circle,
                                            .count = 2,
                                            .elem = MS_SHAPE_NONE,
                                            .value = MS_SHAPE_NONE,
                                            .extra = 0});
  const MsShapeTable table = finish(&b, root);
  Figure value = {.tag = 0, .radius = 2};
  MsString out;
  json("case json", &table, &value, "{\"Circle\":{\"radius\":2}}");
  ms_shape_text_of(&table, &value, true, &out);
  expect("alternative repr", &out, "Circle(radius: 2)");
  ms_shape_text_of(&table, &value, false, &out);
  expect("alternative plain", &out, "Figure.Circle(2)");
  value.tag = 1;
  ms_shape_text_of(&table, &value, false, &out);
  expect("bare case", &out, "Figure.Dot");
  json("bare case json", &table, &value, "\"Dot\"");
  free(b.image);
}

int main(void) {
  test_record();
  test_list_and_optional();
  test_alternative();
  if (failures == 0) {
    printf("shape unit: ok\n");
  }
  return failures == 0 ? 0 : 1;
}
