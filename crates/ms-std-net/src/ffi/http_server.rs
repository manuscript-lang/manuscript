//! Natives for the server half of `@std/net/http.ms`: `Network.serve`, servers and exchanges.
//! ms: domain HTTP

use super::handler::Program;
use super::http_client::{chunk, limit};
use super::tls::tls_options;
use super::{ExchH, HeadersH, ServingH, WorkerH, opt, report};
use crate::bound::Bound;
use crate::conn::Listener;
use crate::error::HttpErr;
use crate::http::server::{Limits, Options, Server};
use crate::tls;
use ms_rt::ffi::{
    ErrOut, Handler, Has, ObjRef, Object, OptInt, Out, StatusCode, Str, StringList, abi_type,
    native,
};
use ms_rt_abi::Obj;
use std::cell::RefCell;
use std::rc::Rc;
use std::time::Duration;

abi_type! {
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
    /// The handler closure, which the serving owns until it drops (`serve` hands it over).
    handler: *mut Obj,
    listener: Rc<Listener>,
}

impl Serving {
    fn new(options: Options, handler: *mut Obj, listener: Rc<Listener>) -> Serving {
        Serving {
            options,
            handler,
            listener,
        }
    }
}

impl Drop for Serving {
    fn drop(&mut self) {
        self.listener.close();
        // SAFETY: the closure `serve` handed over, dropped once here.
        unsafe { ms_rt::obj::msrt_obj_drop(self.handler) };
    }
}

/// The handler closure `serve` handed over, dropped unless a serving takes it.
struct OwnedHandler(*mut Obj);

impl OwnedHandler {
    fn keep(self) -> *mut Obj {
        let handler = self.0;
        std::mem::forget(self);
        handler
    }
}

impl Drop for OwnedHandler {
    fn drop(&mut self) {
        // SAFETY: the closure `serve` handed over, dropped once here.
        unsafe { ms_rt::obj::msrt_obj_drop(self.0) };
    }
}

native! {
    // -------------------------------------------------------------------- server

    /// `serving(address, options, handler)`: binds the plain TCP listener of one `serve` call and
    /// holds what every connection of the call shares: the limits, TLS settings, admission count
    /// and handler.
    // ms: keeps:env
    fn msstd_http_serving_new(
        address: &str,
        opts: &HttpServerOptionsWire,
        env: Handler,
        out: Out<Object<ServingH>>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        // The handler is ours from here: a failure before the serving exists must release it.
        let owned = OwnedHandler(env.as_ptr());
        let options = report(server_options(opts), &err)?;
        let root = crate::net::root();
        let listener = report(root.listen(address), &err)?;
        out.write(Object(ServingH(Rc::new(Serving::new(options, owned.keep(), listener)))));
        Ok(())
    }

    /// Another handle on the same serving, for a connection promise to own.
    fn msstd_http_serving_share(s: ObjRef<ServingH>) -> Object<ServingH> {
        Object(ServingH(s.0.0.clone()))
    }

    /// The bound address of the serving's listener.
    fn msstd_http_serving_address(s: ObjRef<ServingH>) -> String {
        s.listener.address().to_string()
    }

    /// Waits for the next connection of the serving and returns its socket handle.
    fn msstd_http_serving_accept(s: ObjRef<ServingH>, out: Out<i64>, err: ErrOut) -> Result<(), StatusCode> {
        out.write(report(s.listener.accept_raw(None), &err)?);
        Ok(())
    }

    /// Starts the server of one serving worker on this thread: it serves the connections handed to
    /// `worker_adopt` here, and its handle closes (drains) it. The handler is only borrowed from
    /// the serving, which the worker keeps alive.
    fn msstd_http_serving_worker(
        s: ObjRef<ServingH>,
        out: Out<Object<WorkerH>>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        // SAFETY: the serving keeps the handler alive while this handle exists.
        let program = unsafe { Program::borrowed(s.handler) };
        let server = report(
            Server::start_adopting(&crate::net::root(), program, s.options.clone()),
            &err,
        )?;
        out.write(Object(WorkerH(Bound::new(server))));
        Ok(())
    }

    /// Hands the socket handle `accept` returned to the worker's server, on the worker's thread.
    fn msstd_http_worker_adopt(w: ObjRef<WorkerH>, connection: i64) -> () {
        w.adopt(connection);
    }

    /// Drains and closes the worker's server: idle connections go at once and requests in flight
    /// finish within the grace period.
    fn msstd_http_worker_close(w: ObjRef<WorkerH>) -> () {
        w.finish();
    }

    /// Closes the listener of the serving and the connections accepted and never served.
    fn msstd_http_serving_release(s: ObjRef<ServingH>) -> () {
        s.listener.close();
        crate::conn::release_unadopted(s.listener.owner_key());
    }

    // ------------------------------------------------------------------ exchange

    /// `HttpExchange.close()`.
    fn msstd_http_exchange_close(x: ObjRef<ExchH>) -> () {
        x.close();
    }

    /// `HttpExchange.headers()`.
    fn msstd_http_exchange_headers(x: ObjRef<ExchH>) -> Object<HeadersH> {
        Object(HeadersH(Bound::new(Rc::new(RefCell::new(x.headers().borrow().clone())))))
    }

    /// `HttpExchange.method()`.
    fn msstd_http_exchange_method(x: ObjRef<ExchH>) -> out Str {
        x.method_value()
    }

    /// `HttpExchange.path()`.
    fn msstd_http_exchange_path(x: ObjRef<ExchH>) -> out Str {
        x.path_value()
    }

    /// `HttpExchange.protocol()`.
    fn msstd_http_exchange_protocol(x: ObjRef<ExchH>) -> &'static str {
        x.protocol()
    }

    /// `HttpExchange.query()`.
    fn msstd_http_exchange_query(x: ObjRef<ExchH>) -> out Str {
        x.query_value()
    }

    /// `HttpExchange.read(max)`; the end of the body is `STATUS_NONE`.
    fn msstd_http_exchange_read(
        x: ObjRef<ExchH>,
        has_max: Has,
        max: i64,
        out: Out<Vec<u8>>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        chunk(x.read(opt(*has_max, max)), out, &err)
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
