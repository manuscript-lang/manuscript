//! The `bench/web-compare` server (/health, /user/<id>, /top?n=K) on the native
//! HTTP server, with the handler in Rust. Measures the transport's ceiling.
extern crate ms_rt;
use ms_std_net::http::headers::Headers;
use ms_std_net::http::server::{Dispatch, Limits, Options, Outcome, Reply, Request, Server};
use ms_std_net::net::Network;
use std::rc::Rc;

fn score(id: i64) -> i64 {
    id * 7919 % 1000
}

fn pick_after(prev_id: i64, prev_score: i64) -> i64 {
    let (mut best, mut best_score) = (-1, -1);
    for id in 0..1000 {
        let sc = score(id);
        if (sc < prev_score || (sc == prev_score && id > prev_id)) && sc > best_score {
            best = id;
            best_score = sc;
        }
    }
    best
}

fn top(k: i64) -> String {
    let mut out = String::from("[");
    let (mut prev_id, mut prev_score) = (-1, 1000);
    for n in 0..k {
        let best = pick_after(prev_id, prev_score);
        if n > 0 {
            out.push(',');
        }
        out.push_str(&format!("{{\"id\":{best},\"score\":{}}}", score(best)));
        prev_id = best;
        prev_score = score(best);
    }
    out.push_str("]\n");
    out
}

fn reply(status: i64, text: String) -> Outcome<Reply> {
    Outcome::Done(Reply {
        status,
        headers: Headers::new(),
        body: text.into_bytes(),
    })
}

struct App;

impl Dispatch for App {
    fn buffered(&self, r: Request) -> Outcome<Reply> {
        if r.path == "/health" {
            return reply(200, "ok\n".into());
        }
        if r.path == "/top" {
            return match r
                .query
                .strip_prefix("n=")
                .and_then(|v| v.parse::<i64>().ok())
            {
                Some(k) if (1..=50).contains(&k) => reply(200, top(k)),
                _ => reply(400, "bad n\n".into()),
            };
        }
        if let Some(id) = r.path.strip_prefix("/user/") {
            if let Ok(id) = id.parse::<i64>() {
                if (0..1000).contains(&id) {
                    let body = format!(
                        "{{\"id\":{id},\"name\":\"user{id}\",\"score\":{}}}\n",
                        score(id)
                    );
                    return reply(200, body);
                }
            }
        }
        reply(404, "not found\n".into())
    }

    fn streaming(
        &self,
        _: Rc<ms_std_net::http::exchange::Exchange>,
    ) -> Outcome<Result<(), ms_std_net::error::HttpErr>> {
        Outcome::Done(Ok(()))
    }
}

fn main() {
    let address = std::env::args().nth(1).unwrap_or("127.0.0.1:18084".into());
    let net = Network::new_root();
    let options = Options {
        limits: Limits::default(),
        streaming: false,
        tls: None,
    };
    let server = Server::start(&net, &address, Box::new(App), options).expect("listen");
    server.wait();
}
