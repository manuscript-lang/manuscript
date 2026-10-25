//! Whole-request handlers for tests and benchmarks, adapted onto the exchange dispatch.

use crate::error::HttpErr;
use crate::http::exchange::Exchange;
use crate::http::headers::Headers;
use crate::http::server::{Dispatch, Outcome};
use std::rc::Rc;

/// A fully buffered request.
#[derive(Debug)]
pub struct Request {
    pub method: String,
    pub path: String,
    pub query: String,
    pub headers: Headers,
    pub body: Vec<u8>,
    pub protocol: &'static str,
}

/// A buffered response.
#[derive(Debug)]
pub struct Reply {
    pub status: i64,
    pub headers: Headers,
    pub body: Vec<u8>,
}

/// A handler over whole requests; wrap it in [`Buffered`] to serve it.
pub trait Handle {
    fn handle(&self, request: Request) -> Outcome<Reply>;
}

/// Serves a [`Handle`]: reads the body, calls it, and sends the reply with a known length.
pub struct Buffered<T>(pub T);

impl<T: Handle> Dispatch for Buffered<T> {
    fn streaming(&self, exchange: Rc<Exchange>) -> Outcome<Result<(), HttpErr>> {
        let mut body = Vec::new();
        loop {
            match exchange.read(None) {
                Ok(Some(chunk)) => body.extend_from_slice(&chunk),
                Ok(None) => break,
                Err(_) => return Outcome::Done(Err(HttpErr::Closed)),
            }
        }
        let request = Request {
            method: exchange.method(),
            path: exchange.path(),
            query: exchange.query(),
            headers: exchange.headers().borrow().clone(),
            body,
            protocol: exchange.protocol(),
        };
        match self.0.handle(request) {
            Outcome::Done(reply) => {
                Outcome::Done(exchange.send_response(reply.status, &reply.headers, &reply.body))
            }
            Outcome::Cancelled => Outcome::Cancelled,
            Outcome::Fault(text) => Outcome::Fault(text),
        }
    }
}
