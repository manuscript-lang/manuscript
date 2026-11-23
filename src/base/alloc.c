/* Owns the allocator hook and the mimalloc default (see alloc.h). */
#include "base/alloc.h"

#include <mimalloc.h>

#include "base/fatal.h"

#ifdef _WIN32
#include <stdint.h>
#include <stdio.h>
#include <windows.h>
/* PROBE (#6274): report who asks for a huge block */
static void probe_huge(size_t size, const char *what) {
  if (size < ((size_t)1 << 40)) {
    return;
  }
  const unsigned long long base = (unsigned long long)(uintptr_t)GetModuleHandleA(NULL);
  (void)fprintf(stderr, "probe-huge %s size=%llu\n", what, (unsigned long long)size);
  CONTEXT context;
  RtlCaptureContext(&context);
  for (int i = 0; i < 16; i++) {
#if defined(__aarch64__)
    const DWORD64 pc = context.Pc;
#else
    const DWORD64 pc = context.Rip;
#endif
    DWORD64 image = 0;
    PRUNTIME_FUNCTION entry = RtlLookupFunctionEntry(pc, &image, NULL);
    (void)fprintf(stderr, "probe-frame 0x%llx entry=%d\n", (unsigned long long)pc - base, entry != NULL);
    if (entry == NULL) {
      break;
    }
    PVOID handler_data = NULL;
    DWORD64 establisher = 0;
    (void)RtlVirtualUnwind(0, image, pc, entry, &context, &handler_data, &establisher, NULL);
  }
}
#else
static void probe_huge(size_t size, const char *what) { (void)size; (void)what; }
#endif

/* The one other mutable global of base besides the fatal handler: set once before threads. */
static const MsAllocator *installed = NULL;

static void *mimalloc_allocate(size_t size) {
  return mi_malloc(size);
}
static void *mimalloc_reallocate(void *block, size_t size) {
  return mi_realloc(block, size);
}
static void mimalloc_release(void *block) {
  mi_free(block);
}

static const MsAllocator mimalloc_allocator = {mimalloc_allocate, mimalloc_reallocate, mimalloc_release};

static const MsAllocator *current(void) {
  return installed != NULL ? installed : &mimalloc_allocator;
}

static void *checked(void *block) {
  if (block == NULL) {
    ms_fatal(MS_FATAL_OUT_OF_MEMORY, "out of memory");
  }
  return block;
}

void ms_alloc_install(const MsAllocator *allocator) {
  installed = allocator;
}

void *ms_alloc(size_t size) {
  probe_huge(size, "alloc");
  return checked(current()->allocate(size));
}

void *ms_alloc_zeroed(size_t size) {
  void *block = ms_alloc(size);
  __builtin_memset(block, 0, size);
  return block;
}

void *ms_realloc(void *block, size_t size) {
  probe_huge(size, "realloc");
  return checked(block == NULL ? current()->allocate(size) : current()->reallocate(block, size));
}

void ms_free(void *block) {
  if (block != NULL) {
    current()->release(block);
  }
}
