//! Natives for the client half of `@std/net/http.ms` and the `Network.request` entry points of
//! `@std/net/net.ms`: headers, clients, response bodies and one-shot requests.

use super::tls::TlsOptionsWire;
use super::{BodyH, ClientH, HeadersH, NetH, code, opt, report};
use crate::error::{HttpErr, IoErr};
use crate::http::client::{
    self, Body, Client, ClientOptions, Request, Source, outgoing_headers, valid_method,
};
use crate::http::headers::Headers;
use crate::http::url;
use crate::wait::Deadline;
use ms_rt::ffi::{
    Bytes, BytesList, ErrOut, ObjRef, ObjSlot, Object, OptInt, Out, ReadSource, StatusCode, Str,
    abi_record, native,
};
use ms_rt_abi::STATUS_NONE;
use std::cell::RefCell;
use std::rc::Rc;
use std::time::Duration;

abi_record! {
    /// `HttpClientOptions` as the compiler lays it out for natives.
    pub struct HttpClientOptionsWire {
        pub max_redirects: OptInt,
        pub max_idle_connections: OptInt,
        pub max_header_bytes: OptInt,
        pub idle_timeout: OptInt,
        pub decompress: u8,
        pub cookies: u8,
        pub tls: TlsOptionsWire,
    }
}

abi_record! {
    /// A buffered response with its metadata (`ClientResponse`).
    pub struct ClientResponseWire {
        pub status: i64,
        pub headers: ObjSlot<HeadersH>,
        pub protocol: Str,
        pub body: Bytes,
    }
}

abi_record! {
    /// `HttpResponseMetadata`.
    pub struct MetadataWire {
        pub status: i64,
        pub headers: ObjSlot<HeadersH>,
        pub protocol: Str,
    }
}

/// A read result as a status: `STATUS_NONE` at the end of the stream, else the chunk through `out`.
pub(super) fn chunk<E: crate::error::Status>(
    r: Result<Option<Vec<u8>>, E>,
    out: Out<Vec<u8>>,
    err: &ErrOut,
) -> Result<(), StatusCode> {
    match report(r, err)? {
        Some(data) => out.write(data),
        None => return Err(StatusCode(STATUS_NONE)),
    }
    Ok(())
}

/// A negative limit is invalid; `None` is unlimited.
pub(super) fn limit(v: Option<i64>) -> Result<Option<u64>, ()> {
    match v {
        Some(n) if n < 0 => Err(()),
        Some(n) => Ok(Some(n as u64)),
        None => Ok(None),
    }
}

pub(super) fn http_from_code(status: u8, failed: String) -> HttpErr {
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

fn new_headers(h: Headers) -> Object<HeadersH> {
    Object(HeadersH(Rc::new(RefCell::new(h))))
}

fn client_options(w: &HttpClientOptionsWire) -> Result<ClientOptions, HttpErr> {
    let bad = |_| HttpErr::InvalidInput;
    Ok(ClientOptions {
        max_redirects: limit(w.max_redirects.get()).map_err(bad)?,
        max_idle: limit(w.max_idle_connections.get()).map_err(bad)?,
        max_header_bytes: limit(w.max_header_bytes.get()).map_err(bad)?,
        idle_timeout: limit(w.idle_timeout.get())
            .map_err(bad)?
            .map(Duration::from_nanos),
        decompress: w.decompress != 0,
        cookies: w.cookies != 0,
        tls: w.tls.to_options(),
    })
}

struct Call {
    method: String,
    url: url::Url,
    headers: Vec<(String, Vec<u8>)>,
    max_response: u64,
    deadline: Deadline,
}

/// Validates a request: limits, deadline, method, URL, policy and outgoing headers.
fn prepare(
    owner: &crate::net::Network,
    method: &str,
    address: &str,
    headers: &HeadersH,
    max: Option<i64>,
    timeout: Option<i64>,
    check_policy: bool,
) -> Result<Call, HttpErr> {
    let max = limit(max).map_err(|_| HttpErr::InvalidInput)?;
    let deadline = Deadline::from_nanos(timeout).map_err(|_| HttpErr::InvalidInput)?;
    if !valid_method(method) {
        return Err(HttpErr::InvalidInput);
    }
    let url = url::parse(address).ok_or(HttpErr::InvalidInput)?;
    if url.scheme != "http" && url.scheme != "https" {
        return Err(HttpErr::InvalidInput);
    }
    if check_policy && !owner.host_allowed(&url.host) {
        return Err(HttpErr::PermissionDenied);
    }
    let headers = outgoing_headers(
        &headers.borrow(),
        &["Host", "Content-Length", "Transfer-Encoding"],
    )
    .ok_or(HttpErr::InvalidInput)?;
    Ok(Call {
        method: method.to_string(),
        url,
        headers,
        max_response: max.unwrap_or(u64::MAX),
        deadline,
    })
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

/// Everything a request call carries besides its body and the output slots.
struct Args<'a> {
    method: &'a str,
    address: &'a str,
    headers: &'a HeadersH,
    max: Option<i64>,
    timeout: Option<i64>,
}

fn client_send(
    client: &Rc<Client>,
    a: &Args,
    body: Body,
    out: Out<Object<BodyH>>,
    err: &ErrOut,
) -> Result<(), StatusCode> {
    let result = prepare(
        client.network(),
        a.method,
        a.address,
        a.headers,
        a.max,
        a.timeout,
        true,
    )
    .and_then(|call| {
        if client.is_closed() {
            return Err(HttpErr::Closed);
        }
        client.send(request_of(call, body))
    });
    out.write(Object(BodyH(report(result, err)?)));
    Ok(())
}

/// A request body streamed from a compiled `ReadStream`.
struct Upload(ReadSource);

impl Source for Upload {
    fn next(&mut self, max: usize) -> Result<Option<Vec<u8>>, String> {
        let chunk = self
            .0
            .read(max)
            .map_err(|_| "source stream read failed".to_string())?;
        match chunk {
            Some(data) if data.is_empty() || data.len() > max => {
                Err("source stream violated chunk bound".into())
            }
            chunk => Ok(chunk),
        }
    }
}

/// Sends a buffered request on a one-shot client and reads the whole response.
fn one_shot(
    net: &NetH,
    a: &Args,
    body: Vec<u8>,
    out: Out<ClientResponseWire>,
    err: &ErrOut,
) -> Result<(), StatusCode> {
    let result = (|| {
        if net.is_closed() {
            return Err(HttpErr::Closed);
        }
        let call = prepare(net, a.method, a.address, a.headers, a.max, a.timeout, false)?;
        let client = Client::one_shot(net)?;
        let response = client.send(request_of(call, Body::Bytes(Rc::new(body))))?;
        let data = response
            .read_all()
            .map_err(|e| match e {
                client::ReadAll::Limit => HttpErr::LimitExceeded,
                client::ReadAll::Closed => HttpErr::Closed,
                client::ReadAll::Timeout => HttpErr::Timeout,
                client::ReadAll::Invalid => HttpErr::InvalidData,
            })
            .map_err(|e| {
                if client.is_closed() {
                    HttpErr::Closed
                } else {
                    e
                }
            })?;
        Ok((response, data))
    })();
    let (response, data) = report(result, err)?;
    out.write(ClientResponseWire {
        status: i64::from(response.status),
        headers: ObjSlot::new(HeadersH(Rc::new(RefCell::new(
            response.headers.borrow().clone(),
        )))),
        protocol: Str::new(&response.protocol),
        body: Bytes::new(&data),
    });
    Ok(())
}

native! {
    // -------------------------------------------------------------------- errors

    /// `HttpError.message()` for a status and the `Failed` text (nullable).
    fn msstd_http_error_message(status: u8, has_failed: bool, failed: &str) -> String {
        http_from_code(status, (if has_failed { failed } else { "" }).to_string()).message()
    }

    // ------------------------------------------------------------------- headers

    /// `HttpHeaders()`.
    fn msstd_http_headers_new() -> Object<HeadersH> {
        new_headers(Headers::new())
    }

    /// `HttpHeaders.append(name, value)`.
    fn msstd_http_headers_append(h: ObjRef<HeadersH>, name: &str, value: &[u8]) -> Result<(), StatusCode> {
        h.borrow_mut().append(name, value).map_err(code)
    }

    /// `HttpHeaders.values(name)`: 1 and the values when the field exists, 0 otherwise.
    fn msstd_http_headers_values(h: ObjRef<HeadersH>, name: &str, out: Out<BytesList>) -> u8 {
        let headers = h.borrow();
        let Some(values) = headers.values(name) else {
            return 0;
        };
        out.write(BytesList(values.to_vec()));
        1
    }

    /// `HttpHeaders.names()`.
    fn msstd_http_headers_names(h: ObjRef<HeadersH>, out: Out<Vec<String>>) -> () {
        out.write(h.borrow().names().into_iter().map(str::to_string).collect());
    }

    /// `HttpHeaders.remove(name)`.
    fn msstd_http_headers_remove(h: ObjRef<HeadersH>, name: &str) -> bool {
        h.borrow_mut().remove(name)
    }

    /// `HttpHeaders.clone()`.
    fn msstd_http_headers_clone(h: ObjRef<HeadersH>) -> Object<HeadersH> {
        new_headers(h.borrow().clone())
    }

    // -------------------------------------------------------------------- client

    /// `Network.http_client(options) -> Result[HttpClient, HttpError]`.
    fn msstd_net_network_http_client(
        net: ObjRef<NetH>,
        opts: &HttpClientOptionsWire,
        out: Out<Object<ClientH>>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        let client = client_options(opts).and_then(|o| Client::new(&net, o));
        out.write(Object(ClientH(report(client, &err)?)));
        Ok(())
    }

    /// `HttpClient.close()`.
    fn msstd_http_client_close(c: ObjRef<ClientH>) -> () {
        c.close();
    }

    /// `HttpClient.request(method, address, headers, body, max_response, timeout)`.
    fn msstd_http_client_request(
        c: ObjRef<ClientH>,
        method: &str,
        address: &str,
        headers: ObjRef<HeadersH>,
        body: &str,
        has_max: bool,
        max: i64,
        has_timeout: bool,
        timeout: i64,
        out: Out<Object<BodyH>>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        let args = Args {
            method,
            address,
            headers: &headers,
            max: opt(has_max, max),
            timeout: opt(has_timeout, timeout),
        };
        let body = Body::Bytes(Rc::new(body.as_bytes().to_vec()));
        client_send(&c, &args, body, out, &err)
    }

    /// `HttpClient.request` with a `Bytes` body.
    fn msstd_http_client_request_bytes(
        c: ObjRef<ClientH>,
        method: &str,
        address: &str,
        headers: ObjRef<HeadersH>,
        body: &[u8],
        has_max: bool,
        max: i64,
        has_timeout: bool,
        timeout: i64,
        out: Out<Object<BodyH>>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        let args = Args {
            method,
            address,
            headers: &headers,
            max: opt(has_max, max),
            timeout: opt(has_timeout, timeout),
        };
        let body = Body::Bytes(Rc::new(body.to_vec()));
        client_send(&c, &args, body, out, &err)
    }

    /// `HttpClient.request` with a streamed body.
    fn msstd_http_client_request_stream(
        c: ObjRef<ClientH>,
        method: &str,
        address: &str,
        headers: ObjRef<HeadersH>,
        src: ReadSource,
        has_max: bool,
        max: i64,
        has_timeout: bool,
        timeout: i64,
        out: Out<Object<BodyH>>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        let args = Args {
            method,
            address,
            headers: &headers,
            max: opt(has_max, max),
            timeout: opt(has_timeout, timeout),
        };
        client_send(&c, &args, Body::Stream(Box::new(Upload(src))), out, &err)
    }

    // ------------------------------------------------------------ response body

    /// `HttpResponseBody.close()`.
    fn msstd_http_body_close(b: ObjRef<BodyH>) -> () {
        b.close();
    }

    /// `HttpResponseBody.metadata()`.
    fn msstd_http_body_metadata(b: ObjRef<BodyH>) -> out MetadataWire {
        MetadataWire {
            status: i64::from(b.status),
            headers: ObjSlot::new(HeadersH(Rc::new(RefCell::new(b.headers.borrow().clone())))),
            protocol: Str::new(&b.protocol),
        }
    }

    /// `HttpResponseBody.read(max)`; the end of the body is `STATUS_NONE`.
    fn msstd_http_body_read(
        b: ObjRef<BodyH>,
        has_max: bool,
        max: i64,
        out: Out<Vec<u8>>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        let max = match opt(has_max, max) {
            None => 65536,
            Some(n) if n <= 0 => return Err(code(IoErr::InvalidInput)),
            Some(n) => n.min(65536) as usize,
        };
        chunk(b.read(max), out, &err)
    }

    /// `HttpResponseBody.read_all()`: the rest of the body in one buffer.
    fn msstd_http_body_read_all(
        b: ObjRef<BodyH>,
        out: Out<Vec<u8>>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        let data = report(b.read_all_bytes(), &err)?;
        out.write(data);
        Ok(())
    }

    // ----------------------------------------------------------------- one-shot

    /// `Network.request(method, address, headers, body, max_response, timeout)`.
    fn msstd_net_network_request(
        net: ObjRef<NetH>,
        method: &str,
        address: &str,
        headers: ObjRef<HeadersH>,
        body: &str,
        has_max: bool,
        max: i64,
        has_timeout: bool,
        timeout: i64,
        out: Out<ClientResponseWire>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        let args = Args {
            method,
            address,
            headers: &headers,
            max: opt(has_max, max),
            timeout: opt(has_timeout, timeout),
        };
        one_shot(&net, &args, body.as_bytes().to_vec(), out, &err)
    }

    /// `Network.request` with a `Bytes` body.
    fn msstd_net_network_request_bytes(
        net: ObjRef<NetH>,
        method: &str,
        address: &str,
        headers: ObjRef<HeadersH>,
        body: &[u8],
        has_max: bool,
        max: i64,
        has_timeout: bool,
        timeout: i64,
        out: Out<ClientResponseWire>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        let args = Args {
            method,
            address,
            headers: &headers,
            max: opt(has_max, max),
            timeout: opt(has_timeout, timeout),
        };
        one_shot(&net, &args, body.to_vec(), out, &err)
    }
}
