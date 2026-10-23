//! The compiled-handler side of `@std/http.ms` servers: wire records for the buffered handler
//! thunk, the fault-isolating guard, and the dispatcher that calls into compiled code.

use super::http_client::http_from_code;
use super::{ExchH, HeadersH};
use crate::error::HttpErr;
use crate::http::exchange::Exchange;
use crate::http::headers::Headers;
use crate::http::server::{Dispatch, Outcome, Reply, Request as ServerRequest};
use ms_rt_abi::{Obj, StrVal, VecVal};
use ms_std_core::{
    FromAbi, Handler, IntoAbi, ObjRef, Object, bytes_ref, new_string, str_ref, str_release,
    write_bytes,
};
use std::cell::RefCell;
use std::rc::Rc;

unsafe extern "C" {
    fn msrt_guard_call(
        code: unsafe extern "C-unwind" fn(*mut u8),
        data: *mut u8,
        msg_out: *mut StrVal,
    ) -> u8;
    fn msrt_free(p: *mut u8);
    fn msrt_release(o: *mut Obj);
}

/// A string slot no one has written: the null string a thunk leaves when it reports no message.
const NO_MESSAGE: StrVal = StrVal::literal(std::ptr::null_mut(), 0);

// ------------------------------------------------------------------ wire types

/// Request handed to a buffered handler thunk; every field is owned (+1) by the
/// thunk.
#[repr(C)]
pub struct RequestWire {
    pub method: StrVal,
    pub path: StrVal,
    pub query: StrVal,
    pub protocol: StrVal,
    /// `HttpHeaders` handle.
    pub headers: *mut Obj,
    /// `Bytes`.
    pub body: VecVal,
}

/// Response a buffered handler thunk fills in; the native takes ownership.
#[repr(C)]
pub struct ResponseWire {
    pub status: i64,
    /// `HttpHeaders` handle.
    pub headers: *mut Obj,
    /// `Bytes`.
    pub body: VecVal,
}

/// Buffered handler: `fn(request: HttpRequest) HttpResponse` called through a
/// compiler-generated thunk with the closure as `env`.
pub type BufferedThunk =
    unsafe extern "C" fn(env: *mut Obj, req: *mut RequestWire, resp: *mut ResponseWire);

/// Streaming handler: `fn(exchange: HttpExchange) Result[Unit, HttpError]`. The
/// exchange handle is +1 for the thunk; the result is an `HttpError` status
/// (`Failed` text through `err`).
pub type StreamThunk =
    unsafe extern "C" fn(env: *mut Obj, exchange: *mut Obj, err: *mut StrVal) -> u8;

// --------------------------------------------------------------------- helpers

/// Moves a `Bytes` value into a `Vec`, freeing its buffer.
///
/// # Safety
/// `v` is an owned `Bytes` value that is not used afterwards.
unsafe fn take_bytes(v: &VecVal) -> Vec<u8> {
    // SAFETY: caller contract; the buffer came from `msrt_alloc`.
    unsafe {
        let data = bytes_ref(v).to_vec();
        if !v.ptr.is_null() {
            msrt_free(v.ptr);
        }
        data
    }
}

fn headers_handle(h: Headers) -> *mut Obj {
    Object(HeadersH(Rc::new(RefCell::new(h)))).into_raw().cast()
}

/// # Safety
/// `o` is a live `HttpHeaders` handle.
unsafe fn shared<'a>(o: *const Obj) -> ObjRef<'a, HeadersH> {
    // SAFETY: caller contract.
    unsafe { <ObjRef<HeadersH> as FromAbi>::from_raw(o.cast()) }
}

// ---------------------------------------------------------------------- server

/// The program's handler behind the server.
pub struct Program {
    env: *mut Obj,
    buffered: Option<BufferedThunk>,
    streaming: Option<StreamThunk>,
}

impl Drop for Program {
    fn drop(&mut self) {
        // SAFETY: `env` is the closure reference the native took when serving began.
        unsafe { msrt_release(self.env) }
    }
}

/// Runs one request under `msrt_guard_call`. `None` means it returned normally;
/// otherwise the outcome that ends the request (a fault becomes a 500 for the caller).
/// Values owned by the abandoned frames leak, per the ms-rt contract.
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
        2 => Some(Outcome::Cancelled),
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
    fn buffered(&self, request: ServerRequest) -> Outcome<Reply> {
        let Some(thunk) = self.buffered else {
            return Outcome::Fault("no handler".into());
        };
        let mut body = std::mem::MaybeUninit::<VecVal>::uninit();
        // SAFETY: each wire field is initialised before the thunk runs and owned by it
        // afterwards; the response is read back and released below.
        unsafe {
            write_bytes(body.as_mut_ptr(), &request.body);
            let mut req = RequestWire {
                method: new_string(&request.method),
                path: new_string(&request.path),
                query: new_string(&request.query),
                protocol: new_string(request.protocol),
                headers: headers_handle(request.headers),
                body: body.assume_init(),
            };
            let mut resp = ResponseWire {
                status: 0,
                headers: std::ptr::null_mut(),
                body: VecVal {
                    ptr: std::ptr::null_mut(),
                    len: 0,
                    cap: 0,
                },
            };
            if let Some(stop) = guarded(|| thunk(self.env, &mut req, &mut resp)) {
                return stop;
            }
            let headers = if resp.headers.is_null() {
                Headers::new()
            } else {
                let h = shared(resp.headers).borrow().clone();
                msrt_release(resp.headers);
                h
            };
            Outcome::Done(Reply {
                status: resp.status,
                headers,
                body: take_bytes(&resp.body),
            })
        }
    }

    fn streaming(&self, exchange: Rc<Exchange>) -> Outcome<Result<(), HttpErr>> {
        let Some(thunk) = self.streaming else {
            return Outcome::Fault("no handler".into());
        };
        let mut message = NO_MESSAGE;
        // SAFETY: the thunk borrows the exchange handle (it takes its own reference for the
        // handler); the status and optional message string come back owned.
        let mut status = 0;
        let handle = Object(ExchH(exchange)).into_raw().cast();
        // SAFETY: the thunk contract; the handle is live for the call.
        let call = || status = unsafe { thunk(self.env, handle, &mut message) };
        if let Some(stop) = guarded(call) {
            return stop;
        }
        // SAFETY: the handle created above is released once, after the thunk returned.
        unsafe { msrt_release(handle) };
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
    /// A program that answers each request with the buffered handler `env` (a reference is taken).
    pub fn buffered(env: &Handler) -> Box<Program> {
        let env = env.as_ptr();
        // SAFETY: the compiler built `env` as a `fn(HttpRequest) HttpResponse` closure, whose
        // code word is a `BufferedThunk`; `env` is live for the call.
        unsafe {
            Box::new(Program {
                env: retained(env),
                buffered: Some(closure_code(env)),
                streaming: None,
            })
        }
    }

    /// A program that hands each exchange to the streaming handler `env` (a reference is taken).
    pub fn streaming(env: &Handler) -> Box<Program> {
        let env = env.as_ptr();
        // SAFETY: the compiler built `env` as a `fn(HttpExchange) Result[Unit, HttpError]`
        // closure, whose code word is a `StreamThunk`; `env` is live for the call.
        unsafe {
            Box::new(Program {
                env: retained(env),
                buffered: None,
                streaming: Some(closure_code(env)),
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
        unsafe extern "C" {
            fn msrt_retain(o: *mut Obj);
        }
        msrt_retain(env);
    }
    env
}

#[cfg(test)]
mod tests {
    use super::*;

    unsafe extern "C" {
        fn msrt_fault(msg: *const u8, len: usize) -> !;
    }

    unsafe extern "C" fn thunk(_env: *mut Obj, req: *mut RequestWire, resp: *mut ResponseWire) {
        // SAFETY: the dispatcher passes live wires; the path string is owned by us.
        unsafe {
            if str_ref(&(*req).path) == "/boom" {
                msrt_fault(b"boom".as_ptr(), 4);
            }
            (*resp).status = 204;
        }
    }

    fn request(path: &str) -> ServerRequest {
        ServerRequest {
            method: "GET".into(),
            path: path.into(),
            query: String::new(),
            headers: Headers::new(),
            body: Vec::new(),
            protocol: "HTTP/1.1",
        }
    }

    #[test]
    fn a_faulting_handler_is_isolated() {
        let program = Program {
            env: std::ptr::null_mut(),
            buffered: Some(thunk),
            streaming: None,
        };
        let faulted = program.buffered(request("/boom"));
        assert!(matches!(faulted, Outcome::Fault(m) if m.contains("boom")));
        // The guard is reusable and later requests still run.
        let ok = program.buffered(request("/ok"));
        assert!(matches!(ok, Outcome::Done(r) if r.status == 204));
        std::mem::forget(program);
    }
}
