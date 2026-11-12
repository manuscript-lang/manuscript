use ms_syntax::{doc::comments_above, format, parser::parse};
use std::{hint::black_box, sync::Arc, time::Instant};
fn main() {
    let file = Arc::from("qualify.ms");
    let cases = [
        ("fn", 1),
        ("fn", 64),
        ("imports", 1),
        ("imports", 4),
        ("imports", 64),
        ("imports", 1000),
        ("imports", 8000),
        ("same", 4),
        ("same", 1000),
        ("canonical", 1000),
        ("doc", 1),
        ("doc", 4000),
        ("blank", 8000),
    ];
    for (case, n) in cases {
        if !((case == "fn")
            || (case == "imports" && n <= 64)
            || case == "same"
            || case == "canonical")
        {
            continue;
        }
        let mut src = match case {
            "fn" => (0..n)
                .map(|i| format!("fn f{i}() Int: return 1\n"))
                .collect(),
            "doc" => format!("/*\n{}*/\nfn f() Int: return 1\n", "hello\n".repeat(n)),
            "blank" => format!("/*\n{}hello\n*/\nfn f() Int: return 1\n", "\n".repeat(n)),
            _ => (0..n)
                .map(|i| {
                    format!(
                        "import a{i} from \"{}\"\n",
                        if case == "same" {
                            "m.ms".to_string()
                        } else {
                            format!("m{i:05}.ms")
                        }
                    )
                })
                .collect(),
        };
        if case == "canonical" {
            src = format(&file, &src).unwrap();
        }
        let doc = case == "doc" || case == "blank";
        let offset = src.find("fn f").unwrap_or(0);
        let run = || {
            if doc {
                comments_above(black_box(&src), offset, Some(0))
            } else {
                format(&file, black_box(&src)).unwrap()
            }
        };
        parse(&file, &src).unwrap();
        let expected = run();
        if !doc {
            parse(&file, &expected).unwrap();
            assert_eq!(format(&file, &expected).unwrap(), expected);
        } else if case == "blank" {
            assert_eq!(expected, "hello");
        } else {
            assert_eq!(expected, vec!["hello"; n].join("\n"));
        }
        let checksum = expected
            .bytes()
            .fold(0u64, |a, b| a.wrapping_mul(31).wrapping_add(b as u64));
        for _ in 0..3 {
            assert_eq!(run(), expected);
        }
        let t = Instant::now();
        black_box(run());
        let elapsed = t.elapsed().as_secs_f64();
        let batch = (0.003 / elapsed).clamp(1., 5000.) as usize;
        let mut samples = Vec::new();
        for _ in 0..9 {
            let t = Instant::now();
            for _ in 0..batch {
                black_box(run());
            }
            samples.push(t.elapsed().as_secs_f64() * 1e6 / batch as f64);
        }
        println!(
            "{case} n={n} bytes={} checksum={checksum} batch={batch} samples_us={samples:?}",
            src.len()
        );
    }
}
