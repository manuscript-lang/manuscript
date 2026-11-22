/* `pthread_atfork` for glibc 2.28 on aarch64, whose libc and libpthread export only `__register_atfork`: the glibc
 * headers' `libpthread_nonshared.a` carries the out-of-line copy, which the glibc stubs we link do not. x86-64 needs
 * nothing: its libpthread still exports the name. The null shared-object handle is glibc's own for an executable.
 * Linked into programs only (see glibc_stat.c). */
extern int __register_atfork(void (*prepare)(void), void (*parent)(void), void (*child)(void), void *handle);

int pthread_atfork(void (*prepare)(void), void (*parent)(void), void (*child)(void));
int pthread_atfork(void (*prepare)(void), void (*parent)(void), void (*child)(void)) {
  return __register_atfork(prepare, parent, child, (void *)0);
}
