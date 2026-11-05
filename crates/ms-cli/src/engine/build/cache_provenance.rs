//! Forces publication/cache interleavings with real native executables and distinct source keys.

use super::*;
use crate::backend::BuildType;
use ms_build::native::BuildStage;
use std::path::PathBuf;
use std::process::Command;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Mutex, MutexGuard};

// Another fixture's fork can inherit a writable executable descriptor until its exec.
// Isolate independent fixture lifetimes; the forced A/B publication ordering stays inside
// one fixture and the separate CLI controls still run concurrent compiler processes.
static NATIVE_FIXTURE: Mutex<()> = Mutex::new(());

struct Fixture {
    root: PathBuf,
    _native: MutexGuard<'static, ()>,
}
impl Fixture {
    fn new(name: &str) -> Self {
        let native = NATIVE_FIXTURE
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        static NEXT: AtomicUsize = AtomicUsize::new(0);
        let dir = std::env::temp_dir().join(format!(
            "ms-build-provenance-{name}-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        std::fs::create_dir(&dir).unwrap();
        Self {
            root: dir,
            _native: native,
        }
    }
    fn source(&self, first: bool) -> PathBuf {
        let (name, contents) = if first {
            ("first.ms", include_str!("tests/first.ms"))
        } else {
            ("second.ms", include_str!("tests/second.ms"))
        };
        let path = self.root.join(name);
        std::fs::write(&path, contents).unwrap();
        path
    }
    fn cache(&self, key: &str, mode: ms_build::cache::Mode) -> BuildCache {
        BuildCache {
            mode,
            directory: self.root.join("cache"),
            key: key.into(),
        }
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.root);
    }
}

fn prepare(source: &Path, output: &Path) -> BuildStage {
    let backend = Engine::new(ms_build::Native);
    let mut compiled = compile(
        ms_syntax::Names::global(),
        &backend,
        source.to_str().unwrap(),
        false,
    )
    .unwrap_or_else(|_| panic!("fixture must compile: {}", source.display()));
    let stage = BuildStage::for_output(output).unwrap();
    backend
        .build_executable(
            &mut compiled,
            &stage.path().join("program.exe"),
            BuildType::Debug,
            &[],
        )
        .unwrap();
    stage
}

fn status(path: &Path) -> i32 {
    Command::new(path).status().unwrap().code().unwrap()
}
fn metadata(path: &Path) -> PathBuf {
    PathBuf::from(format!("{}.ms-build.json", path.display()))
}
fn record(cache: &BuildCache, source: &Path, artifact: &Path) -> Result<(), String> {
    cache.record(
        source.parent().unwrap().to_str().unwrap(),
        &[source.to_path_buf()],
        artifact.to_str().unwrap(),
    )
}
fn restore(cache: &BuildCache, output: &Path) {
    cache
        .lookup()
        .expect("valid cache entry")
        .restore_to(output.to_str().unwrap())
        .unwrap();
    write_metadata(output, BuildType::Debug).unwrap();
}
fn has_companion(output: &Path) -> bool {
    ms_clif_companion(output).is_some_and(|path| path.is_dir())
}
fn companion_names_match(output: &Path, expected: bool) {
    assert_eq!(has_companion(output), expected);
    if expected {
        let companion = ms_clif_companion(output).unwrap();
        let files: Vec<_> = std::fs::read_dir(companion.join("Contents/Resources/DWARF"))
            .unwrap()
            .map(|file| file.unwrap().file_name())
            .collect();
        assert_eq!(files, vec![output.file_name().unwrap().to_os_string()]);
    }
}
fn no_stages(dir: &Path) {
    assert!(std::fs::read_dir(dir).unwrap().all(|entry| {
        !entry
            .unwrap()
            .file_name()
            .to_string_lossy()
            .starts_with(".ms-build-")
    }));
}

#[test]
fn concurrent_publication_keeps_each_cached_executable() {
    for first_is_a in [true, false] {
        let fixture = Fixture::new("interleave");
        let first = fixture.source(first_is_a);
        let second = fixture.source(!first_is_a);
        let output = fixture.root.join("renamed public program");
        let a = fixture.cache("a", ms_build::cache::Mode::On);
        let b = fixture.cache("b", ms_build::cache::Mode::On);
        let stage_a = prepare(&first, &output);
        let stage_b = prepare(&second, &output);
        let a_companion = has_companion(&stage_a.path().join("program.exe"));
        let b_companion = has_companion(&stage_b.path().join("program.exe"));
        finish_build(stage_a, &output, BuildType::Debug, |artifact_a| {
            // Force another complete native publication before A copies its cache source.
            finish_build(stage_b, &output, BuildType::Debug, |artifact_b| {
                record(&b, &second, artifact_b)
            })?;
            record(&a, &first, artifact_a)
        })
        .unwrap();
        restore(&a, &output);
        assert_eq!(status(&output), if first_is_a { 7 } else { 11 });
        companion_names_match(&output, a_companion);
        restore(&b, &output);
        assert_eq!(status(&output), if first_is_a { 11 } else { 7 });
        companion_names_match(&output, b_companion);
        assert!(ms_json::parse(std::fs::read_to_string(metadata(&output)).unwrap()).is_ok());
        no_stages(&fixture.root);
    }
}

#[test]
fn record_failure_preserves_prior_public_artifacts_and_cleans_stage() {
    let fixture = Fixture::new("record-error");
    let first = fixture.source(true);
    let output = fixture.root.join("program");
    std::fs::write(&output, b"previous executable").unwrap();
    std::fs::write(metadata(&output), b"previous metadata").unwrap();
    let result = finish_build(prepare(&first, &output), &output, BuildType::Debug, |_| {
        Err("forced recording failure".into())
    });
    assert_eq!(result.unwrap_err(), "forced recording failure");
    assert!(std::fs::read(&output).unwrap() == b"previous executable");
    assert_eq!(
        std::fs::read(metadata(&output)).unwrap(),
        b"previous metadata"
    );
    no_stages(&fixture.root);
}

#[test]
fn cache_verification_rejects_before_replacing_public_artifacts() {
    let fixture = Fixture::new("verify-error");
    let first = fixture.source(true);
    let second = fixture.source(false);
    let output = fixture.root.join("program");
    let prior = prepare(&second, &output);
    let cache = fixture.cache("verify", ms_build::cache::Mode::On);
    record(&cache, &first, &prior.path().join("program.exe")).unwrap();
    finish_build(prior, &output, BuildType::Debug, |_| Ok(())).unwrap();
    let old_executable = std::fs::read(&output).unwrap();
    let old_metadata = std::fs::read(metadata(&output)).unwrap();
    let verify = fixture.cache("verify", ms_build::cache::Mode::Verify);
    let result = finish_build(
        prepare(&first, &output),
        &output,
        BuildType::Debug,
        |artifact| record(&verify, &first, artifact),
    );
    assert!(result.unwrap_err().contains("MS_CACHE=verify"));
    assert!(std::fs::read(&output).unwrap() == old_executable);
    assert_eq!(std::fs::read(metadata(&output)).unwrap(), old_metadata);
    assert_eq!(status(&output), 11);
    no_stages(&fixture.root);
}

#[test]
fn publication_failure_retains_valid_cache_for_retry() {
    let fixture = Fixture::new("publish-error");
    let source = fixture.source(true);
    let output = fixture.root.join("program");
    let stage = prepare(&source, &output);
    let companion = has_companion(&stage.path().join("program.exe"));
    // An output can become a directory after the command's initial destination check.
    std::fs::create_dir(&output).unwrap();
    std::fs::write(metadata(&output), b"previous metadata").unwrap();
    let cache = fixture.cache("a", ms_build::cache::Mode::On);
    let result = finish_build(stage, &output, BuildType::Debug, |artifact| {
        record(&cache, &source, artifact)
    });
    assert!(result.is_err());
    assert!(output.is_dir());
    assert_eq!(
        std::fs::read(metadata(&output)).unwrap(),
        b"previous metadata"
    );
    no_stages(&fixture.root);
    std::fs::remove_dir(&output).unwrap();
    restore(&cache, &output);
    assert_eq!(status(&output), 7);
    companion_names_match(&output, companion);
}

#[test]
fn metadata_failure_keeps_produced_executable_and_correct_cache() {
    let fixture = Fixture::new("metadata-error");
    let source = fixture.source(true);
    let output = fixture.root.join("program");
    let stage = prepare(&source, &output);
    let companion = has_companion(&stage.path().join("program.exe"));
    std::fs::create_dir(metadata(&output)).unwrap();
    let cache = fixture.cache("a", ms_build::cache::Mode::On);
    let result = finish_build(stage, &output, BuildType::Debug, |artifact| {
        record(&cache, &source, artifact)
    });
    assert!(result.unwrap_err().contains("cannot write build metadata"));
    assert_eq!(status(&output), 7);
    assert!(metadata(&output).is_dir());
    no_stages(&fixture.root);
    std::fs::remove_dir(metadata(&output)).unwrap();
    restore(&cache, &output);
    assert_eq!(status(&output), 7);
    companion_names_match(&output, companion);
}

#[test]
fn best_effort_cache_failure_does_not_fail_publication() {
    let fixture = Fixture::new("cache-error");
    let source = fixture.source(true);
    let output = fixture.root.join("program");
    let stage = prepare(&source, &output);
    std::fs::write(fixture.root.join("cache"), b"cache unavailable").unwrap();
    let cache = fixture.cache("a", ms_build::cache::Mode::On);
    finish_build(stage, &output, BuildType::Debug, |artifact| {
        record(&cache, &source, artifact)
    })
    .unwrap();
    assert_eq!(status(&output), 7);
    assert!(metadata(&output).is_file());
    assert!(cache.lookup().is_none());
    no_stages(&fixture.root);
}

#[test]
fn failed_recording_preserves_retained_companion_recovery_files() {
    let fixture = Fixture::new("retained-recovery");
    let source = fixture.source(true);
    let output = fixture.root.join("program");
    let stage = prepare(&source, &output);
    let private = stage.path().to_path_buf();
    let recovery = private.join("program.exe.previous.dSYM");
    std::fs::create_dir(&recovery).unwrap();
    std::fs::write(recovery.join("retained"), b"previous debug resource").unwrap();
    let result = finish_build(stage, &output, BuildType::Debug, |_| {
        Err("record failed".into())
    });
    assert_eq!(result.unwrap_err(), "record failed");
    assert!(!private.join("program.exe").exists());
    assert_eq!(
        std::fs::read(recovery.join("retained")).unwrap(),
        b"previous debug resource"
    );
    if let Some(companion) = ms_clif_companion(&private.join("program.exe")) {
        assert!(!companion.exists());
    }
    assert!(!output.exists());
    assert!(!metadata(&output).exists());
}
