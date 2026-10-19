//! Shims for `@std/http.ms` and the HTTP entry points of `@std/net.ms`.

use super::net::network;
use super::{finish, handle_ref, new_handle, opt};
use crate::error::{HttpErr, IoErr, Status};
use crate::http::client::{
    self, Body, Client, ClientOptions, Request, ResponseBody, Source, outgoing_headers,
    valid_method,
};
use crate::http::exchange::Exchange;
use crate::http::headers::{Headers, Shared};
use crate::http::server::{
    CloseError, Dispatch, Limits, Options, Outcome, Reply, Request as ServerRequest, Server,
};
use crate::http::url;
use crate::tls::{self, TlsOptions};
use crate::wait::Deadline;
use ms_rt_abi::{Obj, StrObj, VecVal};
use ms_std_core::{
    bytes_ref, desc_bytes, fault, new_string, read_string_list, str_ref, write_bytes,
    write_string_list,
};
use std::cell::RefCell;
use std::rc::Rc;
use std::time::Duration;

use super::tls::TlsOptionsWire;

unsafe extern "C" {
    fn msrt_guard_call(
        code: unsafe extern "C-unwind" fn(*mut u8),
        data: *mut u8,
        msg_out: *mut *mut StrObj,
    ) -> u8;
    fn msrt_free(p: *mut u8);
    fn msrt_release(o: *mut Obj);
    fn msrt_list_new(out: *mut VecVal);
    fn msrt_list_push(v: *mut VecVal, d: *const ms_rt_abi::TypeDesc, e: *const u8);
}

type ClientRef = Rc<Client>;
type BodyRef = Rc<ResponseBody>;
type ServerRef = Rc<Server>;
type ExchangeRef = Rc<Exchange>;

// ------------------------------------------------------------------ wire types

/// Flattened `Optional[Int]` / `Optional[Duration]` record field.
#[repr(C)]
pub struct OptWire {
    pub present: u8,
    pub value: i64,
}

impl OptWire {
    fn get(&self) -> Option<i64> {
        opt(self.present, self.value)
    }

    pub fn present_value(&self) -> Option<i64> {
        self.get()
    }
}

/// `HttpClientOptions` as the compiler lays it out for natives.
#[repr(C)]
pub struct HttpClientOptionsWire {
    pub max_redirects: OptWire,
    pub max_idle_connections: OptWire,
    pub max_header_bytes: OptWire,
    pub idle_timeout: OptWire,
    pub decompress: u8,
    pub cookies: u8,
    pub tls: TlsOptionsWire,
}

/// `HttpServerOptions` as the compiler lays it out for natives.
#[repr(C)]
pub struct HttpServerOptionsWire {
    pub max_requests: OptWire,
    pub max_body_bytes: OptWire,
    pub max_response_bytes: OptWire,
    pub max_header_bytes: OptWire,
    pub timeout: OptWire,
    pub grace: OptWire,
    /// `Optional[TlsOptions]`: `tls` is meaningful only when this is nonzero.
    pub tls_present: u8,
    pub tls: TlsOptionsWire,
}

/// Request handed to a buffered handler thunk; every field is owned (+1) by the
/// thunk.
#[repr(C)]
pub struct RequestWire {
    pub method: *mut StrObj,
    pub path: *mut StrObj,
    pub query: *mut StrObj,
    pub protocol: *mut StrObj,
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

/// A buffered response with its metadata (`ClientResponse`).
#[repr(C)]
pub struct ClientResponseWire {
    pub status: i64,
    pub headers: *mut Obj,
    pub protocol: *mut StrObj,
    pub body: VecVal,
}

/// `HttpResponseMetadata`.
#[repr(C)]
pub struct MetadataWire {
    pub status: i64,
    pub headers: *mut Obj,
    pub protocol: *mut StrObj,
}

/// Buffered handler: `fn(request: HttpRequest) HttpResponse` called through a
/// compiler-generated thunk with the closure as `env`.
pub type BufferedThunk =
    unsafe extern "C" fn(env: *mut Obj, req: *mut RequestWire, resp: *mut ResponseWire);

/// Streaming handler: `fn(exchange: HttpExchange) Result[Unit, HttpError]`. The
/// exchange handle is +1 for the thunk; the result is an `HttpError` status
/// (`Failed` text through `err`).
pub type StreamThunk =
    unsafe extern "C" fn(env: *mut Obj, exchange: *mut Obj, err: *mut *mut StrObj) -> u8;

/// A `ReadStream` borrowed for an upload: `read` follows the `Connection.read`
/// convention of `ABI.md` (`IoError` status).
#[repr(C)]
pub struct StreamWire {
    pub data: *mut u8,
    pub read: unsafe extern "C" fn(
        data: *mut u8,
        has_max: u8,
        max: i64,
        out: *mut VecVal,
        present: *mut u8,
        err: *mut *mut StrObj,
    ) -> u8,
}

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
    new_handle::<Shared>(Rc::new(RefCell::new(h)))
}

fn shared_handle(h: Shared) -> *mut Obj {
    new_handle::<Shared>(h)
}

/// # Safety
/// `o` is a live `HttpHeaders` handle.
unsafe fn shared<'a>(o: *const Obj) -> &'a Shared {
    // SAFETY: caller contract.
    unsafe { handle_ref::<Shared>(o) }
}

/// A negative limit is invalid; `None` is unlimited.
fn limit(v: Option<i64>) -> Result<Option<u64>, ()> {
    match v {
        Some(n) if n < 0 => Err(()),
        Some(n) => Ok(Some(n as u64)),
        None => Ok(None),
    }
}

fn http_code(e: &HttpErr) -> u8 {
    e.code()
}

fn http_from_code(status: u8, failed: String) -> HttpErr {
    match status {
        1 => HttpErr::InvalidInput,
        2 => HttpErr::InvalidData,
        3 => HttpErr::LimitExceeded,
        4 => HttpErr::PermissionDenied,
        5 => HttpErr::Closed,
        6 => HttpErr::Timeout,
        _ => HttpErr::Failed(failed),
    }
}

// ---------------------------------------------------------------------- errors

/// `Error.message()` of `HttpError`.
///
/// # Safety
/// `failed` is null or a live string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_http_error_message(status: u8, failed: *const StrObj) -> *mut StrObj {
    let text = if failed.is_null() {
        String::new()
    } else {
        // SAFETY: caller contract.
        unsafe { str_ref(failed) }.to_string()
    };
    new_string(&http_from_code(status, text).message())
}

// --------------------------------------------------------------------- headers

/// `headers() -> HttpHeaders` (+1).
#[unsafe(no_mangle)]
pub extern "C" fn msrt_http_headers_new() -> *mut Obj {
    headers_handle(Headers::new())
}

/// `HttpHeaders.append(name, value: Bytes) -> Result[Unit, HttpError]`.
///
/// # Safety
/// Pointers per `ABI.md`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_http_headers_append(
    h: *const Obj,
    name: *const StrObj,
    value: *const VecVal,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        match shared(h)
            .borrow_mut()
            .append(str_ref(name), bytes_ref(value))
        {
            Ok(()) => 0,
            Err(e) => http_code(&e),
        }
    }
}

/// `HttpHeaders.values(name) -> Optional[List[Bytes]]`: an owned copy of the list.
///
/// # Safety
/// Pointers per `ABI.md`; `out` is writable.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_http_headers_values(
    h: *const Obj,
    name: *const StrObj,
    out: *mut VecVal,
    present: *mut u8,
) {
    // SAFETY: caller contract; each element is moved into the list by the push.
    unsafe {
        let headers = shared(h).borrow();
        let Some(values) = headers.values(str_ref(name)) else {
            *present = 0;
            return;
        };
        *present = 1;
        msrt_list_new(out);
        for value in values {
            let mut element = std::mem::MaybeUninit::<VecVal>::uninit();
            write_bytes(element.as_mut_ptr(), value);
            msrt_list_push(out, desc_bytes(), element.as_ptr().cast());
        }
    }
}

/// `HttpHeaders.text(name) -> Result[Optional[List[String]], HttpError]`.
///
/// # Safety
/// Pointers per `ABI.md`; `out` is writable.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_http_headers_text(
    h: *const Obj,
    name: *const StrObj,
    out: *mut VecVal,
    present: *mut u8,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        match shared(h).borrow().text(str_ref(name)) {
            Ok(Some(values)) => {
                *present = 1;
                write_string_list(out, values);
                0
            }
            Ok(None) => {
                *present = 0;
                0
            }
            Err(e) => http_code(&e),
        }
    }
}

/// `HttpHeaders.names() -> List[String]`.
///
/// # Safety
/// `out` is writable.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_http_headers_names(h: *const Obj, out: *mut VecVal) {
    // SAFETY: caller contract.
    unsafe { write_string_list(out, shared(h).borrow().names()) }
}

/// `HttpHeaders.remove(name) -> Bool`.
///
/// # Safety
/// Pointers per `ABI.md`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_http_headers_remove(h: *const Obj, name: *const StrObj) -> u8 {
    // SAFETY: caller contract.
    unsafe { u8::from(shared(h).borrow_mut().remove(str_ref(name))) }
}

/// `HttpHeaders.clone() -> HttpHeaders` (+1): separate membership.
///
/// # Safety
/// `h` is a live headers handle.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_http_headers_clone(h: *const Obj) -> *mut Obj {
    // SAFETY: caller contract.
    unsafe { headers_handle(shared(h).borrow().clone()) }
}

// ---------------------------------------------------------------------- client

fn client_options(w: &HttpClientOptionsWire) -> Result<ClientOptions, HttpErr> {
    let bad = |_| HttpErr::InvalidInput;
    let max_idle = limit(w.max_idle_connections.get()).map_err(bad)?;
    let max_header = limit(w.max_header_bytes.get()).map_err(bad)?;
    let max_redirects = limit(w.max_redirects.get()).map_err(bad)?;
    let idle_timeout = limit(w.idle_timeout.get()).map_err(bad)?;
    // SAFETY: the wire record is live for the call.
    let tls = unsafe { tls_options(&w.tls) };
    Ok(ClientOptions {
        max_redirects,
        max_idle,
        max_header_bytes: max_header,
        idle_timeout: idle_timeout.map(Duration::from_nanos),
        decompress: w.decompress != 0,
        cookies: w.cookies != 0,
        tls,
    })
}

/// # Safety
/// `w` holds live strings and a live list.
unsafe fn tls_options(w: &TlsOptionsWire) -> TlsOptions {
    // SAFETY: caller contract.
    unsafe {
        TlsOptions {
            server_name: str_ref(w.server_name).to_string(),
            roots_pem: str_ref(w.roots_pem).to_string(),
            certificate_pem: str_ref(w.certificate_pem).to_string(),
            private_key_pem: str_ref(w.private_key_pem).to_string(),
            alpn: read_string_list(w.alpn)
                .into_iter()
                .map(str::to_string)
                .collect(),
            require_client_certificate: w.require_client_certificate != 0,
        }
    }
}

/// `Network.http_client(options) -> Result[HttpClient, HttpError]`.
///
/// # Safety
/// Pointers per `ABI.md`; `opts` is a live `HttpClientOptionsWire`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_net_network_http_client(
    net: *const Obj,
    opts: *const HttpClientOptionsWire,
    out: *mut *mut Obj,
    err: *mut *mut StrObj,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        let result = client_options(&*opts).and_then(|o| Client::new(network(net), o));
        finish(result, err, |c| *out = new_handle::<ClientRef>(c))
    }
}

/// `HttpClient.close()`.
///
/// # Safety
/// `c` is a live client handle.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_http_client_close(c: *const Obj) {
    // SAFETY: caller contract.
    unsafe { handle_ref::<ClientRef>(c).close() }
}

struct Call {
    method: String,
    url: url::Url,
    headers: Vec<(String, Vec<u8>)>,
    max_response: u64,
    deadline: Deadline,
}

/// Validates the arguments every request shares, in Go's order.
///
/// # Safety
/// Pointers per `ABI.md`.
unsafe fn prepare(
    owner: &crate::net::Network,
    method: *const StrObj,
    address: *const StrObj,
    headers: *const Obj,
    max: Option<i64>,
    timeout: Option<i64>,
    check_policy: bool,
) -> Result<Call, HttpErr> {
    // SAFETY: caller contract.
    unsafe {
        let max = limit(max).map_err(|_| HttpErr::InvalidInput)?;
        let deadline = Deadline::from_nanos(timeout).map_err(|_| HttpErr::InvalidInput)?;
        let method = str_ref(method).to_string();
        if !valid_method(&method) {
            return Err(HttpErr::InvalidInput);
        }
        let url = url::parse(str_ref(address)).ok_or(HttpErr::InvalidInput)?;
        if url.scheme != "http" && url.scheme != "https" {
            return Err(HttpErr::InvalidInput);
        }
        if check_policy && !owner.host_allowed(&url.host) {
            return Err(HttpErr::PermissionDenied);
        }
        let headers = outgoing_headers(
            &shared(headers).borrow(),
            &["Host", "Content-Length", "Transfer-Encoding"],
        )
        .ok_or(HttpErr::InvalidInput)?;
        Ok(Call {
            method,
            url,
            headers,
            max_response: max.unwrap_or(u64::MAX),
            deadline,
        })
    }
}

fn request_of(call: Call, body: Body) -> Request {
    Request {
        method: call.method,
        url: call.url,
        headers: call.headers,
        body,
        max_response: call.max_response,
        deadline: call.deadline,
    }
}

/// # Safety
/// Pointers per `ABI.md`.
#[allow(clippy::too_many_arguments)]
unsafe fn client_send(
    c: *const Obj,
    method: *const StrObj,
    address: *const StrObj,
    headers: *const Obj,
    body: Body,
    max: Option<i64>,
    timeout: Option<i64>,
    out: *mut *mut Obj,
    err: *mut *mut StrObj,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        let client = handle_ref::<ClientRef>(c);
        let result = prepare(
            client.network(),
            method,
            address,
            headers,
            max,
            timeout,
            true,
        )
        .and_then(|call| {
            if client.is_closed() {
                return Err(HttpErr::Closed);
            }
            client.send(request_of(call, body))
        });
        finish(result, err, |b| *out = new_handle::<BodyRef>(b))
    }
}

/// `HttpClient.request(method, url, headers, body, max_response_bytes, timeout)`.
///
/// # Safety
/// Pointers per `ABI.md`; `method` is the method token.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_http_client_request(
    c: *const Obj,
    method: *const StrObj,
    address: *const StrObj,
    headers: *const Obj,
    body: *const StrObj,
    has_max: u8,
    max: i64,
    has_timeout: u8,
    timeout: i64,
    out: *mut *mut Obj,
    err: *mut *mut StrObj,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        let body = Body::Bytes(Rc::new(str_ref(body).as_bytes().to_vec()));
        client_send(
            c,
            method,
            address,
            headers,
            body,
            opt(has_max, max),
            opt(has_timeout, timeout),
            out,
            err,
        )
    }
}

/// `HttpClient.request_bytes(...)` with a `Bytes` body.
///
/// # Safety
/// Pointers per `ABI.md`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_http_client_request_bytes(
    c: *const Obj,
    method: *const StrObj,
    address: *const StrObj,
    headers: *const Obj,
    body: *const VecVal,
    has_max: u8,
    max: i64,
    has_timeout: u8,
    timeout: i64,
    out: *mut *mut Obj,
    err: *mut *mut StrObj,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        let body = Body::Bytes(Rc::new(bytes_ref(body).to_vec()));
        client_send(
            c,
            method,
            address,
            headers,
            body,
            opt(has_max, max),
            opt(has_timeout, timeout),
            out,
            err,
        )
    }
}

struct Upload {
    stream: StreamWire,
}

impl Source for Upload {
    fn next(&mut self, max: usize) -> Result<Option<Vec<u8>>, String> {
        let mut out = std::mem::MaybeUninit::<VecVal>::uninit();
        let mut present = 0u8;
        let mut message: *mut StrObj = std::ptr::null_mut();
        // SAFETY: the thunk follows the `Connection.read` convention and fills `out`
        // (an owned `Bytes`) when it reports a chunk; `data` is borrowed for the call.
        let status = unsafe {
            (self.stream.read)(
                self.stream.data,
                1,
                max as i64,
                out.as_mut_ptr(),
                &mut present,
                &mut message,
            )
        };
        if !message.is_null() {
            // SAFETY: the thunk handed us an owned string.
            unsafe { msrt_release(message.cast()) };
        }
        if status != 0 {
            return Err("source stream read failed".into());
        }
        if present == 0 {
            return Ok(None);
        }
        // SAFETY: `present` means `out` holds an owned `Bytes`.
        let data = unsafe { take_bytes(&out.assume_init()) };
        if data.is_empty() || data.len() > max {
            return Err("source stream violated chunk bound".into());
        }
        Ok(Some(data))
    }
}

/// `HttpClient.request_stream(method, url, headers, body: ReadStream, ...)`.
///
/// # Safety
/// Pointers per `ABI.md`; `body` is a live `StreamWire` borrowed for the call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_http_client_request_stream(
    c: *const Obj,
    method: *const StrObj,
    address: *const StrObj,
    headers: *const Obj,
    body: *const StreamWire,
    has_max: u8,
    max: i64,
    has_timeout: u8,
    timeout: i64,
    out: *mut *mut Obj,
    err: *mut *mut StrObj,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        let stream = StreamWire {
            data: (*body).data,
            read: (*body).read,
        };
        client_send(
            c,
            method,
            address,
            headers,
            Body::Stream(Box::new(Upload { stream })),
            opt(has_max, max),
            opt(has_timeout, timeout),
            out,
            err,
        )
    }
}

// --------------------------------------------------------------- response body

/// `ResponseBody.close()`.
///
/// # Safety
/// `b` is a live response-body handle.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_http_body_close(b: *const Obj) {
    // SAFETY: caller contract.
    unsafe { handle_ref::<BodyRef>(b).close() }
}

/// `ResponseBody.metadata() -> HttpResponseMetadata`: headers are shared (+1).
///
/// # Safety
/// `out` is writable.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_http_body_metadata(b: *const Obj, out: *mut MetadataWire) {
    // SAFETY: caller contract.
    unsafe {
        let body = handle_ref::<BodyRef>(b);
        out.write(MetadataWire {
            status: i64::from(body.status),
            headers: shared_handle(body.headers.clone()),
            protocol: new_string(&body.protocol),
        });
    }
}

/// `ResponseBody.read(max_bytes) -> Result[Optional[Bytes], IoError]`.
///
/// # Safety
/// Pointers per `ABI.md`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_http_body_read(
    b: *const Obj,
    has_max: u8,
    max: i64,
    out: *mut VecVal,
    present: *mut u8,
    err: *mut *mut StrObj,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        let max = match opt(has_max, max) {
            None => 65536,
            Some(n) if n <= 0 => return IoErr::InvalidInput.code(),
            Some(n) => n.min(65536) as usize,
        };
        finish(
            handle_ref::<BodyRef>(b).read(max),
            err,
            |chunk| match chunk {
                Some(data) => {
                    *present = 1;
                    write_bytes(out, &data);
                }
                None => *present = 0,
            },
        )
    }
}

// ---------------------------------------------------------------- one-shot call

/// # Safety
/// Pointers per `ABI.md`.
#[allow(clippy::too_many_arguments)]
unsafe fn one_shot(
    net: *const Obj,
    method: *const StrObj,
    address: *const StrObj,
    headers: *const Obj,
    body: Vec<u8>,
    max: Option<i64>,
    timeout: Option<i64>,
    out: *mut ClientResponseWire,
    err: *mut *mut StrObj,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        let network = network(net);
        let result = (|| {
            if network.is_closed() {
                return Err(HttpErr::Closed);
            }
            let call = prepare(network, method, address, headers, max, timeout, false)?;
            let client = Client::one_shot(network)?;
            let response = client.send(request_of(call, Body::Bytes(Rc::new(body))))?;
            let data = response.read_all().map_err(|e| match e {
                client::ReadAll::Limit => HttpErr::LimitExceeded,
                client::ReadAll::Closed => HttpErr::Closed,
                client::ReadAll::Invalid => HttpErr::InvalidData,
            });
            let data = data.map_err(|e| {
                if client.is_closed() {
                    HttpErr::Closed
                } else {
                    e
                }
            })?;
            Ok((response, data))
        })();
        finish(result, err, |(response, data)| {
            let mut bytes = std::mem::MaybeUninit::<VecVal>::uninit();
            write_bytes(bytes.as_mut_ptr(), &data);
            out.write(ClientResponseWire {
                status: i64::from(response.status),
                headers: shared_handle(response.headers.clone()),
                protocol: new_string(&response.protocol),
                body: bytes.assume_init(),
            });
        })
    }
}

/// `Network.request(method, url, headers, body, max_response_bytes, timeout)`.
///
/// # Safety
/// Pointers per `ABI.md`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_net_network_request(
    net: *const Obj,
    method: *const StrObj,
    address: *const StrObj,
    headers: *const Obj,
    body: *const StrObj,
    has_max: u8,
    max: i64,
    has_timeout: u8,
    timeout: i64,
    out: *mut ClientResponseWire,
    err: *mut *mut StrObj,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        one_shot(
            net,
            method,
            address,
            headers,
            str_ref(body).as_bytes().to_vec(),
            opt(has_max, max),
            opt(has_timeout, timeout),
            out,
            err,
        )
    }
}

/// `Network.request_bytes(...)` with a `Bytes` body.
///
/// # Safety
/// Pointers per `ABI.md`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_net_network_request_bytes(
    net: *const Obj,
    method: *const StrObj,
    address: *const StrObj,
    headers: *const Obj,
    body: *const VecVal,
    has_max: u8,
    max: i64,
    has_timeout: u8,
    timeout: i64,
    out: *mut ClientResponseWire,
    err: *mut *mut StrObj,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        one_shot(
            net,
            method,
            address,
            headers,
            bytes_ref(body).to_vec(),
            opt(has_max, max),
            opt(has_timeout, timeout),
            out,
            err,
        )
    }
}

// ---------------------------------------------------------------------- server

/// The program's handler behind the server.
struct Program {
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
    let mut message: *mut StrObj = std::ptr::null_mut();
    // SAFETY: `run` and its data outlive the call; `message` is written only on a fault.
    let status = unsafe { msrt_guard_call(run, (&raw mut dynamic).cast(), &mut message) };
    match status {
        0 => None,
        2 => Some(Outcome::Cancelled),
        _ => {
            let text = if message.is_null() {
                "fault".to_string()
            } else {
                // SAFETY: the guard hands over an owned string, released once here.
                let text = unsafe { str_ref(message) }.to_string();
                // SAFETY: as above.
                unsafe { msrt_release(message.cast()) };
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
        let mut message: *mut StrObj = std::ptr::null_mut();
        // SAFETY: the exchange handle moves to the thunk; the status and optional
        // message string come back owned.
        let mut status = 0;
        let handle = new_handle::<ExchangeRef>(exchange);
        // SAFETY: the thunk contract; the handle moves to it.
        let call = || status = unsafe { thunk(self.env, handle, &mut message) };
        if let Some(stop) = guarded(call) {
            return stop;
        }
        let text = if message.is_null() {
            String::new()
        } else {
            // SAFETY: an owned string from the thunk.
            let text = unsafe { str_ref(message) }.to_string();
            // SAFETY: as above; the string is released once, after copying.
            unsafe { msrt_release(message.cast()) };
            text
        };
        Outcome::Done(match status {
            0 => Ok(()),
            code => Err(http_from_code(code, text)),
        })
    }
}

fn server_limits(
    admission: Option<i64>,
    body: Option<i64>,
    response: Option<i64>,
    header: Option<i64>,
    timeout: Option<i64>,
    grace: Option<i64>,
) -> Result<Limits, ()> {
    let unlimited = usize::MAX;
    let size = |v: Option<i64>| -> Result<usize, ()> {
        Ok(limit(v)?.map_or(unlimited, |n| n.min(unlimited as u64) as usize))
    };
    let admission = size(admission)?;
    let header = size(header)?;
    if admission == 0 || header == 0 {
        return Err(());
    }
    Ok(Limits {
        admission,
        body: size(body)?,
        response: size(response)?,
        header,
        timeout: limit(timeout)?.map(Duration::from_nanos),
        grace: limit(grace)?.map(Duration::from_nanos),
    })
}

/// `Network.serve(address, handler, ...) -> Result[HttpServer, IoError]`.
///
/// `env` is the handler closure (the native takes a reference; the server
/// releases it when dropped) and `thunk` calls it.
///
/// # Safety
/// Pointers per `ABI.md`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_net_network_serve(
    net: *const Obj,
    address: *const StrObj,
    env: *mut Obj,
    thunk: BufferedThunk,
    has_max_requests: u8,
    max_requests: i64,
    has_max_body: u8,
    max_body: i64,
    has_max_response: u8,
    max_response: i64,
    has_timeout: u8,
    timeout: i64,
    has_grace: u8,
    grace: i64,
    out: *mut *mut Obj,
    err: *mut *mut StrObj,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        let program = Box::new(Program {
            env: retained(env),
            buffered: Some(thunk),
            streaming: None,
        });
        let limits = server_limits(
            opt(has_max_requests, max_requests),
            opt(has_max_body, max_body),
            opt(has_max_response, max_response),
            None,
            opt(has_timeout, timeout),
            opt(has_grace, grace),
        );
        let result = match limits {
            Err(()) => Err(IoErr::InvalidInput),
            Ok(limits) => Server::start(
                network(net),
                str_ref(address),
                program,
                Options {
                    limits,
                    streaming: false,
                    tls: None,
                },
            )
            .map_err(|e| match e {
                crate::error::NetErr::Closed => IoErr::Closed,
                _ => IoErr::Unavailable,
            }),
        };
        finish(result, err, |s| *out = new_handle::<ServerRef>(s))
    }
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

/// `Network.serve_stream(address, handler, options) -> Result[HttpServer, HttpError]`.
///
/// # Safety
/// Pointers per `ABI.md`; `opts` is a live `HttpServerOptionsWire`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_net_network_serve_stream(
    net: *const Obj,
    address: *const StrObj,
    env: *mut Obj,
    thunk: StreamThunk,
    opts: *const HttpServerOptionsWire,
    out: *mut *mut Obj,
    err: *mut *mut StrObj,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        let w = &*opts;
        let program = Box::new(Program {
            env: retained(env),
            buffered: None,
            streaming: Some(thunk),
        });
        let limits = server_limits(
            w.max_requests.get(),
            w.max_body_bytes.get(),
            w.max_response_bytes.get(),
            w.max_header_bytes.get(),
            w.timeout.get(),
            w.grace.get(),
        );
        let owner = network(net);
        let result = (|| {
            let limits = limits.map_err(|()| HttpErr::InvalidInput)?;
            if !owner.listen_allowed(str_ref(address)) {
                return Err(HttpErr::PermissionDenied);
            }
            let tls = if w.tls_present != 0 {
                let mut options = tls_options(&w.tls);
                if options.alpn.is_empty() {
                    options.alpn = vec!["http/1.1".to_string()];
                }
                Some(tls::server_config(&options).map_err(|_| HttpErr::InvalidInput)?)
            } else {
                None
            };
            Server::start(
                owner,
                str_ref(address),
                program,
                Options {
                    limits,
                    streaming: true,
                    tls,
                },
            )
            .map_err(HttpErr::from)
        })();
        finish(result, err, |s| *out = new_handle::<ServerRef>(s))
    }
}

/// `HttpServer.address() -> String`.
///
/// # Safety
/// `s` is a live server handle.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_http_server_address(s: *const Obj) -> *mut StrObj {
    // SAFETY: caller contract.
    unsafe { new_string(handle_ref::<ServerRef>(s).address()) }
}

/// `HttpServer.close()`; closing from the server's own handler faults.
///
/// # Safety
/// `s` is a live server handle.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_http_server_close(s: *const Obj) {
    // SAFETY: caller contract.
    unsafe {
        if let Err(CloseError::FromHandler) = handle_ref::<ServerRef>(s).close() {
            fault("HTTP server cannot close from its own request");
        }
    }
}

/// `HttpServer.wait() -> Result[Unit, IoError]`.
///
/// # Safety
/// `s` is a live server handle.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_http_server_wait(s: *const Obj) -> u8 {
    // SAFETY: caller contract.
    unsafe { handle_ref::<ServerRef>(s).wait() };
    0
}

// -------------------------------------------------------------------- exchange

/// # Safety
/// `x` is a live exchange handle.
unsafe fn exchange<'a>(x: *const Obj) -> &'a ExchangeRef {
    // SAFETY: caller contract.
    unsafe { handle_ref::<ExchangeRef>(x) }
}

/// `HttpExchange.close()`.
///
/// # Safety
/// `x` is a live exchange handle.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_http_exchange_close(x: *const Obj) {
    // SAFETY: caller contract.
    unsafe { exchange(x).close() }
}

/// `HttpExchange.headers() -> HttpHeaders` (+1, shared with the exchange).
///
/// # Safety
/// `x` is a live exchange handle.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_http_exchange_headers(x: *const Obj) -> *mut Obj {
    // SAFETY: caller contract.
    unsafe { shared_handle(exchange(x).headers()) }
}

/// `HttpExchange.method() -> String` (the method token).
///
/// # Safety
/// `x` is a live exchange handle.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_http_exchange_method(x: *const Obj) -> *mut StrObj {
    // SAFETY: caller contract.
    unsafe { new_string(&exchange(x).method()) }
}

/// `HttpExchange.path() -> String`.
///
/// # Safety
/// `x` is a live exchange handle.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_http_exchange_path(x: *const Obj) -> *mut StrObj {
    // SAFETY: caller contract.
    unsafe { new_string(&exchange(x).path()) }
}

/// `HttpExchange.protocol() -> String`.
///
/// # Safety
/// `x` is a live exchange handle.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_http_exchange_protocol(x: *const Obj) -> *mut StrObj {
    // SAFETY: caller contract.
    unsafe { new_string(exchange(x).protocol()) }
}

/// `HttpExchange.query() -> String`.
///
/// # Safety
/// `x` is a live exchange handle.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_http_exchange_query(x: *const Obj) -> *mut StrObj {
    // SAFETY: caller contract.
    unsafe { new_string(&exchange(x).query()) }
}

/// `HttpExchange.read(max_bytes) -> Result[Optional[Bytes], IoError]`.
///
/// # Safety
/// Pointers per `ABI.md`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_http_exchange_read(
    x: *const Obj,
    has_max: u8,
    max: i64,
    out: *mut VecVal,
    present: *mut u8,
    err: *mut *mut StrObj,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        finish(
            exchange(x).read(opt(has_max, max)),
            err,
            |chunk| match chunk {
                Some(data) => {
                    *present = 1;
                    write_bytes(out, &data);
                }
                None => *present = 0,
            },
        )
    }
}

/// `HttpExchange.send_headers(status, headers) -> Result[Unit, HttpError]`.
///
/// # Safety
/// Pointers per `ABI.md`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_http_exchange_send_headers(
    x: *const Obj,
    status: i64,
    headers: *const Obj,
    err: *mut *mut StrObj,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        let h = shared(headers).borrow().clone();
        finish(exchange(x).send_headers(status, &h), err, |()| {})
    }
}

/// `HttpExchange.write(data: String) -> Result[Unit, IoError]`.
///
/// # Safety
/// Pointers per `ABI.md`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_http_exchange_write(
    x: *const Obj,
    data: *const StrObj,
    err: *mut *mut StrObj,
) -> u8 {
    // SAFETY: caller contract.
    unsafe { finish(exchange(x).write(str_ref(data).as_bytes()), err, |()| {}) }
}

/// `HttpExchange.write_bytes(data: Bytes) -> Result[Unit, IoError]`.
///
/// # Safety
/// Pointers per `ABI.md`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_http_exchange_write_bytes(
    x: *const Obj,
    data: *const VecVal,
    err: *mut *mut StrObj,
) -> u8 {
    // SAFETY: caller contract.
    unsafe { finish(exchange(x).write(bytes_ref(data)), err, |()| {}) }
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
            if str_ref((*req).path) == "/boom" {
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
