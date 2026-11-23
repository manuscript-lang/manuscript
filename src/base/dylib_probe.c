/* A tiny shared library for the unit test of base/dylib.h: it exports one function. */
#if defined(_WIN32)
#define PROBE_EXPORT __declspec(dllexport)
#else
#define PROBE_EXPORT __attribute__((visibility("default")))
#endif

PROBE_EXPORT int ms_dylib_probe_add(int left, int right);

PROBE_EXPORT int ms_dylib_probe_add(int left, int right) {
  return left + right;
}
