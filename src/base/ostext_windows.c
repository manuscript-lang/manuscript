/* Owns the UTF-8 to UTF-16 conversion of Windows paths and command lines (see ostext.h). */
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#define NOGDI
#define NOUSER
#include <windows.h>

#include "base/alloc.h"
#include "base/ostext.h"

enum { LONG_PATH_UNITS = 248 };

static uint16_t *convert(MsSpan span, size_t *units) {
  MsOsText text = ms_os_text_new(span);
  int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.ptr, -1, NULL, 0);
  uint16_t *wide = NULL;
  if (count > 0) {
    wide = ms_alloc((size_t)count * sizeof(uint16_t));
    if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.ptr, -1, (WCHAR *)wide, count) != count) {
      ms_free(wide);
      wide = NULL;
    }
    *units = (size_t)count - 1;
  }
  ms_os_text_free(&text);
  return wide;
}

/* A drive or UNC path of LONG_PATH_UNITS or more units with the extended-length prefix. */
static uint16_t *prefixed(const uint16_t *wide, size_t units, bool unc) {
  static const uint16_t local[] = {'\\', '\\', '?', '\\'};
  static const uint16_t share[] = {'\\', '\\', '?', '\\', 'U', 'N', 'C', '\\'};
  const uint16_t *head = unc ? share : local;
  size_t head_units = unc ? 8 : 4;
  size_t skip = unc ? 2 : 0;
  uint16_t *out = ms_alloc((head_units + units - skip + 1) * sizeof(uint16_t));
  for (size_t index = 0; index < head_units; index++) {
    out[index] = head[index];
  }
  for (size_t index = skip; index < units; index++) {
    out[head_units + index - skip] = wide[index] == '/' ? '\\' : wide[index];
  }
  out[head_units + units - skip] = 0;
  return out;
}

MsOsWide ms_os_wide_new(MsSpan span, bool as_path) {
  size_t units = 0;
  uint16_t *wide = convert(span, &units);
  if (wide == NULL || !as_path || units < LONG_PATH_UNITS) {
    return (MsOsWide){.ptr = wide};
  }
  bool drive = units >= 3 && wide[1] == ':' && (wide[2] == '\\' || wide[2] == '/');
  bool unc = units >= 3 && wide[0] == '\\' && wide[1] == '\\' && wide[2] != '?';
  if (!drive && !unc) {
    return (MsOsWide){.ptr = wide};
  }
  uint16_t *long_path = prefixed(wide, units, unc);
  ms_free(wide);
  return (MsOsWide){.ptr = long_path};
}

void ms_os_wide_free(MsOsWide *text) {
  ms_free(text->ptr);
  text->ptr = NULL;
}
#endif
