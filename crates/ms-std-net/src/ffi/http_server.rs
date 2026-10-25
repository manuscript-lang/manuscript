//! Natives for the server half of `@std/http.ms`: `Network.serve`, servers and exchanges.

use super::handler::Program;
use super::http_client::{chunk, limit};
use super::tls::TlsOptionsWire;
use super::{ExchH, HeadersH, NetH, ServerH, opt, report};
use crate::error::HttpErr;
use crate::http::server::{CloseError, Limits, Options, Server};
use crate::tls;
use ms_rt::ffi::{
    ErrOut, Handler, ObjRef, Object, OptInt, Out, RecList, StatusCode, Str, abi_record, fault,
    native,
};
use std::time::Duration;

abi_record! {
    /// `HttpServerOptions` as the compiler lays it out for natives; `tls` is meaningful only when
    /// `tls_present` (the `Optional[TlsOptions]` flag) is nonzero.
    pub struct HttpServerOptionsWire {
        pub event_capacity: OptInt,
        pub max_requests: OptInt,
        pub max_connections: OptInt,
        pub max_body_bytes: OptInt,
        pub max_response_bytes: OptInt,
        pub max_header_bytes: OptInt,
        pub timeout: OptInt,
        pub header_timeout: OptInt,
        pub idle_timeout: OptInt,
        pub write_timeout: OptInt,
        pub grace: OptInt,
        pub tls_present: u8,
        pub tls: TlsOptionsWire,
    }
}

abi_record! {
    /// Snapshot of independent per-member HTTP counters.
    pub struct HttpStatsWire {
        pub requests: i64,
        pub admitted: i64,
        pub rejected: i64,
        pub completed: i64,
        pub aborted: i64,
        pub timed_out: i64,
        pub faulted: i64,
        pub active_requests: i64,
        pub active_connections: i64,
        pub request_body_bytes: i64,
        pub response_body_bytes: i64,
        pub dropped_events: i64,
        pub connections: i64,
        pub rejected_connections: i64,
        pub accept_errors: i64,
        pub protocol_errors: i64,
        pub tls_failures: i64,
        pub connection_timeouts: i64,
    }
}

abi_record! {
    /// One bounded terminal HTTP event.
    pub struct HttpEventWire {
        pub method: Str,
        pub path: Str,
        pub route: Str,
        pub peer_address: Str,
        pub scheme: Str,
        pub status: i64,
        pub elapsed: i64,
        pub request_body_bytes: i64,
        pub response_body_bytes: i64,
        pub outcome: Str,
        pub rejected: u8,
    }
}

fn server_limits(opts: &HttpServerOptionsWire) -> Result<Limits, ()> {
    let unlimited = usize::MAX;
    let size = |v: Option<i64>| -> Result<usize, ()> {
        Ok(limit(v)?.map_or(unlimited, |n| n.min(unlimited as u64) as usize))
    };
    let admission = size(opts.max_requests.get())?;
    let header = size(opts.max_header_bytes.get())?;
    let connections = size(opts.max_connections.get())?;
    if admission == 0 || header == 0 || connections == 0 {
        return Err(());
    }
    let event_capacity = match opts.event_capacity.get() {
        None => 0,
        Some(n) if n > 0 => usize::try_from(n).map_err(|_| ())?,
        _ => return Err(()),
    };
    Ok(Limits {
        event_capacity,
        admission,
        connections,
        body: size(opts.max_body_bytes.get())?,
        response: size(opts.max_response_bytes.get())?,
        header,
        timeout: limit(opts.timeout.get())?.map(Duration::from_nanos),
        grace: limit(opts.grace.get())?.map(Duration::from_nanos),
        header_timeout: limit(opts.header_timeout.get())?.map(Duration::from_nanos),
        idle_timeout: limit(opts.idle_timeout.get())?.map(Duration::from_nanos),
        write_timeout: limit(opts.write_timeout.get())?.map(Duration::from_nanos),
    })
}

/// Both handler forms share option validation, permissions and TLS negotiation.
pub(crate) fn server_options(
    net: &crate::net::Network,
    address: &str,
    opts: &HttpServerOptionsWire,
    streaming: bool,
) -> Result<Options, HttpErr> {
    let limits = server_limits(opts).map_err(|()| HttpErr::InvalidInput)?;
    if !net.listen_allowed(address) {
        return Err(HttpErr::PermissionDenied);
    }
    let tls = if opts.tls_present != 0 {
        let mut options = opts.tls.to_options();
        if options.alpn.is_empty() {
            options.alpn = vec!["h2".to_string(), "http/1.1".to_string()];
        }
        Some(tls::server_config(&options).map_err(|_| HttpErr::InvalidInput)?)
    } else {
        None
    };
    Ok(Options {
        limits,
        streaming,
        tls,
    })
}

native! {
    // -------------------------------------------------------------------- server

    /// `Network.serve(address, handler, options) -> Result[HttpServer, HttpError]`.
    fn msrt_net_network_serve(
        net: ObjRef<NetH>,
        address: &str,
        env: Handler,
        opts: &HttpServerOptionsWire,
        out: Out<Object<ServerH>>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        let options = report(server_options(&net, address, opts, false), &err)?;
        let result = Server::start(&net, address, Program::buffered(&env), options)
            .map_err(HttpErr::from);
        out.write(Object(ServerH(report(result, &err)?)));
        Ok(())
    }

    /// `Network.serve_stream(address, handler, options) -> Result[HttpServer, HttpError]`.
    fn msrt_net_network_serve_stream(
        net: ObjRef<NetH>,
        address: &str,
        env: Handler,
        opts: &HttpServerOptionsWire,
        out: Out<Object<ServerH>>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        let options = report(server_options(&net, address, opts, true), &err)?;
        let result = Server::start(&net, address, Program::streaming(&env), options)
            .map_err(HttpErr::from);
        out.write(Object(ServerH(report(result, &err)?)));
        Ok(())
    }

    /// Activation and drain state, including signal-driven shutdown.
    fn msrt_http_server_is_ready(s: ObjRef<ServerH>) -> bool {
        s.is_ready()
    }

    /// Per-member counters, independent of optional event delivery.
    fn msrt_http_server_stats(s: ObjRef<ServerH>, out: Out<HttpStatsWire>) -> () {
        let stats = s.stats();
        out.write(HttpStatsWire {
            requests: stats.requests,
            admitted: stats.admitted,
            rejected: stats.rejected,
            completed: stats.completed,
            aborted: stats.aborted,
            timed_out: stats.timed_out,
            faulted: stats.faulted,
            active_requests: stats.active_requests,
            active_connections: stats.active_connections,
            request_body_bytes: stats.request_body_bytes,
            response_body_bytes: stats.response_body_bytes,
            dropped_events: stats.dropped_events,
            connections: stats.connections,
            rejected_connections: stats.rejected_connections,
            accept_errors: stats.accept_errors,
            protocol_errors: stats.protocol_errors,
            tls_failures: stats.tls_failures,
            connection_timeouts: stats.connection_timeouts,
        });
    }

    /// Drains events synchronously; never invokes application code.
    fn msrt_http_server_take_events(s: ObjRef<ServerH>, out: Out<RecList<HttpEventWire>>) -> () {
        out.write(RecList::new(s.take_events().into_iter().map(|event| HttpEventWire {
            method: Str::new(&event.method),
            path: Str::new(&event.path),
            route: Str::new(&event.route),
            peer_address: Str::new(&event.peer_address),
            scheme: Str::new(&event.scheme),
            status: event.status,
            elapsed: event.elapsed,
            request_body_bytes: event.request_body_bytes,
            response_body_bytes: event.response_body_bytes,
            outcome: Str::new(&event.outcome),
            rejected: u8::from(event.rejected),
        })));
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

    /// Explicit bounded route label for access events.
    fn msrt_http_exchange_set_route(x: ObjRef<ExchH>, route: &str) -> () { x.set_route(route); }

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

    /// Direct transport peer, independent of forwarded headers.
    fn msrt_http_exchange_peer_address(x: ObjRef<ExchH>) -> String { x.peer_address() }

    /// Scheme established by the accepted transport.
    fn msrt_http_exchange_scheme(x: ObjRef<ExchH>) -> &'static str { x.scheme() }

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
        has_content_length: bool,
        content_length: i64,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        let h = headers.borrow().clone();
        report(x.send_headers(status, &h, opt(has_content_length, content_length)), &err)
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
