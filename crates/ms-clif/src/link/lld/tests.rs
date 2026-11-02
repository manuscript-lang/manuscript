use super::*;
use std::io::Write as _;
use std::sync::mpsc;
use std::time::Duration;

fn scratch(name: &str) -> PathBuf {
    let root = std::env::temp_dir().join(format!("ms-link-cache-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    std::fs::create_dir_all(&root).unwrap();
    root
}

fn archive() -> Vec<u8> {
    let name = format!("bin/tool{}", if cfg!(windows) { ".exe" } else { "" });
    let contents = b"complete verified tool";
    let mut header = [0u8; 512];
    header[..name.len()].copy_from_slice(name.as_bytes());
    header[100..108].copy_from_slice(b"0000755\0");
    header[124..136].copy_from_slice(format!("{:011o}\0", contents.len()).as_bytes());
    header[148..156].fill(b' ');
    header[156] = b'0';
    let checksum: u32 = header.iter().map(|b| u32::from(*b)).sum();
    header[148..156].copy_from_slice(format!("{checksum:06o}\0 ").as_bytes());
    let mut tar = header.to_vec();
    tar.extend_from_slice(contents);
    tar.resize(1024 + 1024, 0);
    let mut encoder = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::fast());
    encoder.write_all(&tar).unwrap();
    encoder.finish().unwrap()
}

fn concurrent_fetch(first_fails: bool) {
    use sha2::{Digest, Sha256};
    let root = scratch(if first_fails {
        "fetch-failure"
    } else {
        "fetch-success"
    });
    let bytes = archive();
    let sha: String = Sha256::digest(&bytes)
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect();
    let (a_ready, a_waiting) = mpsc::channel();
    let (a_release, a_continue) = mpsc::channel();
    let (b_ready, b_waiting) = mpsc::channel();
    let (b_release, b_continue) = mpsc::channel();
    let a_root = root.clone();
    let a_sha = sha.clone();
    let a_bytes = bytes.clone();
    let first = std::thread::spawn(move || {
        fetch_at(&a_root, "fixture", &a_sha, &["tool"], || {
            a_ready.send(()).unwrap();
            a_continue.recv().unwrap();
            if first_fails {
                Err("fixture download failed".into())
            } else {
                Ok(a_bytes)
            }
        })
    });
    a_waiting.recv_timeout(Duration::from_secs(30)).unwrap();
    let b_root = root.clone();
    let b_sha = sha.clone();
    let second = std::thread::spawn(move || {
        fetch_at(&b_root, "fixture", &b_sha, &["tool"], || {
            b_ready.send(()).unwrap();
            b_continue.recv().unwrap();
            Ok(bytes)
        })
    });
    b_waiting.recv_timeout(Duration::from_secs(30)).unwrap();
    let stages = std::fs::read_dir(&root).unwrap().count();
    a_release.send(()).unwrap();
    let first = first.join().unwrap();
    b_release.send(()).unwrap();
    let second = second.join().unwrap();
    assert_eq!(
        stages, 2,
        "each downloader must retain its own staging directory"
    );
    assert_eq!(first.is_err(), first_fails, "{first:?}");
    let ready = second.unwrap().unwrap();
    assert_eq!(ready, root.join(&sha[..16]));
    let tool = ready.join(if cfg!(windows) { "tool.exe" } else { "tool" });
    assert_eq!(std::fs::read(tool).unwrap(), b"complete verified tool");
    assert!(ready.join(".ok").is_file());
    assert_eq!(std::fs::read_dir(&root).unwrap().count(), 1);
    assert_eq!(
        fetch_at(&root, "fixture", &sha, &["tool"], || panic!(
            "warm cache must not download"
        ))
        .unwrap(),
        Some(ready)
    );
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn concurrent_tool_downloads_keep_their_staging_files() {
    concurrent_fetch(false);
}

#[test]
fn failed_tool_download_does_not_remove_another_download() {
    concurrent_fetch(true);
}

#[test]
fn staging_does_not_reuse_or_remove_an_existing_directory() {
    let root = scratch("stale-stage");
    let first = staging(&root, "fixture").unwrap();
    let name = first.file_name().unwrap().to_str().unwrap();
    let (prefix, counter) = name.rsplit_once('-').unwrap();
    let stale = root.join(format!(
        "{prefix}-{}",
        counter.parse::<usize>().unwrap() + 1
    ));
    std::fs::create_dir(&stale).unwrap();
    std::fs::write(stale.join("retained"), b"owned elsewhere").unwrap();
    let next = staging(&root, "fixture").unwrap();
    assert_ne!(next, first);
    assert_ne!(next, stale);
    assert_eq!(
        std::fs::read(stale.join("retained")).unwrap(),
        b"owned elsewhere"
    );
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn bundled_extraction_preserves_existing_staging_links() {
    let root = scratch("bundled-links");
    let victim = root.join("victim");
    std::fs::write(&victim, b"retained contents").unwrap();
    let stale = root.join(format!(".support.txt-{}-0", std::process::id()));
    std::fs::hard_link(&victim, &stale).unwrap();
    let payload = b"tiny bundled support payload";
    extract_at(&root, &[("support.txt", payload)]).unwrap();
    assert_eq!(std::fs::read(&victim).unwrap(), b"retained contents");
    assert_eq!(std::fs::read(&stale).unwrap(), b"retained contents");
    assert_eq!(std::fs::read(root.join("support.txt")).unwrap(), payload);
    assert_eq!(std::fs::read_dir(&root).unwrap().count(), 3);
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn bundled_extraction_repairs_incomplete_files_and_reuses_complete_files() {
    let root = scratch("bundled-repair");
    let files: &[(&str, &[u8])] = &[("one", b"complete one"), ("two", b"complete two")];
    std::fs::write(root.join("one"), b"partial").unwrap();
    extract_at(&root, files).unwrap();
    for (name, payload) in files {
        assert_eq!(std::fs::read(root.join(name)).unwrap(), *payload);
    }
    let before = std::fs::metadata(root.join("one"))
        .unwrap()
        .modified()
        .unwrap();
    extract_at(&root, files).unwrap();
    assert_eq!(
        std::fs::metadata(root.join("one"))
            .unwrap()
            .modified()
            .unwrap(),
        before
    );
    assert_eq!(std::fs::read_dir(&root).unwrap().count(), 2);
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn failed_bundled_publication_cleans_only_its_own_stage() {
    let root = scratch("bundled-error");
    let blocked = root.join("support.txt");
    std::fs::create_dir(&blocked).unwrap();
    std::fs::write(blocked.join("retained"), b"owned elsewhere").unwrap();
    assert!(extract_at(&root, &[("support.txt", b"payload")]).is_err());
    assert_eq!(
        std::fs::read(blocked.join("retained")).unwrap(),
        b"owned elsewhere"
    );
    assert_eq!(std::fs::read_dir(&root).unwrap().count(), 1);
    std::fs::remove_dir_all(root).unwrap();
}
