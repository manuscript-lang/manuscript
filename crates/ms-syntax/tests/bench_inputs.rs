use std::path::PathBuf;
use std::process::{Command, Output};

struct Inputs(PathBuf);

impl Inputs {
    fn new(name: &str) -> Self {
        let nonce = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let path = std::env::temp_dir().join(format!(
            "ms-syntax-bench-{name}-{}-{nonce}",
            std::process::id()
        ));
        std::fs::create_dir(&path).unwrap();
        Self(path)
    }

    fn bench(&self, sources: &[&str]) -> Output {
        let mut command = Command::new(env!("CARGO_BIN_EXE_ms-syntax"));
        command.arg("bench");
        for (index, source) in sources.iter().enumerate() {
            let path = self.0.join(format!("input-{index}.ms"));
            std::fs::write(&path, source).unwrap();
            command.arg(path);
        }
        command.output().unwrap()
    }
}

impl Drop for Inputs {
    fn drop(&mut self) {
        std::fs::remove_dir_all(&self.0).unwrap();
    }
}

#[test]
fn parser_bench_refuses_invalid_sources_without_reporting_throughput() {
    let inputs = Inputs::new("invalid");
    for sources in [
        vec!["fn broken(\n"],
        vec!["fn valid() Int: 1\n", "fn broken(\n"],
        vec!["fn broken(\n", "fn valid() Int: 1\n"],
    ] {
        let output = inputs.bench(&sources);
        assert_eq!(output.status.code(), Some(1));
        assert!(output.stdout.is_empty(), "{output:?}");
        let error = String::from_utf8(output.stderr).unwrap();
        assert!(error.contains("unterminated delimiter"), "{error}");
        assert!(error.contains(".ms:2:1: parse:"), "{error}");
    }
}

#[test]
fn parser_bench_reports_throughput_for_valid_sources() {
    let inputs = Inputs::new("valid");
    let sources = ["fn first() Int: 1\n", "fn second() Int: 2\n"];
    let output = inputs.bench(&sources);
    assert!(output.status.success(), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    let report = String::from_utf8(output.stdout).unwrap();
    let bytes = sources.iter().map(|source| source.len()).sum::<usize>();
    assert!(
        report.starts_with(&format!("2 files, {bytes} bytes:")),
        "{report}"
    );
    assert!(report.contains("MB/s"), "{report}");
}
