//! Test fakes: replacement closures for functions, by test capture (one per test file) and
//! function index. `fake(original, replacement, body)` pushes the replacement for the length
//! of `body`; a test build routes a faked function through `msrt_fake_has` and `msrt_fake_get`.
//! The table does not own a replacement: it lives in the frame that called `fake`, which pops
//! it before returning.

use ms_rt_abi::Obj;
use std::sync::Mutex;

/// (capture id, function index, replacement closure), innermost last. A flat list: a test
/// holds a handful.
static FAKES: Mutex<Vec<(u64, i64, usize)>> = Mutex::new(Vec::new());

fn lock() -> std::sync::MutexGuard<'static, Vec<(u64, i64, usize)>> {
    FAKES.lock().unwrap_or_else(|e| e.into_inner())
}

/// Makes `closure` the replacement of function `func` for the running task's capture, until
/// the matching `msrt_fake_pop`.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_fake_push(func: i64, closure: *mut Obj) {
    let capture = crate::task::capture();
    lock().push((capture, func, closure as usize));
}

/// Ends the innermost replacement of function `func` for the running task's capture.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_fake_pop(func: i64) {
    let capture = crate::task::capture();
    let mut fakes = lock();
    if let Some(at) = fakes
        .iter()
        .rposition(|(c, f, _)| *c == capture && *f == func)
    {
        fakes.remove(at);
    }
}

fn find(func: i64) -> *mut Obj {
    let capture = crate::task::capture();
    lock()
        .iter()
        .rfind(|(c, f, _)| *c == capture && *f == func)
        .map_or(std::ptr::null_mut(), |e| e.2 as *mut Obj)
}

/// Whether function `func` has a replacement for the running task's capture.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_fake_has(func: i64) -> bool {
    !find(func).is_null()
}

/// The replacement closure of function `func` for the running task's capture, or null. The
/// caller borrows it.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_fake_get(func: i64) -> *mut Obj {
    find(func)
}

/// Forgets every replacement of the running task's capture (a fault left some behind).
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_fake_clear() {
    let capture = crate::task::capture();
    lock().retain(|(c, _, _)| *c != capture);
}
