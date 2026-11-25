/* compiler/project/package.c: package specs and the lock file. */
#include "compiler/project/package.h"

#include "base/message.h"
#include "compiler/project/project_internal.h"

bool ms_package_is_hex(MsSpan text, size_t len) {
  if (text.len != len) {
    return false;
  }
  for (size_t i = 0; i < text.len; i++) {
    const uint8_t b = text.ptr[i];
    if (!((b >= '0' && b <= '9') || (b >= 'a' && b <= 'f'))) {
      return false;
    }
  }
  return true;
}

static bool has_byte(MsSpan text, const char *set) {
  for (size_t i = 0; i < text.len; i++) {
    for (const char *c = set; *c != 0; c++) {
      if (text.ptr[i] == (uint8_t)*c) {
        return true;
      }
    }
  }
  return false;
}

static bool is_space_or_control(MsSpan text) {
  for (size_t i = 0; i < text.len; i++) {
    const uint8_t b = text.ptr[i];
    if (b <= 0x20 || b == 0x7f) {
      return true; /* a space and the controls, which includes every ASCII whitespace */
    }
  }
  return false;
}

bool ms_package_check_spec(MsArena *arena, MsSpan spec, MsSpan *why) {
  size_t hash = 0;
  const bool split = ms_span_find_byte(spec, '#', &hash);
  const MsSpan url = split ? ms_span_of(spec.ptr, hash) : spec;
  const MsSpan tag = split ? ms_span_of(spec.ptr + hash + 1, spec.len - hash - 1) : (MsSpan){0};
  if (!split || url.len == 0 || tag.len == 0 || is_space_or_control(spec)) {
    *why = ms_message_format(arena,
                             "invalid dependency %S; write \"<git url>#<tag or commit>\", for example "
                             "\"https://github.com/acme/pg.git#v1.0.0\"",
                             ms_project_quote(arena, spec));
    return false;
  }
  if (!ms_span_starts_with_text(url, "https://") && !ms_span_starts_with_text(url, "file://")) {
    *why = ms_message_format(arena,
                             "dependency URL %S must start with https:// (or file:// for a local repository); other "
                             "git transports are not supported",
                             ms_project_quote(arena, url));
    return false;
  }
  size_t unused = 0;
  const bool dots = ms_span_find(tag, ms_span_of_text(".."), &unused);
  if (tag.ptr[0] == '-' || dots || has_byte(tag, "~^:?*[\\") || tag.ptr[0] == '/' || tag.ptr[tag.len - 1] == '/') {
    *why = ms_message_format(arena, "dependency tag %S is not a plain tag name or full commit",
                             ms_project_quote(arena, tag));
    return false;
  }
  return true;
}
