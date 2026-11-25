// conform: tags=testing,tier-core
// conform: phase=check
extern fn msrt_task_current() Int

export fn main() Int {
	msrt_task_current()
	return 0
}
// expect-error: MS3000 3:1 extern fn msrt_task_current names a runtime-internal symbol; msrt_ and msstd_ natives are reserved for bundled standard modules, so call the standard library instead
