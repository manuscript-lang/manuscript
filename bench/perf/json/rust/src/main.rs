// serde_json baseline: same corpora and measurement protocol as src/main.ms and node.js.
// `Value` is the counterpart of `JsonValue`: parse builds the tree, stringify writes it.
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

fn main() {
    let dir = format!("{}/../data", env!("CARGO_MANIFEST_DIR"));
    for name in std::env::args().skip(1) {
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
