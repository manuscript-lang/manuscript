//! Natives for the server half of `@std/net/http.ms`: `Network.serve`, servers and exchanges.

use super::handler::Program;
use ms_rt_abi::Obj;
use super::http_client::{chunk, limit};
use super::tls::tls_options;
use super::{ExchH, HeadersH, ServingH, opt, report};
use crate::error::HttpErr;
use crate::conn::Listener;
use crate::http::server::{Limits, Options, Server};
use crate::tls;
use ms_rt::ffi::{
    ErrOut, Handler, ObjRef, Object, OptInt, Out, StatusCode, Str, StringList, abi_record, native,
};
use std::cell::RefCell;
use std::rc::Rc;
use std::time::Duration;

abi_record! {
    /// `HttpServerOptions` as the compiler lays it out for natives; `tls` is meaningful only when
    /// `tls_present` (the `TlsOptions?` flag) is nonzero.
    pub struct HttpServerOptionsWire {
        pub max_requests: OptInt,
        pub max_body_bytes: OptInt,
        pub max_response_bytes: OptInt,
        pub max_header_bytes: OptInt,
        pub timeout: OptInt,
        pub grace: OptInt,
        pub tls_present: u8,
        // `tls` inline (see `tls_options`).
        pub tls_server_name: Str,
        pub tls_roots_pem: Str,
        pub tls_certificate_pem: Str,
        pub tls_private_key_pem: Str,
        pub tls_alpn: StringList,
        pub tls_require_client_certificate: u8,
        // Read by `serve` itself, not by the server: the runtime thread limit.
        pub cores: OptInt,
    }
}

/// Request header block cap when `max_header_bytes` is none.
const SERVE_MAX_HEADER_BYTES: i64 = 1 << 20;

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
    let header = size(header.or(Some(SERVE_MAX_HEADER_BYTES)))?;
    let timeout = limit(timeout)?;
    if admission == 0 || header == 0 || timeout == Some(0) {
        return Err(());
    }
    Ok(Limits {
        admission,
        body: size(body)?,
        response: size(response)?,
        header,
        timeout: timeout.map(Duration::from_nanos),
        grace: limit(grace)?.map(Duration::from_nanos),
    })
}

/// The server's limits and TLS settings from the wire options.
fn server_options(opts: &HttpServerOptionsWire) -> Result<Options, HttpErr> {
    let limits = server_limits(
        opts.max_requests.get(),
        opts.max_body_bytes.get(),
        opts.max_response_bytes.get(),
        opts.max_header_bytes.get(),
        opts.timeout.get(),
        opts.grace.get(),
    )
    .map_err(|()| HttpErr::InvalidInput)?;
    let tls = if opts.tls_present != 0 {
        let mut options = tls_options(
            &opts.tls_server_name,
            &opts.tls_roots_pem,
            &opts.tls_certificate_pem,
            &opts.tls_private_key_pem,
            &opts.tls_alpn,
            opts.tls_require_client_certificate,
        );
        if options.alpn.is_empty() {
            options.alpn = vec!["http/1.1".to_string()];
        }
        Some(tls::server_config(&options).map_err(|_| HttpErr::InvalidInput)?)
    } else {
        None
    };
    Ok(Options {
        limits,
        admitted: Default::default(),
        tls,
    })
}

/// What every connection of one `serve` call shares.
pub struct Serving {
    options: Options,
    /// The handler closure, one reference held until the serving drops.
    handler: *mut Obj,
    listener: Rc<Listener>,
}

impl Serving {
    fn new(options: Options, handler: *mut Obj, listener: Rc<Listener>) -> Serving {
        // SAFETY: `handler` is a live closure object.
        unsafe { ms_rt::obj::msrt_retain(handler) };
        Serving {
            options,
            handler,
            listener,
        }
    }

    /// The serving whose identity (`msstd_http_serving_id`) is `id`.
    ///
    /// # Safety
    /// The serving must be alive and stay so while the result is used.
    unsafe fn get<'a>(id: i64) -> &'a Serving {
        // SAFETY: caller contract.
        unsafe { &*(id as *const Serving) }
    }
}

impl Drop for Serving {
    fn drop(&mut self) {
        self.listener.close();
        // SAFETY: the reference taken in `new`.
        unsafe { ms_rt::obj::msrt_release(self.handler) };
    }
}

native! {
    // -------------------------------------------------------------------- server

    /// `serving(address, options, handler)`: binds the plain TCP listener of one `serve` call and
    /// holds what every connection of the call shares: the limits, TLS settings, admission count
    /// and handler.
    fn msstd_http_serving_new(
        address: &str,
        opts: &HttpServerOptionsWire,
        env: Handler,
        out: Out<Object<ServingH>>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        let options = report(server_options(opts), &err)?;
        let root = crate::net::root();
        let listener = report(root.listen(address), &err)?;
        out.write(Object(ServingH(Serving::new(options, env.as_ptr(), listener))));
        Ok(())
    }

    /// The identity of a serving for the promises that use it: they cannot capture the object, but
    /// can capture this number, and the `HttpServer` keeps the object alive until they ended.
    fn msstd_http_serving_id(s: ObjRef<ServingH>) -> i64 {
        std::ptr::from_ref::<Serving>(&s) as i64
    }

    /// The bound address of the listener of serving `id`.
    fn msstd_http_serving_address(id: i64) -> String {
        // SAFETY: `id` names a serving its owner keeps alive (see `msstd_http_serving_id`).
        unsafe { Serving::get(id) }.listener.address().to_string()
    }

    /// Waits for the next connection of serving `id` and returns its socket handle.
    fn msstd_http_serving_accept(id: i64, out: Out<i64>, err: ErrOut) -> Result<(), StatusCode> {
        // SAFETY: as above.
        let serving = unsafe { Serving::get(id) };
        out.write(report(serving.listener.accept_raw(None), &err)?);
        Ok(())
    }

    /// Serves the socket handle `accept` returned, on this thread, and returns when the connection
    /// has ended. The handler is only borrowed from the serving.
    fn msstd_http_serving_connect(id: i64, connection: i64) -> () {
        // SAFETY: as above.
        let serving = unsafe { Serving::get(id) };
        // SAFETY: the serving keeps the handler alive until every connection promise ended.
        let program = unsafe { Program::borrowed(serving.handler) };
        if let Ok(server) = Server::start_adopting(&crate::net::root(), program, serving.options.clone())
        {
            server.serve_connection(connection);
        }
    }

    /// Closes the listener of serving `id` and the connections accepted and never served.
    fn msstd_http_serving_release(id: i64) -> () {
        // SAFETY: as above.
        let serving = unsafe { Serving::get(id) };
        serving.listener.close();
        crate::conn::release_unadopted(serving.listener.owner_key());
    }

    // ------------------------------------------------------------------ exchange

    /// `HttpExchange.close()`.
    fn msstd_http_exchange_close(x: ObjRef<ExchH>) -> () {
        x.close();
    }

    /// `HttpExchange.headers()`.
    fn msstd_http_exchange_headers(x: ObjRef<ExchH>) -> Object<HeadersH> {
        Object(HeadersH(Rc::new(RefCell::new(x.headers().borrow().clone()))))
    }

    /// `HttpExchange.method()`.
    fn msstd_http_exchange_method(x: ObjRef<ExchH>) -> String {
        x.method()
    }

    /// `HttpExchange.path()`.
    fn msstd_http_exchange_path(x: ObjRef<ExchH>) -> String {
        x.path()
    }

    /// `HttpExchange.protocol()`.
    fn msstd_http_exchange_protocol(x: ObjRef<ExchH>) -> String {
        x.protocol().to_string()
    }

    /// `HttpExchange.query()`.
    fn msstd_http_exchange_query(x: ObjRef<ExchH>) -> String {
        x.query()
    }

    /// `HttpExchange.read(max)`; the end of the body is `STATUS_NONE`.
    fn msstd_http_exchange_read(
        x: ObjRef<ExchH>,
        has_max: bool,
        max: i64,
        out: Out<Vec<u8>>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        chunk(x.read(opt(has_max, max)), out, &err)
    }

    /// `HttpExchange.send_headers(status, headers)`.
    fn msstd_http_exchange_send_headers(
        x: ObjRef<ExchH>,
        status: i64,
        headers: ObjRef<HeadersH>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        let h = headers.borrow().clone();
        report(x.send_headers(status, &h), &err)
    }

    /// `HttpExchange.send(status, headers, body)`.
    fn msstd_http_exchange_send(
        x: ObjRef<ExchH>,
        status: i64,
        headers: ObjRef<HeadersH>,
        body: &[u8],
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        let h = headers.borrow().clone();
        report(x.send_response(status, &h, body), &err)
    }

    /// `HttpExchange.write(data)`.
    fn msstd_http_exchange_write(x: ObjRef<ExchH>, data: &str, err: ErrOut) -> Result<(), StatusCode> {
        report(x.write(data.as_bytes()), &err)
    }

    /// `HttpExchange.write(data: Bytes)`.
    fn msstd_http_exchange_write_bytes(x: ObjRef<ExchH>, data: &[u8], err: ErrOut) -> Result<(), StatusCode> {
        report(x.write(data), &err)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use core::mem::offset_of;

    /// The compiler packs a record's leaves in declaration order, a nested record's included.
    #[test]
    fn tls_options_are_packed_inline() {
        assert_eq!(offset_of!(HttpServerOptionsWire, tls_present), 96);
        assert_eq!(offset_of!(HttpServerOptionsWire, tls_server_name), 104);
        assert_eq!(
            offset_of!(HttpServerOptionsWire, tls_require_client_certificate),
            192
        );
    }
}
