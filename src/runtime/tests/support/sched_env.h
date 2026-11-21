/* The scheduler's environment for C unit tests that run tasks and promises: a real poll(2) over the descriptors a
 * task waits on, faults that leave through the innermost guard, and no process exit. */
#ifndef MS_TEST_SCHED_ENV_H
#define MS_TEST_SCHED_ENV_H

/* Installs the hooks and the poller on this thread, before the first task (ms_task_run_main). */
void ms_test_sched_install(void);

#endif
