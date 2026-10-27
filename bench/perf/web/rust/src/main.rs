//! The same /health, /user/<id> and /top?n= endpoints as ../ms and ../go on hyper, for a Rust baseline.
//! Usage: server <port> <data-dir>  (the data dir is accepted for run.sh; /io is not served).
use std::convert::Infallible;
use std::fmt::Write;

use bytes::Bytes;
use http_body_util::Full;
use hyper::body::Incoming;
use hyper::server::conn::http1;
use hyper::service::service_fn;
use hyper::{Request, Response, StatusCode};
use hyper_util::rt::TokioIo;
use tokio::net::TcpListener;

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
        let _ = write!(out, "{{\"id\":{best},\"score\":{}}}", score(best));
        prev_id = best;
        prev_score = score(best);
    }
    out.push_str("]\n");
    out
}

fn reply(status: u16, text: String) -> Response<Full<Bytes>> {
    let mut r = Response::new(Full::new(Bytes::from(text)));
    *r.status_mut() = StatusCode::from_u16(status).unwrap();
    r
}

async fn handle(req: Request<Incoming>) -> Result<Response<Full<Bytes>>, Infallible> {
    let path = req.uri().path();
    let res = if path == "/health" {
        reply(200, "ok\n".into())
    } else if path == "/top" {
        match req.uri().query().and_then(|q| q.strip_prefix("n=")).and_then(|n| n.parse::<i64>().ok()) {
            Some(k) if (1..=50).contains(&k) => reply(200, top(k)),
            _ => reply(400, "bad n\n".into()),
        }
    } else if let Some(id) = path.strip_prefix("/user/").and_then(|s| s.parse::<i64>().ok()).filter(|i| (0..1000).contains(i)) {
        reply(200, format!("{{\"id\":{id},\"name\":\"user{id}\",\"score\":{}}}\n", score(id)))
    } else {
        reply(404, "not found\n".into())
    };
    Ok(res)
}

fn main() {
    let port = std::env::args().nth(1).expect("port");
    let rt = tokio::runtime::Builder::new_multi_thread().worker_threads(2).enable_all().build().unwrap();
    rt.block_on(async move {
        let listener = TcpListener::bind(format!("127.0.0.1:{port}")).await.unwrap();
        loop {
            let (stream, _) = listener.accept().await.unwrap();
            stream.set_nodelay(true).ok();
            tokio::spawn(async move {
                let _ = http1::Builder::new().serve_connection(TokioIo::new(stream), service_fn(handle)).await;
            });
        }
    });
}
