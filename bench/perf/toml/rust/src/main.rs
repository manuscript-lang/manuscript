// Parses the generated document 200 times and prints the best run in microseconds, matching
// the Manuscript side: the same text, into a dynamic `toml::Table`.
use std::hint::black_box;
use std::time::Instant;

fn document(count: usize) -> String {
    let mut text = String::new();
    for i in 0..count {
        text.push_str(&format!(
            "[item{i}]\nid = {i}\nname = \"user{i}\"\ntags = [\"a\", \"b\"]\n"
        ));
    }
    text
}

fn main() {
    let text = document(2000);
    let mut best = u128::MAX;
    for _ in 0..200 {
        let started = Instant::now();
        let table = black_box(&text).parse::<toml::Table>().unwrap();
        black_box(&table);
        best = best.min(started.elapsed().as_micros());
    }
    println!("rust toml bytes={} best_us={best}", text.len());
}
