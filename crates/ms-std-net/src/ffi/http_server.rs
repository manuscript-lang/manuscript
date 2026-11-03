//! Natives for the server half of `@std/net/http.ms`: `Network.serve`, servers and exchanges.

use super::handler::Program;
use super::http_client::{chunk, limit};
use super::tls::tls_options;
use super::{ExchH, HeadersH, ServingH, opt, report};
use crate::error::HttpErr;
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

native! {
    // -------------------------------------------------------------------- server

    /// `serving(options)`: the limits, TLS settings and admission count that every connection of
    /// one `serve` call shares.
    fn msstd_http_serving_new(
        opts: &HttpServerOptionsWire,
        out: Out<Object<ServingH>>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        out.write(Object(ServingH(report(server_options(opts), &err)?)));
        Ok(())
    }

    /// `Serving.connect(handler, connection)`: serves the socket handle `Listener.accept_raw`
    /// returned, on this thread, and returns when the connection has ended. The handler is only
    /// borrowed: the promise that calls this keeps it alive.
    fn msstd_http_serving_connect(
        serving: ObjRef<ServingH>,
        env: Handler,
        connection: i64,
    ) -> () {
        let options = Options {
            limits: serving.limits.clone(),
            admitted: serving.admitted.clone(),
            tls: serving.tls.clone(),
        };
        if let Ok(server) = Server::start_adopting(&crate::net::root(), Program::streaming(&env), options) {
            server.serve_connection(connection);
        }
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
