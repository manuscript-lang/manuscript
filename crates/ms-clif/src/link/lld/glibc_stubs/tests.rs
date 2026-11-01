use super::*;
use std::sync::mpsc;
use std::time::Duration;

fn concurrent_stubs(first_fails: bool) {
    let root = std::env::temp_dir().join(format!(
        "ms-glibc-cache-{first_fails}-{}",
        std::process::id()
    ));
    let _ = std::fs::remove_dir_all(&root);
    std::fs::create_dir_all(&root).unwrap();
    let (a_ready, a_waiting) = mpsc::channel();
    let (a_release, a_continue) = mpsc::channel();
    let (b_ready, b_waiting) = mpsc::channel();
    let (b_release, b_continue) = mpsc::channel();
    let a_root = root.clone();
    let first = std::thread::spawn(move || {
        cache_stubs(&a_root, |stage| {
            std::fs::write(stage.join("libc.so.6"), b"partial").unwrap();
            a_ready.send(()).unwrap();
            a_continue.recv().unwrap();
            if first_fails {
                return Err(Error("fixture stub generation failed".into()));
            }
            std::fs::write(stage.join("libc.so.6"), b"complete").unwrap();
            Ok(())
        })
    });
    a_waiting.recv_timeout(Duration::from_secs(30)).unwrap();
    let b_root = root.clone();
    let second = std::thread::spawn(move || {
        cache_stubs(&b_root, |stage| {
            std::fs::write(stage.join("libc.so.6"), b"partial").unwrap();
            b_ready.send(()).unwrap();
            b_continue.recv().unwrap();
            std::fs::write(stage.join("libc.so.6"), b"complete").unwrap();
            Ok(())
        })
    });
    b_waiting.recv_timeout(Duration::from_secs(30)).unwrap();
    assert!(
        !root.join("glibc/.ok").exists(),
        "in-progress stubs must not be published"
    );
    let stages = std::fs::read_dir(&root).unwrap().count();
    a_release.send(()).unwrap();
    let first = first.join().unwrap();
    b_release.send(()).unwrap();
    let second = second.join().unwrap();
    assert_eq!(
        stages, 2,
        "each builder must retain its own staging directory"
    );
    assert_eq!(first.is_err(), first_fails, "{first:?}");
    let ready = second.unwrap();
    assert_eq!(ready, root.join("glibc"));
    assert!(ready.join(".ok").is_file());
    assert_eq!(std::fs::read(ready.join("libc.so.6")).unwrap(), b"complete");
    assert_eq!(std::fs::read_dir(&root).unwrap().count(), 1);
    assert_eq!(
        cache_stubs(&root, |_| panic!("warm cache must not generate")).unwrap(),
        ready
    );
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn concurrent_stub_generation_keeps_each_builders_files() {
    concurrent_stubs(false);
}

#[test]
fn failed_stub_generation_does_not_remove_another_builder() {
    concurrent_stubs(true);
}
