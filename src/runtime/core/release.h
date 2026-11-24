/* runtime/core/release.h: what a module that holds process-wide state frees when the process asks for its books to
 * balance (MS_FREE_AT_EXIT, for a leak check).
 *
 * A module registers its release function the first time it makes that state. The process entry therefore never
 * names a module, and a program that never touches the module does not link it: before this, the entry called every
 * module's release function, which linked the HTTP client, TLS and BigInt code into a program that only prints. */
#ifndef MS_RUNTIME_CORE_RELEASE_H
#define MS_RUNTIME_CORE_RELEASE_H

typedef void (*MsReleaseFn)(void);

/* Registers `release` to run once at exit, after the functions registered later. A function already registered is
 * not added again. Callable from any thread. */
void ms_release_at_exit(MsReleaseFn release);

/* Runs the registered functions, the newest first, and forgets them. */
void ms_release_run(void);

/* Registers `quiesce` to run on each worker thread just before it ends, once its tasks are gone. A module whose
 * helper thread frees blocks that a worker allocated registers a function that waits until the helper has freed
 * everything submitted so far: a block freed after its allocating thread ended stays counted live by the allocator, which
 * the leak check reads as a leak. A function already registered is not added again. Callable from any thread. */
void ms_quiesce_at_thread_exit(MsReleaseFn quiesce);

/* Runs the registered functions on the calling thread. */
void ms_quiesce_run(void);

#endif
