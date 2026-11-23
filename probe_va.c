#include <stdarg.h>
#include <stdio.h>
#include <stddef.h>
typedef struct { const char *ptr; size_t len; } Span;
__attribute__((noinline)) static void by_struct(void *arena, const char *fmt, ...) {
  va_list a; va_start(a, fmt); (void)arena; (void)fmt;
  Span s1 = va_arg(a, Span); const char *t = va_arg(a, const char *); Span s2 = va_arg(a, Span); Span s3 = va_arg(a, Span);
  printf("struct/struct: %zu %s %zu %zu\n", s1.len, t, s2.len, s3.len);
  va_end(a);
}
__attribute__((noinline)) static void by_words(void *arena, const char *fmt, ...) {
  va_list a; va_start(a, fmt); (void)arena; (void)fmt;
  const char *p1 = va_arg(a, const char *); size_t l1 = va_arg(a, size_t);
  const char *t = va_arg(a, const char *);
  const char *p2 = va_arg(a, const char *); size_t l2 = va_arg(a, size_t);
  const char *p3 = va_arg(a, const char *); size_t l3 = va_arg(a, size_t);
  (void)p1; (void)p2; (void)p3;
  printf("struct-caller/word-callee: %zu %s %zu %zu\n", l1, t, l2, l3);
  va_end(a);
}
__attribute__((noinline)) static void by_pointer(void *arena, const char *fmt, ...) {
  va_list a; va_start(a, fmt); (void)arena; (void)fmt;
  const Span *s1 = va_arg(a, const Span *); const char *t = va_arg(a, const char *); const Span *s2 = va_arg(a, const Span *); const Span *s3 = va_arg(a, const Span *);
  printf("pointer: %zu %s %zu %zu\n", s1->len, t, s2->len, s3->len);
  va_end(a);
}
int main(void) {
  Span a = {"a", 1}, b = {"bb", 2}, c = {"ccc", 3};
  by_struct(NULL, "x", a, "t", b, c);
  by_words(NULL, "x", a, "t", b, c);
  by_words(NULL, "x", a.ptr, a.len, "t", b.ptr, b.len, c.ptr, c.len);
  by_pointer(NULL, "x", &a, "t", &b, &c);
  return 0;
}
