//! Natives for the server half of `@std/http.ms`: `Network.serve`, servers and exchanges.

use super::handler::Program;
use super::http_client::{chunk, limit};
use super::tls::TlsOptionsWire;
use super::{ExchH, HeadersH, NetH, ServerH, opt, report};
use crate::error::HttpErr;
use crate::http::server::{CloseError, Limits, Options, Server};
use crate::tls;
use ms_rt::ffi::{
    ErrOut, Handler, ObjRef, Object, OptInt, Out, StatusCode, abi_record, fault, native,
};
use std::time::Duration;

abi_record! {
    /// `HttpServerOptions` as the compiler lays it out for natives; `tls` is meaningful only when
    /// `tls_present` (the `Optional[TlsOptions]` flag) is nonzero.
    pub struct HttpServerOptionsWire {
        pub max_requests: OptInt,
        pub max_body_bytes: OptInt,
        pub max_response_bytes: OptInt,
        pub max_header_bytes: OptInt,
        pub timeout: OptInt,
        pub grace: OptInt,
        pub tls_present: u8,
        pub tls: TlsOptionsWire,
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

native! {
    // -------------------------------------------------------------------- server

    /// `Network.serve(address, handler, options) -> Result[HttpServer, HttpError]`; the server takes a
    /// reference to the handler closure and releases it when dropped.
    fn msrt_net_network_serve(
        net: ObjRef<NetH>,
        address: &str,
        env: Handler,
        opts: &HttpServerOptionsWire,
        out: Out<Object<ServerH>>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        let program = Program::streaming(&env);
        let limits = server_limits(
            opts.max_requests.get(),
            opts.max_body_bytes.get(),
            opts.max_response_bytes.get(),
            opts.max_header_bytes.get(),
            opts.timeout.get(),
            opts.grace.get(),
        );
        let result = (|| {
            let limits = limits.map_err(|()| HttpErr::InvalidInput)?;
            if !net.listen_allowed(address) {
                return Err(HttpErr::PermissionDenied);
            }
            let tls = if opts.tls_present != 0 {
                let mut options = opts.tls.to_options();
                if options.alpn.is_empty() {
                    options.alpn = vec!["http/1.1".to_string()];
                }
                Some(tls::server_config(&options).map_err(|_| HttpErr::InvalidInput)?)
            } else {
                None
            };
            Server::start(
                &net,
                address,
                program,
                Options {
                    limits,
                    tls,
                },
            )
            .map_err(HttpErr::from)
        })();
        out.write(Object(ServerH(report(result, &err)?)));
        Ok(())
    }

    /// `HttpServer.address()`.
    fn msrt_http_server_address(s: ObjRef<ServerH>) -> String {
        s.address().to_string()
    }

    /// `HttpServer.close()`; closing from one of its own handlers faults.
    fn msrt_http_server_close(s: ObjRef<ServerH>) -> () {
        if let Err(CloseError::FromHandler) = s.close() {
            fault("HTTP server cannot close from its own request");
        }
    }

    /// `HttpServer.wait()`.
    fn msrt_http_server_wait(s: ObjRef<ServerH>) -> u8 {
        s.wait();
        0
    }

    // ------------------------------------------------------------------ exchange

    /// `HttpExchange.close()`.
    fn msrt_http_exchange_close(x: ObjRef<ExchH>) -> () {
        x.close();
    }

    /// `HttpExchange.headers()`.
    fn msrt_http_exchange_headers(x: ObjRef<ExchH>) -> Object<HeadersH> {
        Object(HeadersH(x.headers()))
    }

    /// `HttpExchange.method()`.
    fn msrt_http_exchange_method(x: ObjRef<ExchH>) -> String {
        x.method()
    }

    /// `HttpExchange.path()`.
    fn msrt_http_exchange_path(x: ObjRef<ExchH>) -> String {
        x.path()
    }

    /// `HttpExchange.protocol()`.
    fn msrt_http_exchange_protocol(x: ObjRef<ExchH>) -> String {
        x.protocol().to_string()
    }

    /// `HttpExchange.query()`.
    fn msrt_http_exchange_query(x: ObjRef<ExchH>) -> String {
        x.query()
    }

    /// `HttpExchange.read(max)`; the end of the body is `STATUS_NONE`.
    fn msrt_http_exchange_read(
        x: ObjRef<ExchH>,
        has_max: bool,
        max: i64,
        out: Out<Vec<u8>>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        chunk(x.read(opt(has_max, max)), out, &err)
    }

    /// `HttpExchange.send_headers(status, headers)`.
    fn msrt_http_exchange_send_headers(
        x: ObjRef<ExchH>,
        status: i64,
        headers: ObjRef<HeadersH>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        let h = headers.borrow().clone();
        report(x.send_headers(status, &h), &err)
    }

    /// `HttpExchange.send(status, headers, body)`.
    fn msrt_http_exchange_send(
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
    fn msrt_http_exchange_write(x: ObjRef<ExchH>, data: &str, err: ErrOut) -> Result<(), StatusCode> {
        report(x.write(data.as_bytes()), &err)
    }

    /// `HttpExchange.write(data: Bytes)`.
    fn msrt_http_exchange_write_bytes(x: ObjRef<ExchH>, data: &[u8], err: ErrOut) -> Result<(), StatusCode> {
        report(x.write(data), &err)
    }
}
