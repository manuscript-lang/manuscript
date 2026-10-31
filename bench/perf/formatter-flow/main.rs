use std::{hint::black_box, sync::Arc, time::Instant};

fn fingerprint(text: &str) -> u64 {
    text.bytes().fold(0xcbf29ce484222325, |hash, c| {
        (hash ^ u64::from(c)).wrapping_mul(0x100000001b3)
    })
}

fn source(count: usize, shape: &str) -> String {
    if shape == "functions" {
        return (0..count)
            .map(|n| include_str!("function.ms").replace("_N", &format!("_{n}")))
            .collect::<Vec<_>>()
            .join("\n");
    }
    if matches!(shape, "list-flat" | "list-lines") {
        let separator = if shape == "list-lines" {
            ",\n        "
        } else {
            ", "
        };
        let items = vec!["123"; count].join(separator);
        return include_str!("list.ms").replace("123", &items);
    }
    let template = match shape {
        "flow" | "pipe" | "nonempty" | "comments" | "unicode" | "crlf" => include_str!("flow.ms"),
        "member" => include_str!("member.ms"),
        "inline" => include_str!("inline.ms"),
        "clause" => include_str!("clause.ms"),
        _ => panic!("unknown shape"),
    };
    let step = match shape {
        "pipe" => "        | .m()\n",
        "inline" | "clause" => ".m()",
        _ => "        .m()\n",
    };
    let mut steps = step.repeat(count);
    if shape == "nonempty" {
        steps.push_str("        .m(value)\n");
    }
    if shape == "comments" {
        steps.insert_str(
            steps.len() / 2 / step.len() * step.len(),
            "        # keep λ😀\n",
        );
    }
    let mut source = template.replace("{{steps}}", &steps);
    if shape == "unicode" {
        source = source.replace("text", "\"λ😀\"");
    }
    if shape == "crlf" {
        source = source.replace('\n', "\r\n");
    }
    source
}

fn main() {
    let args: Vec<_> = std::env::args().collect();
    let count: usize = args[1].parse().unwrap();
    let rounds: u32 = args[2].parse().unwrap();
    let shape = &args[3];
    assert!(count > 0 && rounds > 0);
    let source = source(count, shape);
    let file: Arc<str> = "/tmp/ms-formatter-flow-perf.ms".into();
    let output = ms_syntax::format(&file, &source).unwrap();
    assert_eq!(
        ms_syntax::format(&file, &output).unwrap(),
        output,
        "idempotence"
    );
    let expected = fingerprint(&output);
    let start = Instant::now();
    let mut sum = 0u64;
    for _ in 0..rounds {
        let formatted = ms_syntax::format(black_box(&file), black_box(&source)).unwrap();
        sum = sum.wrapping_add(black_box(fingerprint(&formatted)));
    }
    let elapsed = start.elapsed().as_nanos();
    assert_eq!(sum, expected.wrapping_mul(u64::from(rounds)));
    let rss = std::fs::read_to_string("/proc/self/status")
        .ok()
        .and_then(|status| {
            status.lines().find_map(|line| {
                line.strip_prefix("VmHWM:")
                    .and_then(|value| value.split_whitespace().next()?.parse::<u64>().ok())
            })
        });
    println!(
        "{count},{rounds},{shape},{elapsed},{expected},{},{},{}",
        source.len(),
        output.len(),
        rss.unwrap_or(0)
    );
}
