//! The bundled skill is installed outside the compiler checkout without overwrite.

use std::path::Path;
use std::process::Command;

fn ms(dir: &Path, args: &[&str]) -> std::process::Output {
    Command::new(env!("CARGO_BIN_EXE_ms"))
        .current_dir(dir)
        .args(args)
        .output()
        .unwrap()
}

fn directory(name: &str) -> std::path::PathBuf {
    let path = std::env::temp_dir().join(format!("ms-cli-skill-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&path);
    std::fs::create_dir_all(&path).unwrap();
    path
}

#[test]
fn skill_installs_complete_versioned_bundle_in_requested_parent() {
    let dir = directory("bundle");
    let out = ms(&dir, &["skill", "-o", "agents with spaces/skills"]);
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    let destination = dir.join("agents with spaces/skills/manuscript");
    for (name, text) in ms_tooling::guide::skill::FILES {
        assert_eq!(
            std::fs::read_to_string(destination.join(name)).unwrap(),
            text.replace("{{MS_VERSION}}", ms_cli::VERSION),
            "{name}"
        );
    }
    let root = std::fs::read_to_string(destination.join("SKILL.md")).unwrap();
    assert!(root.starts_with("---\nname: manuscript\ndescription:"));
    for tail in root.split("](references/").skip(1) {
        let path = tail.split(')').next().unwrap();
        assert!(
            destination.join("references").join(path).is_file(),
            "{path}"
        );
    }
    assert!(root.contains(ms_cli::VERSION));
    assert!(!root.contains("{{MS_VERSION}}"));
    let version = ms(&dir, &["--version"]);
    assert_eq!(
        String::from_utf8_lossy(&version.stdout).trim(),
        format!("Manuscript {}", ms_cli::VERSION)
    );
    assert!(!dir.join(".agents").exists());
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn skill_output_directory_never_overwrites_local_edits() {
    let dir = directory("default");
    assert!(
        ms(&dir, &["skill", "-o", ".agents/skills"])
            .status
            .success()
    );
    let root = dir.join(".agents/skills/manuscript/SKILL.md");
    std::fs::write(&root, "local edits").unwrap();
    let reference = dir.join(".agents/skills/manuscript/references/validation.md");
    std::fs::write(&reference, "local reference").unwrap();
    let out = ms(&dir, &["skill", "-o", ".agents/skills"]);
    assert_eq!(out.status.code(), Some(1));
    assert!(String::from_utf8_lossy(&out.stderr).contains("never overwritten"));
    assert_eq!(std::fs::read_to_string(root).unwrap(), "local edits");
    assert_eq!(
        std::fs::read_to_string(reference).unwrap(),
        "local reference"
    );
    assert!(ms(&dir, &["skill", "--output", "second"]).status.success());
    assert!(dir.join("second/manuscript/SKILL.md").is_file());
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn skill_help_and_bad_options_do_not_install() {
    let dir = directory("options");
    for args in [
        vec!["skill", "-o"],
        vec!["skill", "-o", ""],
        vec!["skill", "-o", "--bad"],
        vec!["skill", "--unknown"],
        vec!["skill", "directory"],
        vec!["skill", "-o", "one", "--output", "two"],
    ] {
        assert_eq!(ms(&dir, &args).status.code(), Some(2), "{args:?}");
    }
    let out = ms(&dir, &["skill", "--help"]);
    assert!(out.status.success());
    assert!(String::from_utf8_lossy(&out.stdout).contains("<directory>/manuscript/"));
    assert_eq!(std::fs::read_dir(&dir).unwrap().count(), 0);
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn skill_reports_file_as_destination_without_changing_it() {
    let dir = directory("occupied");
    std::fs::write(dir.join("manuscript"), "existing file").unwrap();
    let out = ms(&dir, &["skill", "--output", "."]);
    assert_eq!(out.status.code(), Some(1));
    assert_eq!(
        std::fs::read_to_string(dir.join("manuscript")).unwrap(),
        "existing file"
    );
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn skill_stdout_is_complete_versioned_and_can_be_redirected_without_installing() {
    let dir = directory("stdout");
    let out = ms(&dir, &["skill"]);
    assert!(out.status.success());
    assert!(out.stderr.is_empty());
    let document = String::from_utf8(out.stdout).unwrap();
    assert_eq!(
        document,
        ms_tooling::guide::skill::document(ms_cli::VERSION)
    );
    assert!(document.starts_with("---\nname: manuscript\n"));
    assert!(document.contains(&format!("Generated for Manuscript {}", ms_cli::VERSION)));
    assert!(!document.contains("{{MS_VERSION}}"));
    assert!(!document.contains("](references/"));
    assert_eq!(document.matches("<!-- complete").count(), 9);
    for (path, _) in &ms_tooling::guide::skill::FILES[1..] {
        let slug = path
            .trim_start_matches("references/")
            .trim_end_matches(".md");
        assert!(document.contains(&format!("(#{slug})")));
        let title = slug.replace('-', " ");
        assert!(
            document
                .to_ascii_lowercase()
                .contains(&format!("\n## {title}\n"))
        );
    }
    assert_eq!(std::fs::read_dir(&dir).unwrap().count(), 0);
    let file = std::fs::File::create(dir.join("skill.md")).unwrap();
    let status = Command::new(env!("CARGO_BIN_EXE_ms"))
        .current_dir(&dir)
        .arg("skill")
        .stdout(file)
        .status()
        .unwrap();
    assert!(status.success());
    assert_eq!(
        std::fs::read_to_string(dir.join("skill.md")).unwrap(),
        document
    );
    assert_eq!(std::fs::read_dir(&dir).unwrap().count(), 1);
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn guide_command_is_removed_and_explain_retains_diagnostic_lookup() {
    let dir = directory("explain");
    assert_eq!(ms(&dir, &["guide"]).status.code(), Some(2));
    assert_eq!(ms(&dir, &["help", "guide"]).status.code(), Some(2));
    assert!(!ms_cli::help::COMMAND_NAMES.contains(&"guide"));
    let out = ms(&dir, &["explain", "MS3060", "MSL110", "--json"]);
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    let json = String::from_utf8(out.stdout).unwrap();
    assert!(json.contains("\"format\": 1"));
    assert!(json.contains("MS3060"));
    assert!(json.contains("MSL110"));
    assert!(json.contains("\"repair\""));
    assert!(json.contains("\"severity\""));
    assert_eq!(ms(&dir, &["explain"]).status.code(), Some(2));
    assert_eq!(ms(&dir, &["explain", "--json"]).status.code(), Some(2));
    assert_eq!(ms(&dir, &["explain", "MS9999"]).status.code(), Some(1));
    let _ = std::fs::remove_dir_all(dir);
}
