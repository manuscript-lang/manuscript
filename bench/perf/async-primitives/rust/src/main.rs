// Rust (tokio) port of main.ms: the same modes with tasks and channels. TOKIO_THREADS=1 uses the current-thread
// runtime, anything else the multi-thread one with that many workers.
use std::time::Instant;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::mpsc;

fn work(a: i64) -> i64 {
    a * 2 + 1
}

async fn run_spawn(n: i64) -> i64 {
    let mut total = 0;
    for i in 0..n {
        total += tokio::spawn(async move { work(i) }).await.unwrap();
    }
    total
}

async fn run_batch(n: i64) -> i64 {
    let mut total = 0;
    let mut done = 0;
    while done < n {
        let mut handles = Vec::with_capacity(64);
        for i in 0..64 {
            handles.push(tokio::spawn(async move { work(done + i) }));
        }
        for handle in handles {
            total += handle.await.unwrap();
        }
        done += 64;
    }
    total
}

async fn run_pingpong(n: i64) -> i64 {
    let (request_tx, mut request_rx) = mpsc::channel::<i64>(1);
    let (reply_tx, mut reply_rx) = mpsc::channel::<i64>(1);
    let server = tokio::spawn(async move {
        while let Some(value) = request_rx.recv().await {
            reply_tx.send(value + 1).await.unwrap();
        }
    });
    let mut total = 0;
    for i in 0..n {
        request_tx.send(i).await.unwrap();
        total += reply_rx.recv().await.unwrap();
    }
    drop(request_tx);
    server.await.unwrap();
    total
}

async fn run_stream(n: i64) -> i64 {
    let (tx, mut rx) = mpsc::channel::<i64>(64);
    let writer = tokio::spawn(async move {
        for i in 0..n {
            tx.send(i).await.unwrap();
        }
    });
    let mut total = 0;
    while let Some(value) = rx.recv().await {
        total += value;
    }
    writer.await.unwrap();
    total
}

async fn run_sleep(n: i64) -> i64 {
    for _ in 0..n {
        tokio::time::sleep(std::time::Duration::from_nanos(0)).await;
    }
    n
}

async fn run_echo(n: i64) -> i64 {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let server = tokio::spawn(async move {
        let (mut conn, _) = listener.accept().await.unwrap();
        let mut buf = vec![0u8; 65536];
        loop {
            let got = conn.read(&mut buf).await.unwrap();
            if got == 0 {
                return;
            }
            conn.write_all(&buf[..got]).await.unwrap();
        }
    });
    let mut client = TcpStream::connect(address).await.unwrap();
    client.set_nodelay(true).unwrap();
    let message = b"0123456789012345678901234567890123456789012345678901234567890123";
    let mut buf = vec![0u8; 65536];
    let mut total = 0;
    for _ in 0..n {
        client.write_all(message).await.unwrap();
        total += client.read(&mut buf).await.unwrap() as i64;
    }
    drop(client);
    server.await.unwrap();
    total
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let mode = args[1].clone();
    let n: i64 = args[2].parse().unwrap();
    let threads: usize = std::env::var("TOKIO_THREADS").ok().and_then(|v| v.parse().ok()).unwrap_or(1);
    let runtime = if threads <= 1 {
        tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap()
    } else {
        tokio::runtime::Builder::new_multi_thread().worker_threads(threads).enable_all().build().unwrap()
    };
    let before = Instant::now();
    let total = runtime.block_on(async {
        // The work runs as a task, as main does in Manuscript and Go, so a wake is task to task.
        tokio::spawn(async move {
            match mode.as_str() {
                "inline" | "here" => run_spawn(n).await,
                "batch" | "batch-here" => run_batch(n).await,
                "pingpong" => run_pingpong(n).await,
                "stream" => run_stream(n).await,
                "sleep" => run_sleep(n).await,
                "echo" => run_echo(n).await,
                _ => 0,
            }
        })
        .await
        .unwrap()
    });
    println!("{} total {} ns/op {}", args[1], total, before.elapsed().as_nanos() as i64 / n);
}
