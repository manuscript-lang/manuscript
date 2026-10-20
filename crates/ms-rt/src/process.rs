//! Process exit and exported process helpers.
use crate::global::Global;
use crate::sys;

/// A native's cleanup that must run when the program ends (restoring the terminal).
static EXIT_HOOK: Global<Option<extern "C" fn()>> = Global::new(None);

/// Registers the one hook that runs after output is flushed and before the process ends.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_process_on_exit(hook: extern "C" fn()) {
    // SAFETY: single threaded runtime state.
    unsafe { *EXIT_HOOK.ptr() = Some(hook) };
}

/// Flushes output, runs the exit hook, writes the profile and terminates the process.
pub fn exit(code: i32) -> ! {
    crate::io::flush_stdout();
    // SAFETY: single threaded runtime state; the hook is taken so it runs once.
    if let Some(hook) = unsafe { (*EXIT_HOOK.ptr()).take() } {
        hook();
    }
    crate::profile::finish();
    // SAFETY: terminating the process.
    unsafe { sys::_exit(code) }
}

#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_process_exit(code: i64) -> ! {
    exit(code as i32)
}
