//! Process exit and exported process helpers.
use crate::global::Process;
use crate::sys;

/// Natives' cleanups that must run when the program ends (restoring the terminal, releasing the
/// shared standard-input handle), in registration order.
static EXIT_HOOKS: Process<[Option<extern "C" fn()>; 4]> = Process::new([None; 4]);

/// Registers a hook that runs after output is flushed and before the process ends, whether
/// `main` returns or the program exits. A registered hook stays registered; past four, later
/// registrations are ignored.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_process_on_exit(hook: extern "C" fn()) {
    // SAFETY: single threaded runtime state.
    let hooks = unsafe { &mut *EXIT_HOOKS.ptr() };
    if let Some(free) = hooks.iter_mut().find(|h| h.is_none()) {
        *free = Some(hook);
    }
}

/// Runs the exit hooks once each.
pub fn run_exit_hooks() {
    for i in 0..4 {
        // SAFETY: single threaded runtime state; each hook is taken so it runs once, and a hook
        // that registers another sees no outstanding borrow.
        if let Some(hook) = unsafe { (*EXIT_HOOKS.ptr())[i].take() } {
            hook();
        }
    }
}

/// Flushes output, runs the exit hooks, writes the profile and terminates the process.
pub fn exit(code: i32) -> ! {
    crate::io::flush_stdout();
    run_exit_hooks();
    crate::profile::finish();
    // SAFETY: terminating the process.
    unsafe { sys::_exit(code) }
}

#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_process_exit(code: i64) -> ! {
    exit(code as i32)
}
