/* runtime/core/release.c: see release.h. */
#include "runtime/core/release.h"

#include <stddef.h>

#include "base/fatal.h"
#include "runtime/sys/spin.h"

enum { RELEASE_MAX = 16 };

static struct {
  MsSpin lock;
  MsReleaseFn functions[RELEASE_MAX];
  size_t count;
} registry = {.lock = MS_SPIN_INIT};

void ms_release_at_exit(MsReleaseFn release) {
  ms_spin_lock(&registry.lock);
  for (size_t index = 0; index < registry.count; index++) {
    if (registry.functions[index] == release) {
      ms_spin_unlock(&registry.lock);
      return;
    }
  }
  if (registry.count == RELEASE_MAX) {
    ms_spin_unlock(&registry.lock);
    ms_fatal(MS_FATAL_INVARIANT, "too many release functions");
  }
  registry.functions[registry.count++] = release;
  ms_spin_unlock(&registry.lock);
}

void ms_release_run(void) {
  while (true) {
    ms_spin_lock(&registry.lock);
    const MsReleaseFn release = registry.count == 0 ? NULL : registry.functions[--registry.count];
    ms_spin_unlock(&registry.lock);
    if (release == NULL) {
      return;
    }
    release();
  }
}
