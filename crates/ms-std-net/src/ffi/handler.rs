//! The compiled-handler side of `@std/http.ms` servers: the fault-isolating guard and the
//! dispatcher that calls into compiled code.

use super::ExchH;
use super::http_client::http_from_code;
use crate::error::HttpErr;
use crate::http::exchange::Exchange;
use crate::http::server::{Dispatch, Outcome};
use ms_rt::ffi::{Handler, IntoAbi, Object, str_ref, str_release};
use ms_rt_abi::{Obj, StrVal};
use std::rc::Rc;

use ms_rt::fault::msrt_guard_call;
use ms_rt::obj::msrt_release;

/// A string slot no one has written: the null string a thunk leaves when it reports no message.
const NO_MESSAGE: StrVal = StrVal::literal(std::ptr::null_mut(), 0);

/// Exchange handler: `fn(exchange: HttpExchange) Result[Unit, HttpError]`. The
/// exchange handle is +1 for the thunk; the result is an `HttpError` status
/// (`Failed` text through `err`).
pub type StreamThunk =
    unsafe extern "C" fn(env: *mut Obj, exchange: *mut Obj, err: *mut StrVal) -> u8;

// ---------------------------------------------------------------------- server

/// The program's handler behind the server.
pub struct Program {
    env: *mut Obj,
    streaming: StreamThunk,
}

impl Drop for Program {
    fn drop(&mut self) {
        // SAFETY: `env` is the closure reference the native took when serving began.
        unsafe { msrt_release(self.env) }
    }
}

/// Runs one request under `msrt_guard_call`. `None` means it returned normally;
/// otherwise the outcome that ends the request (a fault becomes a 500 for the caller).
/// Values owned by the abandoned frames leak, per the ms-rt contract: `msrt_unwind_drops` is
/// false for a fault, and the unwind pass registers no cleanup around the leaf calls (index,
/// unwrap, arithmetic) that fault. Documented on `Network.serve`.
fn guarded<T>(mut call: impl FnMut()) -> Option<Outcome<T>> {
    unsafe extern "C-unwind" fn run(data: *mut u8) {
        // SAFETY: `data` is the `&mut dyn FnMut()` below, live for the guard call.
        unsafe { (*data.cast::<&mut dyn FnMut()>())() };
    }
    let mut dynamic: &mut dyn FnMut() = &mut call;
    let mut message = NO_MESSAGE;
    // SAFETY: `run` and its data outlive the call; `message` is written only on a fault.
    let status = unsafe { msrt_guard_call(run, (&raw mut dynamic).cast(), &mut message) };
    match status {
        0 => None,
        2 => {
            // The task goes on to answer the request: a cancel aimed at it ends with the handler.
            ms_rt::scope::acknowledge_cancel();
            Some(Outcome::Cancelled)
        }
        _ => {
            let text = if message.ptr_word.is_null() && message.is_static() {
                "fault".to_string()
            } else {
                // SAFETY: the guard hands over an owned string, released once here.
                let text = unsafe { str_ref(&message) }.to_string();
                // SAFETY: as above.
                unsafe { str_release(&message) };
                text
            };
            Some(Outcome::Fault(text))
        }
    }
}

impl Dispatch for Program {
    fn streaming(&self, exchange: Rc<Exchange>) -> Outcome<Result<(), HttpErr>> {
        let thunk = self.streaming;
        let mut message = NO_MESSAGE;
        // SAFETY: the thunk borrows the exchange handle (it takes its own reference for the
        // handler); the status and optional message string come back owned.
        let mut status = 0;
        let handle = Object(ExchH(exchange)).into_raw().cast();
        // SAFETY: the thunk contract; the handle is live for the call.
        let call = || status = unsafe { thunk(self.env, handle, &mut message) };
        let stop = guarded(call);
        // SAFETY: the handle created above is released once, after the thunk returned or its
        // frames were abandoned; the frames' own references leak, but this one need not.
        unsafe { msrt_release(handle) };
        if let Some(stop) = stop {
            return stop;
        }
        let text = if message.ptr_word.is_null() && message.is_static() {
            String::new()
        } else {
            // SAFETY: an owned string from the thunk.
            let text = unsafe { str_ref(&message) }.to_string();
            // SAFETY: as above; the string is released once, after copying.
            unsafe { str_release(&message) };
            text
        };
        Outcome::Done(match status {
            0 => Ok(()),
            code => Err(http_from_code(code, text)),
        })
    }
}

impl Program {
    /// A program that hands each exchange to the streaming handler `env` (a reference is taken).
    pub fn streaming(env: &Handler) -> Box<Program> {
        let env = env.as_ptr();
        // SAFETY: the compiler built `env` as a `fn(HttpExchange) Result[Unit, HttpError]`
        // closure, whose code word is a `StreamThunk`; `env` is live for the call.
        unsafe {
            Box::new(Program {
                env: retained(env),
                streaming: closure_code(env),
            })
        }
    }
}

/// The code word of a closure object: `Closure { hdr, code @16, .. }` (`ms-rt/ABI.md` §6).
///
/// # Safety
/// `env` is a live closure whose code has the signature `T`.
unsafe fn closure_code<T: Copy>(env: *mut Obj) -> T {
    const { assert!(size_of::<T>() == size_of::<usize>()) };
    // SAFETY: caller contract; the code word follows the 16-byte header.
    unsafe { std::mem::transmute_copy(&*env.cast::<usize>().add(2)) }
}

/// Takes a reference to `env` for the server.
///
/// # Safety
/// `env` is a live object.
unsafe fn retained(env: *mut Obj) -> *mut Obj {
    // SAFETY: caller contract.
    unsafe {
        use ms_rt::obj::msrt_retain;
        msrt_retain(env);
    }
    env
}

#[cfg(test)]
mod tests {
    use super::*;

    use ms_rt::fault::msrt_fault;

    #[test]
    fn a_faulting_handler_is_isolated() {
        let faulted = guarded::<()>(|| {
            // SAFETY: a fault with a static message; the guard catches it.
            unsafe { msrt_fault(b"boom".as_ptr(), 4) }
        });
        assert!(matches!(faulted, Some(Outcome::Fault(m)) if m.contains("boom")));
        // The guard is reusable and later calls still run.
        assert!(guarded::<()>(|| {}).is_none());
    }
}
