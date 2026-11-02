//! Deterministic LSP workloads; setup/checking is excluded except in completion.
use ms_lsp::analysis::{Document, Documents, Options, compile_source};
use ms_lsp::json::{Escape, Json};
use ms_lsp::{completion, nav, semantic, symbols, text, uri};
use std::fmt::Write;
use std::hint::black_box;
use std::time::Instant;

fn fingerprint(text: &str) -> u64 {
    text.bytes().fold(0xcbf29ce484222325, |hash, byte| {
        (hash ^ u64::from(byte)).wrapping_mul(0x100000001b3)
    })
}

fn main() {
    let args: Vec<_> = std::env::args().collect();
    let mode = &args[1];
    let count: usize = args[2].parse().unwrap();
    let rounds: u32 = args[3].parse().unwrap();
    let shape = args.get(4).map(String::as_str).unwrap_or("ascii");
    assert!(count > 0 && rounds > 0);
    let mut source = String::new();
    for i in 0..count {
        source.push_str(&include_str!("function.ms").replace("item_N", &format!("item_{i}")));
        source.push('\n');
    }
    if shape == "references" {
        let lines: Vec<_> = include_str!("references.ms").lines().collect();
        source.clear();
        writeln!(source, "{}", lines[0]).unwrap();
        for i in 0..count {
            writeln!(
                source,
                "{}",
                lines[1].replace("_item_N", &format!("_item_{i}"))
            )
            .unwrap();
        }
        writeln!(source, "{}", lines[2]).unwrap();
    }
    if shape == "unicode" {
        source = source.replace("# sample", "# 😀 αβ");
    }
    if shape == "crlf" {
        source = source.replace('\n', "\r\n");
    }
    if shape == "long" {
        source.insert_str(0, &format!("# {}\n", "x".repeat(100_000)));
    }
    if shape == "tail" {
        writeln!(source, "# {}", "x".repeat(1_000_000)).unwrap();
    }
    if shape.starts_with("spaces-") {
        let length = shape.rsplit('-').next().unwrap();
        source.push_str(&" ".repeat(length.parse().unwrap()));
        source.push('\n');
        if shape.starts_with("spaces-crlf-") {
            source = source.replace('\n', "\r\n");
        }
    }
    let file = "/tmp/ms-lsp-perf.ms";
    let doc = Document::new(uri::file_uri(file), source);
    let analysis = compile_source(file, &doc.text, &Options::default());
    assert!(analysis.success(), "{:?}", analysis.diagnostics.first());
    let index = analysis.index();
    let needle = match mode.as_str() {
        "hover-first" => doc.text.find("123").unwrap(),
        "references-first" => doc.text.find("value +").unwrap(),
        "hover-name" | "references" => doc.text.rfind("value +").unwrap(),
        "hover-blank" => doc.text.rfind("    return").unwrap(),
        _ => doc.text.rfind("123").unwrap(),
    };
    let position = text::position(&doc.text, needle);
    let query = || -> u64 {
        match mode.as_str() {
            "hover" | "hover-first" | "hover-name" | "hover-blank" => nav::at(
                black_box(&analysis),
                black_box(&doc),
                position,
                black_box(index),
            )
            .map_or(0, |hit| {
                (hit.offset as u64).wrapping_add(fingerprint(&hit.text))
            }),
            "symbols" => {
                fingerprint(&symbols::document_symbols(&analysis, &doc).compact(Escape::Plain))
            }
            "semantic" => fingerprint(
                &semantic::semantic_tokens(Some(&analysis), index, &doc).compact(Escape::Plain),
            ),
            "references" | "references-first" => fingerprint(
                &Json::Arr(nav::references_with_index(
                    &analysis, index, &doc, position, true,
                ))
                .compact(Escape::Plain),
            ),
            "completion" => fingerprint(
                &Json::Arr(
                    completion::completion_at(&doc, &Documents::new(), position, false)
                        .unwrap()
                        .iter()
                        .map(|item| item.json())
                        .collect(),
                )
                .compact(Escape::Plain),
            ),
            "index" => ms_lsp::index::source_index(&analysis)
                .iter()
                .fold(0u64, |sum, entry| {
                    sum.rotate_left(7)
                        ^ fingerprint(&entry.key)
                        ^ fingerprint(&entry.name)
                        ^ fingerprint(entry.file.as_str())
                        ^ entry.offset as u64
                        ^ entry.end as u64
                }),
            "format" => fingerprint(&ms_syntax::format(&file.into(), &doc.text).unwrap()),
            _ => panic!("unknown mode"),
        }
    };
    let expected = black_box(query());
    let start = Instant::now();
    let mut checksum = 0u64;
    for _ in 0..rounds {
        checksum = checksum.wrapping_add(black_box(query()));
    }
    let elapsed = start.elapsed().as_nanos();
    assert_eq!(checksum, expected.wrapping_mul(u64::from(rounds)));
    // Whole-process high water includes setup/checking, not just the query.
    let rss = std::fs::read_to_string("/proc/self/status")
        .ok()
        .and_then(|status| {
            status.lines().find_map(|line| {
                line.strip_prefix("VmHWM:")
                    .and_then(|value| value.split_whitespace().next()?.parse::<u64>().ok())
            })
        });
    println!(
        "{mode},{count},{rounds},{shape},{elapsed},{expected},{},{}",
        doc.text.len(),
        rss.unwrap_or(0)
    );
}
