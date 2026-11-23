#include <stdarg.h>
#include <stdio.h>
#include <stddef.h>
typedef struct { const char *ptr; size_t len; } Span;
__attribute__((noinline)) static void show(void *arena, const char *fmt, ...) {
  va_list a; va_start(a, fmt); (void)arena; (void)fmt;
  Span s1 = va_arg(a, Span); const char *t = va_arg(a, const char *); Span s2 = va_arg(a, Span); Span s3 = va_arg(a, Span);
  printf("%zu %s %zu %zu\n", s1.len, t, s2.len, s3.len);
  va_end(a);
}
int main(void) {
  Span a = {"a", 1}, b = {"bb", 2}, c = {"ccc", 3};
  show(NULL, "x", a, "t", b, c);
  return 0;
}
