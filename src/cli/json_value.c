/* Owns json_value.h. */
#include "cli/json_value.h"

#include "compiler/syntax/diag_json.h"

typedef struct Reader {
  MsArena *arena;
  MsSpan text;
  size_t at;
  bool failed;
} Reader;

static MsJson *value(Reader *r);

static void skip(Reader *r) {
  while (r->at < r->text.len && (r->text.ptr[r->at] == ' ' || r->text.ptr[r->at] == '\n' ||
                                 r->text.ptr[r->at] == '\r' || r->text.ptr[r->at] == '\t')) {
    r->at++;
  }
}

static MsJson *node(Reader *r, MsJsonKind kind) {
  MsJson *json = MS_ARENA_NEW(r->arena, MsJson);
  json->kind = kind;
  return json;
}

static bool hex4(Reader *r, uint32_t *out) {
  if (r->at + 4 > r->text.len) {
    return false;
  }
  uint32_t code = 0;
  for (size_t i = 0; i < 4; i++) {
    const uint8_t c = r->text.ptr[r->at + i];
    const uint32_t digit = c >= '0' && c <= '9' ? (uint32_t)(c - '0')
                           : c >= 'a' && c <= 'f' ? (uint32_t)(c - 'a' + 10)
                           : c >= 'A' && c <= 'F' ? (uint32_t)(c - 'A' + 10)
                                                  : 99;
    if (digit == 99) {
      return false;
    }
    code = code * 16 + digit;
  }
  r->at += 4;
  *out = code;
  return true;
}

static void put_utf8(MsStrBuild *out, uint32_t code) {
  if (code < 0x80) {
    ms_strbuild_append_byte(out, (uint8_t)code);
  } else if (code < 0x800) {
    ms_strbuild_append_byte(out, (uint8_t)(0xC0 | (code >> 6)));
    ms_strbuild_append_byte(out, (uint8_t)(0x80 | (code & 0x3F)));
  } else if (code < 0x10000) {
    ms_strbuild_append_byte(out, (uint8_t)(0xE0 | (code >> 12)));
    ms_strbuild_append_byte(out, (uint8_t)(0x80 | ((code >> 6) & 0x3F)));
    ms_strbuild_append_byte(out, (uint8_t)(0x80 | (code & 0x3F)));
  } else {
    ms_strbuild_append_byte(out, (uint8_t)(0xF0 | (code >> 18)));
    ms_strbuild_append_byte(out, (uint8_t)(0x80 | ((code >> 12) & 0x3F)));
    ms_strbuild_append_byte(out, (uint8_t)(0x80 | ((code >> 6) & 0x3F)));
    ms_strbuild_append_byte(out, (uint8_t)(0x80 | (code & 0x3F)));
  }
}

static void escape(Reader *r, MsStrBuild *out) {
  if (r->at >= r->text.len) {
    r->failed = true;
    return;
  }
  const uint8_t c = r->text.ptr[r->at++];
  uint32_t code = 0;
  switch (c) {
  case 'n': ms_strbuild_append_byte(out, '\n'); break;
  case 't': ms_strbuild_append_byte(out, '\t'); break;
  case 'r': ms_strbuild_append_byte(out, '\r'); break;
  case 'b': ms_strbuild_append_byte(out, '\b'); break;
  case 'f': ms_strbuild_append_byte(out, '\f'); break;
  case 'u':
    if (!hex4(r, &code)) {
      r->failed = true;
      return;
    }
    if (code >= 0xD800 && code < 0xDC00 && r->at + 1 < r->text.len && r->text.ptr[r->at] == '\\' &&
        r->text.ptr[r->at + 1] == 'u') {
      uint32_t low = 0;
      r->at += 2;
      if (!hex4(r, &low)) {
        r->failed = true;
        return;
      }
      code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00);
    }
    put_utf8(out, code);
    break;
  default: ms_strbuild_append_byte(out, c); break;
  }
}

static MsSpan string_text(Reader *r) {
  MsStrBuild out = ms_strbuild_new();
  r->at++;
  while (!r->failed && r->at < r->text.len && r->text.ptr[r->at] != '"') {
    const uint8_t c = r->text.ptr[r->at++];
    if (c == '\\') {
      escape(r, &out);
    } else {
      ms_strbuild_append_byte(&out, c);
    }
  }
  if (r->at >= r->text.len) {
    r->failed = true;
  }
  r->at++;
  const MsSpan kept = ms_arena_copy(r->arena, ms_strbuild_span(&out));
  ms_strbuild_free(&out);
  return kept;
}

static bool word(Reader *r, const char *text) {
  const MsSpan part = ms_span_of_text(text);
  if (r->at + part.len > r->text.len || !ms_span_equal(ms_span_of(r->text.ptr + r->at, part.len), part)) {
    return false;
  }
  r->at += part.len;
  return true;
}

static MsJson *container(Reader *r, bool object) {
  MsJson *json = node(r, object ? MS_JSON_OBJECT : MS_JSON_ARRAY);
  const uint8_t close = object ? '}' : ']';
  size_t capacity = 0;
  r->at++;
  skip(r);
  if (r->at < r->text.len && r->text.ptr[r->at] == close) {
    r->at++;
    return json;
  }
  while (!r->failed) {
    if (json->count == capacity) {
      const size_t grown = capacity == 0 ? 4 : capacity * 2;
      MsJson **items = MS_ARENA_NEW_ARRAY(r->arena, MsJson *, grown);
      MsSpan *keys = object ? MS_ARENA_NEW_ARRAY(r->arena, MsSpan, grown) : NULL;
      for (size_t i = 0; i < json->count; i++) {
        items[i] = json->items[i];
        if (object) {
          keys[i] = json->keys[i];
        }
      }
      json->items = items;
      json->keys = keys;
      capacity = grown;
    }
    skip(r);
    if (object) {
      if (r->at >= r->text.len || r->text.ptr[r->at] != '"') {
        r->failed = true;
        break;
      }
      json->keys[json->count] = string_text(r);
      skip(r);
      if (r->at >= r->text.len || r->text.ptr[r->at++] != ':') {
        r->failed = true;
        break;
      }
    }
    json->items[json->count++] = value(r);
    skip(r);
    if (r->at >= r->text.len) {
      r->failed = true;
    } else if (r->text.ptr[r->at] == ',') {
      r->at++;
    } else if (r->text.ptr[r->at] == close) {
      r->at++;
      break;
    } else {
      r->failed = true;
    }
  }
  return json;
}

static MsJson *value(Reader *r) {
  skip(r);
  if (r->at >= r->text.len) {
    r->failed = true;
    return node(r, MS_JSON_NULL);
  }
  const uint8_t c = r->text.ptr[r->at];
  if (c == '{' || c == '[') {
    return container(r, c == '{');
  }
  MsJson *json = node(r, MS_JSON_NULL);
  if (c == '"') {
    json->kind = MS_JSON_STRING;
    json->text = string_text(r);
  } else if (word(r, "true") || word(r, "false")) {
    json->kind = MS_JSON_BOOL;
    json->text = ms_span_of(r->text.ptr + r->at - (c == 't' ? 4 : 5), c == 't' ? 4 : 5);
  } else if (word(r, "null")) {
    json->kind = MS_JSON_NULL;
  } else {
    const size_t start = r->at;
    while (r->at < r->text.len && ((r->text.ptr[r->at] >= '0' && r->text.ptr[r->at] <= '9') || r->text.ptr[r->at] == '-' ||
                                   r->text.ptr[r->at] == '+' || r->text.ptr[r->at] == '.' || r->text.ptr[r->at] == 'e' ||
                                   r->text.ptr[r->at] == 'E')) {
      r->at++;
    }
    json->kind = MS_JSON_NUMBER;
    json->text = ms_span_of(r->text.ptr + start, r->at - start);
    r->failed = r->failed || r->at == start;
  }
  return json;
}

MsJson *ms_json_parse(MsArena *arena, MsSpan text) {
  Reader r = {.arena = arena, .text = text};
  MsJson *json = value(&r);
  skip(&r);
  return r.failed || r.at != text.len ? NULL : json;
}

const MsJson *ms_json_member(const MsJson *object, const char *key) {
  for (size_t i = 0; object != NULL && object->kind == MS_JSON_OBJECT && i < object->count; i++) {
    if (ms_span_is_text(object->keys[i], key)) {
      return object->items[i];
    }
  }
  return NULL;
}

void ms_json_write(MsStrBuild *out, const MsJson *json, size_t depth) {
  switch (json->kind) {
  case MS_JSON_NULL: ms_strbuild_append_text(out, "null"); return;
  case MS_JSON_BOOL:
  case MS_JSON_NUMBER: ms_strbuild_append(out, json->text); return;
  case MS_JSON_STRING: ms_json_string(out, json->text); return;
  case MS_JSON_ARRAY:
  case MS_JSON_OBJECT: break;
  }
  const bool object = json->kind == MS_JSON_OBJECT;
  if (json->count == 0) {
    ms_strbuild_append_text(out, object ? "{}" : "[]");
    return;
  }
  ms_strbuild_append_text(out, object ? "{\n" : "[\n");
  for (size_t i = 0; i < json->count; i++) {
    ms_strbuild_append_indent(out, depth + 1);
    if (object) {
      ms_json_string(out, json->keys[i]);
      ms_strbuild_append_text(out, ": ");
    }
    ms_json_write(out, json->items[i], depth + 1);
    ms_strbuild_append_text(out, i + 1 < json->count ? ",\n" : "\n");
  }
  ms_strbuild_append_indent(out, depth);
  ms_strbuild_append_byte(out, object ? '}' : ']');
}
