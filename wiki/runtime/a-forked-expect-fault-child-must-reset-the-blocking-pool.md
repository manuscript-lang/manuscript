# A forked `expect_fault` child must reset the blocking pool

Verified (2026-11-12, #3720): `expect_fault` forks, and the child copies the pool's counts (`threads`, `idle`) but none of its threads. A blocking call (`append_file(..).wait()` in a faulting close) then queued a job that nobody ran, and the test hung until its 60 s timeout. The old "every other task is parked" rule ran such calls inline and hid it; five fixtures (`optional-unused-cause-receiver-cleanup`, `list-incoming-resource-transfer`, `source-borrowed-wrapper-temporary-cleanup` and two more) timed out once the rule only counted local-token waiters.

Apply when: code runs in the fork child, or the pool's bookkeeping changes.
Evidence: `glue::pool::reset_after_fork`, called from `fault::isolate_trap_child`; the fixtures above.
Verify: `ms-conform run --id e2e/accept/optional-unused-cause-receiver-cleanup` passes.
