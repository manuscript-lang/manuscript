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

static struct {
  MsSpin lock;
  MsReleaseFn functions[RELEASE_MAX];
  size_t count;
} quiesce_registry = {.lock = MS_SPIN_INIT};

void ms_quiesce_at_thread_exit(MsReleaseFn quiesce) {
  ms_spin_lock(&quiesce_registry.lock);
  for (size_t index = 0; index < quiesce_registry.count; index++) {
    if (quiesce_registry.functions[index] == quiesce) {
      ms_spin_unlock(&quiesce_registry.lock);
      return;
    }
  }
  if (quiesce_registry.count == RELEASE_MAX) {
    ms_spin_unlock(&quiesce_registry.lock);
    ms_fatal(MS_FATAL_INVARIANT, "too many quiesce functions");
  }
  quiesce_registry.functions[quiesce_registry.count++] = quiesce;
  ms_spin_unlock(&quiesce_registry.lock);
}

void ms_quiesce_run(void) {
  ms_spin_lock(&quiesce_registry.lock);
  const size_t count = quiesce_registry.count;
  MsReleaseFn functions[RELEASE_MAX];
  for (size_t index = 0; index < count; index++) {
    functions[index] = quiesce_registry.functions[index];
  }
  ms_spin_unlock(&quiesce_registry.lock);
  for (size_t index = 0; index < count; index++) {
    functions[index]();
  }
}
