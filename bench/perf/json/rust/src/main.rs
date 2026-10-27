// serde_json baseline: same corpora and measurement protocol as src/main.ms and node.js.
// `Value` is the counterpart of `JsonValue`: parse builds the tree, stringify writes it.
use serde::Serialize;
use serde_json::Value;
use std::hint::black_box;
use std::time::Instant;

fn run<F: FnMut() -> usize>(mut body: F) -> u128 {
    black_box(body()); // warm-up
    let mut samples: Vec<u128> = Vec::new();
    let mut total = 0u128;
    while total < 1_000_000_000 || samples.len() < 5 {
        let started = Instant::now();
        black_box(body());
        let elapsed = started.elapsed().as_nanos();
        samples.push(elapsed);
        total += elapsed;
    }
    samples.sort();
    samples[samples.len() / 2]
}

#[derive(Serialize)]
struct Row {
    id: i64,
    name: String,
    tags: Vec<String>,
    score: f64,
    ok: bool,
}

/// The typed counterpart of `records`: derived `Serialize` over a list of structs.
fn records() {
    let rows: Vec<Row> = (0..10000)
        .map(|i| Row {
            id: i,
            name: format!("user{i}"),
            tags: vec!["a".to_string(), "b".to_string()],
            score: i as f64 * 1.0 + 0.5,
            ok: i % 2 == 0,
        })
        .collect();
    let size = serde_json::to_vec(&rows).unwrap().len();
    let ns = run(|| serde_json::to_vec(black_box(&rows)).unwrap().len());
    println!("records\tstringify\t{ns}\t{size}");
}

fn main() {
    let dir = format!("{}/../data", env!("CARGO_MANIFEST_DIR"));
    for name in std::env::args().skip(1) {
        if name == "records" {
            records();
            continue;
        }
        let text = std::fs::read(format!("{dir}/{name}.json")).expect("read corpus");
        let tree: Value = serde_json::from_slice(&text).expect("valid json");
        let size = text.len();
        let parse = run(|| {
            let v: Value = serde_json::from_slice(black_box(&text)).unwrap();
            black_box(&v);
            1
        });
        let stringify = run(|| serde_json::to_vec(black_box(&tree)).unwrap().len());
        println!("{name}\tparse\t{parse}\t{size}");
        println!("{name}\tstringify\t{stringify}\t{size}");
    }
}
