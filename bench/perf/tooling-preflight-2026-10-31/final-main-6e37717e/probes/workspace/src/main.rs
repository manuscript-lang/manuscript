use ms_lsp::analysis::{Document, Documents};
use ms_lsp::json::{Escape, Json};
use ms_lsp::{uri, workspace};
use std::hint::black_box;
use std::time::Instant;

fn fingerprint(text: &str) -> u64 {
    text.bytes().fold(0xcbf29ce484222325, |a, b| (a ^ u64::from(b)).wrapping_mul(0x100000001b3))
}

fn main() {
    let args: Vec<_> = std::env::args().collect();
    let modules: usize = args[1].parse().unwrap();
    let query = &args[2];
    let rounds: u32 = args[3].parse().unwrap();
    let root = "/workspace/perf-evidence/lsp-workspace-throughput-fixture-v1";
    let _ = std::fs::remove_dir_all(root);
    std::fs::create_dir_all(root).unwrap();
    std::fs::write(format!("{root}/ms.toml"), include_str!("../ms.toml")).unwrap();
    let source = include_str!("../main.ms");
    std::fs::write(format!("{root}/main.ms"), source).unwrap();
    for i in 0..modules {
        let name = if i == 0 { "only_target".to_string() } else { format!("value_{i}") };
        std::fs::write(format!("{root}/module_{i}.ms"), include_str!("../module.ms").replace("item", &name)).unwrap();
    }
    let d = Document::new(uri::file_uri(&format!("{root}/main.ms")), source);
    let docs = Documents::from([(d.uri.clone(), d)]);
    let roots = vec![root.to_string()];
    let expected = if query.is_empty() { modules + 1 } else if query == "only_target" { 1 } else { 0 };
    let work = || {
        let symbols = workspace::workspace_symbols(&docs, &roots, query, None).unwrap();
        assert_eq!(symbols.len(), expected);
        fingerprint(&Json::Arr(symbols).compact(Escape::Plain))
    };
    let expected_fingerprint = black_box(work());
    let start = Instant::now();
    let mut sum = 0u64;
    for _ in 0..rounds { sum = sum.wrapping_add(black_box(work())); }
    let elapsed = start.elapsed().as_nanos();
    assert_eq!(sum, expected_fingerprint.wrapping_mul(u64::from(rounds)));
    println!("{modules},{query},{rounds},{elapsed},{expected},{expected_fingerprint}");
    std::fs::remove_dir_all(root).unwrap();
}
