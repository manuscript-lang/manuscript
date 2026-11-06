//! Current publication/metadata/record ordering with real native producer pins.

use super::*;
use crate::backend::BuildType;
use std::path::PathBuf;
use std::process::Command;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Mutex, MutexGuard};

// Isolate fixture writes from unrelated fixture forks (see engine/testing.rs).
// The forced A/B interleaving itself remains inside one fixture.
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
        let root = std::env::temp_dir().join(format!(
            "ms-pinned-cache-{name}-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        std::fs::create_dir(&root).unwrap();
        Self {
            root,
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
    fn output(&self) -> PathBuf {
        self.root.join(format!(
            "renamed public program{}",
            std::env::consts::EXE_SUFFIX
        ))
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.root);
    }
}

fn compiled(backend: &Engine<ms_build::Native>, source: &Path) -> super::super::Compiled {
    compile(
        ms_syntax::Names::global(),
        backend,
        source.to_str().unwrap(),
        false,
    )
    .unwrap_or_else(|_| panic!("fixture must compile: {}", source.display()))
}
fn link(
    backend: &Engine<ms_build::Native>,
    compiled: &mut super::super::Compiled,
    output: &Path,
) -> (ArtifactPin, Result<ms_build::Backend, String>) {
    let pin = ArtifactPin::create(output).unwrap();
    let result = backend.link_pinned(compiled, output, BuildType::Debug, &[], Some(pin.path()));
    (pin, result)
}
fn record(
    cache: &BuildCache,
    compiled: &super::super::Compiled,
    pin: &ArtifactPin,
    backend: ms_build::Backend,
) -> Result<(), String> {
    cache.record(
        compiled,
        &build_inputs(compiled).unwrap(),
        pin.path(),
        backend,
    )
}
fn status(path: &Path) -> i32 {
    Command::new(path).status().unwrap().code().unwrap()
}
fn metadata(path: &Path) -> PathBuf {
    PathBuf::from(format!("{}.ms-build.json", path.display()))
}
fn restore(cache: &BuildCache, output: &Path) {
    cache
        .lookup()
        .expect("valid entry")
        .restore_to(output.to_str().unwrap())
        .unwrap();
}
fn companion_bytes(output: &Path) -> Option<Vec<u8>> {
    let companion = ms_clif_companion(output)?;
    if !companion.exists() {
        return None;
    }
    let resource = companion
        .join("Contents/Resources/DWARF")
        .join(output.file_name().unwrap());
    Some(std::fs::read(resource).unwrap())
}
fn no_stages(root: &Path) {
    assert!(std::fs::read_dir(root).unwrap().all(|entry| {
        !entry
            .unwrap()
            .file_name()
            .to_string_lossy()
            .starts_with(".ms-build-")
    }));
}

#[test]
fn concurrent_publication_records_each_producers_executable_and_companion() {
    for first_is_a in [true, false] {
        let fixture = Fixture::new("interleave");
        let a_source = fixture.source(first_is_a);
        let b_source = fixture.source(!first_is_a);
        let output = fixture.output();
        let backend = Engine::new(ms_build::Native);
        let mut a = compiled(&backend, &a_source);
        let mut b = compiled(&backend, &b_source);
        let cache_a = fixture.cache("a", ms_build::cache::Mode::On);
        let cache_b = fixture.cache("b", ms_build::cache::Mode::On);
        let (pin_a, result) = link(&backend, &mut a, &output);
        let backend_a = result.unwrap();
        let debug_a = companion_bytes(&output);
        assert_eq!(companion_bytes(pin_a.path()), debug_a);
        // B completes publication and recording before A records its source.
        let (pin_b, result) = link(&backend, &mut b, &output);
        let backend_b = result.unwrap();
        let debug_b = companion_bytes(&output);
        if let (Some(a), Some(b)) = (&debug_a, &debug_b) {
            assert_ne!(a, b, "producer debug resources must distinguish A from B");
        }
        record(&cache_b, &b, &pin_b, backend_b).unwrap();
        record(&cache_a, &a, &pin_a, backend_a).unwrap();
        drop((pin_a, pin_b));
        restore(&cache_a, &output);
        assert_eq!(status(&output), if first_is_a { 7 } else { 11 });
        assert_eq!(companion_bytes(&output), debug_a);
        restore(&cache_b, &output);
        assert_eq!(status(&output), if first_is_a { 11 } else { 7 });
        assert_eq!(companion_bytes(&output), debug_b);
        no_stages(&fixture.root);
    }
}

#[test]
fn verification_mismatch_keeps_current_postpublication_policy() {
    let fixture = Fixture::new("verify");
    let output = fixture.output();
    let backend = Engine::new(ms_build::Native);
    let mut previous = compiled(&backend, &fixture.source(false));
    let cache = fixture.cache("same", ms_build::cache::Mode::On);
    let (pin, result) = link(&backend, &mut previous, &output);
    let selected = result.unwrap();
    record(&cache, &previous, &pin, selected).unwrap();
    drop(pin);
    let mut rebuilt = compiled(&backend, &fixture.source(true));
    let (pin, result) = link(&backend, &mut rebuilt, &output);
    let selected = result.unwrap();
    let verify = fixture.cache("same", ms_build::cache::Mode::Verify);
    assert!(
        record(&verify, &rebuilt, &pin, selected)
            .unwrap_err()
            .contains("MS_CACHE=verify")
    );
    assert_eq!(status(&output), 7);
    assert!(ms_json::parse(std::fs::read_to_string(metadata(&output)).unwrap()).is_ok());
    drop(pin);
    restore(&cache, &output);
    assert_eq!(status(&output), 11);
    no_stages(&fixture.root);
}

#[test]
fn publication_failure_does_not_record_and_cleans_owned_pin() {
    let fixture = Fixture::new("publish-error");
    let output = fixture.output();
    let backend = Engine::new(ms_build::Native);
    let mut build = compiled(&backend, &fixture.source(true));
    std::fs::create_dir(&output).unwrap();
    std::fs::write(metadata(&output), b"previous metadata").unwrap();
    let cache = fixture.cache("a", ms_build::cache::Mode::On);
    let (pin, linked) = link(&backend, &mut build, &output);
    let result = linked.and_then(|selected| record(&cache, &build, &pin, selected));
    assert!(result.is_err());
    drop(pin);
    assert!(output.is_dir());
    assert_eq!(
        std::fs::read(metadata(&output)).unwrap(),
        b"previous metadata"
    );
    assert!(cache.lookup().is_none());
    no_stages(&fixture.root);
}

#[test]
fn metadata_failure_keeps_published_executable_without_recording() {
    let fixture = Fixture::new("metadata-error");
    let output = fixture.output();
    let backend = Engine::new(ms_build::Native);
    let mut build = compiled(&backend, &fixture.source(true));
    std::fs::create_dir(metadata(&output)).unwrap();
    let cache = fixture.cache("a", ms_build::cache::Mode::On);
    let (pin, linked) = link(&backend, &mut build, &output);
    let result = linked.and_then(|selected| record(&cache, &build, &pin, selected));
    assert!(result.unwrap_err().contains("cannot write build metadata"));
    drop(pin);
    assert_eq!(status(&output), 7);
    assert!(metadata(&output).is_dir());
    assert!(cache.lookup().is_none());
    no_stages(&fixture.root);
}

#[test]
fn best_effort_cache_failure_does_not_fail_publication() {
    let fixture = Fixture::new("cache-error");
    let output = fixture.output();
    let backend = Engine::new(ms_build::Native);
    let mut build = compiled(&backend, &fixture.source(true));
    std::fs::write(fixture.root.join("cache"), b"unavailable cache directory").unwrap();
    let cache = fixture.cache("a", ms_build::cache::Mode::On);
    let (pin, linked) = link(&backend, &mut build, &output);
    linked
        .and_then(|selected| record(&cache, &build, &pin, selected))
        .unwrap();
    drop(pin);
    assert_eq!(status(&output), 7);
    assert!(metadata(&output).is_file());
    assert!(cache.lookup().is_none());
    no_stages(&fixture.root);
}

#[test]
fn dropping_pin_preserves_unrelated_recovery_files() {
    let fixture = Fixture::new("recovery");
    let pin = ArtifactPin::create(&fixture.output()).unwrap();
    let stage = pin.path().parent().unwrap().to_path_buf();
    let recovery = stage.join("program.exe.previous.dSYM");
    std::fs::create_dir(&recovery).unwrap();
    std::fs::write(recovery.join("retained"), b"old debug").unwrap();
    std::fs::write(pin.path(), b"candidate").unwrap();
    if let Some(companion) = ms_clif_companion(pin.path()) {
        std::fs::create_dir(companion).unwrap();
    }
    drop(pin);
    assert!(!stage.join("program.exe").exists());
    assert_eq!(
        std::fs::read(recovery.join("retained")).unwrap(),
        b"old debug"
    );
    if let Some(companion) = ms_clif_companion(&stage.join("program.exe")) {
        assert!(!companion.exists());
    }
}
