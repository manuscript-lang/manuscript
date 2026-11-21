/* compiler/project/semver.c: port of crates/ms-driver/src/project/semver.rs. */
#include "compiler/project/semver.h"

#include "base/chars.h"
#include "base/list.h"
#include "base/message.h"
#include "compiler/project/project_internal.h"

MS_LIST_DEFINE(IdentList, ident_list, MsSpan)

/* A decimal number without a leading zero that fits in 64 bits. */
static bool number(MsSpan part, uint64_t *out) {
  if (part.len == 0 || (part.len > 1 && part.ptr[0] == '0')) {
    return false;
  }
  uint64_t value = 0;
  for (size_t i = 0; i < part.len; i++) {
    if (!ms_ascii_is_digit(part.ptr[i])) {
      return false;
    }
    const uint64_t digit = (uint64_t)(part.ptr[i] - '0');
    if (value > (UINT64_MAX - digit) / 10) {
      return false;
    }
    value = value * 10 + digit;
  }
  *out = value;
  return true;
}

static bool all_digits(MsSpan id) {
  for (size_t i = 0; i < id.len; i++) {
    if (!ms_ascii_is_digit(id.ptr[i])) {
      return false;
    }
  }
  return true;
}

/* A pre-release identifier: ASCII letters, digits and `-`, and no leading zero when numeric. */
static bool identifier(MsSpan id) {
  if (id.len == 0) {
    return false;
  }
  for (size_t i = 0; i < id.len; i++) {
    if (!ms_ascii_is_alnum(id.ptr[i]) && id.ptr[i] != '-') {
      return false;
    }
  }
  return !(all_digits(id) && id.len > 1 && id.ptr[0] == '0');
}

/* Splits `text` at the first `separator`: false when there is none. */
static bool split_once(MsSpan text, uint8_t separator, MsSpan *before, MsSpan *after) {
  for (size_t i = 0; i < text.len; i++) {
    if (text.ptr[i] == separator) {
      *before = ms_span_of(text.ptr, i);
      *after = ms_span_of(text.ptr + i + 1, text.len - i - 1);
      return true;
    }
  }
  return false;
}

/* The pieces of `text` between `separator`s, in the arena. */
static size_t split_all(MsArena *arena, MsSpan text, uint8_t separator, const MsSpan **out) {
  size_t count = 1;
  for (size_t i = 0; i < text.len; i++) {
    count += text.ptr[i] == separator;
  }
  MsSpan *pieces = MS_ARENA_NEW_ARRAY(arena, MsSpan, count);
  size_t start = 0;
  size_t at = 0;
  for (size_t i = 0; i <= text.len; i++) {
    if (i == text.len || text.ptr[i] == separator) {
      pieces[at++] = ms_span_of(text.ptr + start, i - start);
      start = i + 1;
    }
  }
  *out = pieces;
  return count;
}

static bool identifiers(MsArena *arena, MsSpan text, const MsSpan **ids, size_t *count) {
  *count = split_all(arena, text, '.', ids);
  for (size_t i = 0; i < *count; i++) {
    if (!identifier((*ids)[i])) {
      return false;
    }
  }
  return true;
}

bool ms_version_parse(MsArena *arena, MsSpan text, MsVersion *out, MsSpan *why) {
  const char *bad = "%S is not a version; write three numbers such as 1.2.3 (a suffix such as -rc.1 is allowed)";
  MsSpan numbers = text;
  MsSpan pre = {0};
  const bool has_pre = split_once(text, '-', &numbers, &pre);
  const MsSpan *parts = NULL;
  const size_t count = split_all(arena, numbers, '.', &parts);
  MsVersion version = {0};
  if (count != 3 || !number(parts[0], &version.major) || !number(parts[1], &version.minor) ||
      !number(parts[2], &version.patch)) {
    *why = ms_message_format(arena, bad, ms_project_quote(arena, text));
    return false;
  }
  if (has_pre && !identifiers(arena, pre, &version.pre, &version.npre)) {
    *why = ms_message_format(arena, bad, ms_project_quote(arena, text));
    return false;
  }
  *out = version;
  return true;
}

bool ms_version_of_tag(MsArena *arena, MsSpan tag, MsVersion *out) {
  MsSpan why = {0};
  if (tag.len != 0 && tag.ptr[0] == 'v') {
    tag = ms_span_of(tag.ptr + 1, tag.len - 1);
  }
  return ms_version_parse(arena, tag, out, &why);
}

MsBucket ms_version_bucket(const MsVersion *version) {
  if (version->major > 0) {
    return (MsBucket){MS_BUCKET_MAJOR, version->major};
  }
  if (version->minor > 0) {
    return (MsBucket){MS_BUCKET_MINOR, version->minor};
  }
  return (MsBucket){MS_BUCKET_PATCH, version->patch};
}

bool ms_bucket_equal(MsBucket a, MsBucket b) {
  return a.kind == b.kind && a.number == b.number;
}

void ms_bucket_append(MsStrBuild *out, MsBucket bucket) {
  if (bucket.kind == MS_BUCKET_MAJOR) {
    ms_strbuild_printf(out, "%llu.x", (unsigned long long)bucket.number);
  } else if (bucket.kind == MS_BUCKET_MINOR) {
    ms_strbuild_printf(out, "0.%llu.x", (unsigned long long)bucket.number);
  } else {
    ms_strbuild_printf(out, "0.0.%llu", (unsigned long long)bucket.number);
  }
}

static int compare_numbers(uint64_t a, uint64_t b) {
  return a < b ? -1 : a > b;
}

static int compare_spans(MsSpan a, MsSpan b) {
  const size_t common = a.len < b.len ? a.len : b.len;
  const int order = common == 0 ? 0 : __builtin_memcmp(a.ptr, b.ptr, common);
  if (order != 0) {
    return order < 0 ? -1 : 1;
  }
  return compare_numbers(a.len, b.len);
}

/* Numeric identifiers sort before the others and by value; the rest by bytes. A shorter list sorts first. */
static int compare_pre(const MsSpan *a, size_t na, const MsSpan *b, size_t nb) {
  for (size_t i = 0; i < na && i < nb; i++) {
    uint64_t x = 0;
    uint64_t y = 0;
    const bool x_number = all_digits(a[i]) && number(a[i], &x);
    const bool y_number = all_digits(b[i]) && number(b[i], &y);
    int order = 0;
    if (x_number && y_number) {
      order = compare_numbers(x, y);
    } else if (x_number != y_number) {
      order = x_number ? -1 : 1;
    } else {
      order = compare_spans(a[i], b[i]);
    }
    if (order != 0) {
      return order;
    }
  }
  return compare_numbers(na, nb);
}

int ms_version_compare(const MsVersion *a, const MsVersion *b) {
  int order = compare_numbers(a->major, b->major);
  if (order == 0) {
    order = compare_numbers(a->minor, b->minor);
  }
  if (order == 0) {
    order = compare_numbers(a->patch, b->patch);
  }
  if (order != 0) {
    return order;
  }
  if (a->npre == 0 || b->npre == 0) {
    return a->npre == b->npre ? 0 : (a->npre == 0 ? 1 : -1);
  }
  return compare_pre(a->pre, a->npre, b->pre, b->npre);
}

static void append_pre(MsStrBuild *out, const MsSpan *pre, size_t npre) {
  if (npre == 0) {
    return;
  }
  ms_strbuild_append_byte(out, '-');
  for (size_t i = 0; i < npre; i++) {
    if (i != 0) {
      ms_strbuild_append_byte(out, '.');
    }
    ms_strbuild_append(out, pre[i]);
  }
}

void ms_version_append(MsStrBuild *out, const MsVersion *version) {
  ms_strbuild_printf(out, "%llu.%llu.%llu", (unsigned long long)version->major,
                     (unsigned long long)version->minor, (unsigned long long)version->patch);
  append_pre(out, version->pre, version->npre);
}

/* ---- requirements ---- */

static MsSpan requirement_error(MsArena *arena, MsSpan text, const char *why) {
  MsStrBuild message = ms_strbuild_new();
  ms_strbuild_append(&message, ms_project_quote(arena, text));
  ms_strbuild_append_text(&message, " is not a version requirement: ");
  ms_strbuild_append_text(&message, why);
  MsSpan copy = ms_arena_copy(arena, ms_strbuild_span(&message));
  ms_strbuild_free(&message);
  return copy;
}

/* The one to three numbers of a requirement, `minor` and `patch` set when written. */
static bool requirement_numbers(MsArena *arena, MsSpan numbers, MsRequirement *out) {
  const MsSpan *parts = NULL;
  const size_t count = split_all(arena, numbers, '.', &parts);
  uint64_t value[3] = {0, 0, 0};
  if (count > 3) {
    return false;
  }
  for (size_t i = 0; i < count; i++) {
    if (!number(parts[i], &value[i])) {
      return false;
    }
  }
  out->major = value[0];
  out->has_minor = count > 1;
  out->minor = value[1];
  out->has_patch = count > 2;
  out->patch = value[2];
  return true;
}

bool ms_requirement_parse(MsArena *arena, MsSpan text, MsRequirement *out, MsSpan *why) {
  MsRequirement requirement = {.op = MS_REQ_CARET};
  MsSpan rest = text;
  if (text.len != 0 && (text.ptr[0] == '^' || text.ptr[0] == '~' || text.ptr[0] == '=')) {
    requirement.op = text.ptr[0] == '^' ? MS_REQ_CARET : text.ptr[0] == '~' ? MS_REQ_TILDE : MS_REQ_EXACT;
    rest = ms_span_of(text.ptr + 1, text.len - 1);
  }
  MsSpan numbers = rest;
  MsSpan pre = {0};
  const bool has_pre = split_once(rest, '-', &numbers, &pre);
  if (has_pre && !identifiers(arena, pre, &requirement.pre, &requirement.npre)) {
    *why = requirement_error(arena, text, "the suffix after - is not a pre-release name");
    return false;
  }
  if (!requirement_numbers(arena, numbers, &requirement)) {
    *why = requirement_error(arena, text,
                             "write one to three numbers such as 1, 1.2 or 1.2.3, with an optional ^, ~ or =");
    return false;
  }
  if (requirement.npre != 0 && !requirement.has_patch) {
    *why = requirement_error(arena, text, "a pre-release needs all three numbers");
    return false;
  }
  /* A zero major makes the next number the compatibility boundary, so it must be there. */
  if (requirement.major == 0 && !requirement.has_minor) {
    *why = requirement_error(arena, text, "0 alone covers incompatible releases; write 0.4 or 0.4.1");
    return false;
  }
  if (requirement.major == 0 && requirement.has_minor && requirement.minor == 0 && !requirement.has_patch) {
    *why = requirement_error(arena, text, "0.0 alone covers incompatible releases; write 0.0.3");
    return false;
  }
  *out = requirement;
  return true;
}

MsBucket ms_requirement_bucket(const MsRequirement *requirement) {
  if (requirement->major > 0) {
    return (MsBucket){MS_BUCKET_MAJOR, requirement->major};
  }
  if (requirement->has_minor && requirement->minor > 0) {
    return (MsBucket){MS_BUCKET_MINOR, requirement->minor};
  }
  return (MsBucket){MS_BUCKET_PATCH, requirement->has_patch ? requirement->patch : 0};
}

static bool exact_matches(const MsRequirement *requirement, const MsVersion *version, int order_to_floor) {
  if (requirement->has_minor && requirement->has_patch) {
    return order_to_floor == 0;
  }
  if (requirement->has_minor) {
    return version->minor == requirement->minor;
  }
  return true;
}

bool ms_requirement_matches(const MsRequirement *requirement, const MsVersion *version) {
  if (version->npre != 0 && requirement->npre == 0) {
    return false;
  }
  if (!ms_bucket_equal(ms_version_bucket(version), ms_requirement_bucket(requirement))) {
    return false;
  }
  const MsVersion floor = {.major = requirement->major,
                           .minor = requirement->has_minor ? requirement->minor : 0,
                           .patch = requirement->has_patch ? requirement->patch : 0,
                           .pre = requirement->pre,
                           .npre = requirement->npre};
  const int order = ms_version_compare(version, &floor);
  if (order < 0) {
    return false;
  }
  if (requirement->op == MS_REQ_EXACT) {
    return exact_matches(requirement, version, order);
  }
  if (requirement->op == MS_REQ_TILDE) {
    return !requirement->has_minor || version->minor == requirement->minor;
  }
  /* Inside the bucket, a caret on a fully written 0.0.x is that one version. */
  return requirement->major != 0 || !(requirement->has_minor && requirement->minor == 0) || order == 0;
}

void ms_requirement_append(MsStrBuild *out, const MsRequirement *requirement) {
  const char *op = requirement->op == MS_REQ_CARET ? "^" : requirement->op == MS_REQ_TILDE ? "~" : "=";
  ms_strbuild_append_text(out, op);
  ms_strbuild_printf(out, "%llu", (unsigned long long)requirement->major);
  if (requirement->has_minor) {
    ms_strbuild_printf(out, ".%llu", (unsigned long long)requirement->minor);
  }
  if (requirement->has_patch) {
    ms_strbuild_printf(out, ".%llu", (unsigned long long)requirement->patch);
  }
  append_pre(out, requirement->pre, requirement->npre);
}
