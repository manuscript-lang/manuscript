/* Owns build_type.h. Port of `BuildType` in crates/ms-cli/src/backend.rs. */
#include "cli/build_type.h"

static const char *const NAMES[] = {"Debug", "Release", "MinSizeRel"};

const char *ms_build_type_name(MsBuildType type) {
  return NAMES[type];
}

static bool equal_ignoring_case(MsSpan text, const char *name) {
  size_t i = 0;
  for (; i < text.len && name[i] != 0; i++) {
    const uint8_t a = text.ptr[i] >= 'A' && text.ptr[i] <= 'Z' ? (uint8_t)(text.ptr[i] + 32) : text.ptr[i];
    const uint8_t b = (uint8_t)name[i] >= 'A' && (uint8_t)name[i] <= 'Z' ? (uint8_t)(name[i] + 32) : (uint8_t)name[i];
    if (a != b) {
      return false;
    }
  }
  return i == text.len && name[i] == 0;
}

bool ms_build_type_parse(MsSpan name, MsBuildType fallback, MsBuildType *out) {
  if (name.len == 0) {
    *out = fallback;
    return true;
  }
  for (int type = MS_BUILD_DEBUG; type <= MS_BUILD_MINSIZEREL; type++) {
    if (equal_ignoring_case(name, NAMES[type])) {
      *out = (MsBuildType)type;
      return true;
    }
  }
  return false;
}
