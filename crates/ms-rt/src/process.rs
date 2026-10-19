//! Process exit and exported process helpers.
use crate::sys;

/// Flushes output, writes the profile and terminates the process.
pub fn exit(code: i32) -> ! {
    crate::io::flush_stdout();
    crate::profile::finish();
    // SAFETY: terminating the process.
    unsafe { sys::_exit(code) }
}

#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_process_exit(code: i64) -> ! {
    exit(code as i32)
}
