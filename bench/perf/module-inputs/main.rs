//! Build against a release ms-driver; README.md describes the paired protocol.
use ms_driver::{LoadOptions, load_file};
use std::{path::Path, time::Instant};

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let entry = &args[1];
    let count: usize = args[2].parse().unwrap();
    let iterations: usize = args[3].parse().unwrap();
    let syms = Default::default();
    let mut elapsed = 0.0;
    for _ in 0..iterations {
        let start = Instant::now();
        let graph = load_file(syms, entry, LoadOptions::default());
        elapsed += start.elapsed().as_secs_f64();
        assert!(graph.diagnostics.is_empty(), "{:?}", graph.diagnostics);
        assert_eq!(graph.modules.len(), count + 1);
        assert_eq!(graph.entry, "main.ms");
        for (i, module) in graph.modules.iter().take(count).enumerate() {
            assert_eq!(syms.str(module.file), format!("f{i}.ms"));
        }
        let expected: Vec<_> = std::iter::once(entry.to_string())
            .chain((0..count).map(|i| {
                Path::new(entry)
                    .parent()
                    .unwrap()
                    .join(format!("f{i}.ms"))
                    .to_str()
                    .unwrap()
                    .to_string()
            }))
            .collect();
        let actual: Vec<_> = graph
            .inputs
            .into_iter()
            .filter(|p| p.ends_with(".ms"))
            .collect();
        assert_eq!(actual, expected);
    }
    println!("{:.9}", elapsed * 1000.0 / iterations as f64);
}
