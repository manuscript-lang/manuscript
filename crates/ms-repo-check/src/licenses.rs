//! The dependency license inventory: every locked registry or git crate with its declared
//! SPDX license, plus SHA-256 hashes of bundled notice files. Not a legal assessment.

use ms_json::{Escape, Json, obj};
use std::path::Path;
use std::process::Command;

const INVENTORY: &str = "documentation/contributing/dependency-licenses.json";
const NOTICE_ROOTS: [&str; 2] = ["website/themes/hugo-book", "skills"];

/// Writes the inventory, or with `check` fails when the checked-in file differs.
pub fn run(check: bool) -> Result<(), String> {
    let mut crates = cargo_crates()?;
    crates.sort();
    let mut notices = Vec::new();
    for root in NOTICE_ROOTS {
        collect_notices(Path::new(root), &mut notices)?;
    }
    notices.sort();
    let document = obj([
        (
            "crates",
            Json::Arr(
                crates
                    .into_iter()
                    .map(|(name, version, license)| {
                        obj([
                            ("name", Json::str(name)),
                            ("version", Json::str(version)),
                            ("license", Json::str(license)),
                        ])
                    })
                    .collect(),
            ),
        ),
        (
            "notices",
            Json::Arr(
                notices
                    .into_iter()
                    .map(|(path, sha256)| {
                        obj([("path", Json::str(path)), ("sha256", Json::str(sha256))])
                    })
                    .collect(),
            ),
        ),
    ]);
    let text = document.pretty_line(Escape::HtmlSafe);
    if check {
        let actual = std::fs::read_to_string(INVENTORY).map_err(|e| format!("{INVENTORY}: {e}"))?;
        if actual != text {
            return Err("dependency notices changed; run make licenses".into());
        }
        return Ok(());
    }
    std::fs::write(INVENTORY, text).map_err(|e| format!("{INVENTORY}: {e}"))
}

/// (name, version, license) of every crate in the locked graph that comes from a registry or git.
fn cargo_crates() -> Result<Vec<(String, String, String)>, String> {
    let output = Command::new("cargo")
        .args(["metadata", "--locked", "--format-version", "1"])
        .output()
        .map_err(|e| format!("cargo metadata: {e}"))?;
    if !output.status.success() {
        return Err(format!(
            "cargo metadata: {}",
            String::from_utf8_lossy(&output.stderr)
        ));
    }
    let metadata = ms_json::parse(&output.stdout)?;
    let packages = metadata
        .get("packages")
        .and_then(Json::as_array)
        .ok_or("cargo metadata: no packages")?;
    let mut crates = Vec::new();
    for package in packages {
        // Registry crates and the vendored copies under `vendor/`; workspace members are ours.
        let vendored = package
            .get("manifest_path")
            .and_then(Json::as_str)
            .is_some_and(|path| path.contains("/vendor/"));
        if package.get("source").is_none_or(Json::is_null) && !vendored {
            continue;
        }
        let field = |key: &str| {
            package
                .get(key)
                .and_then(Json::as_str)
                .unwrap_or_default()
                .to_string()
        };
        let license = match field("license") {
            license if license.is_empty() => "UNKNOWN".to_string(),
            license => license,
        };
        crates.push((field("name"), field("version"), license));
    }
    Ok(crates)
}

fn collect_notices(dir: &Path, notices: &mut Vec<(String, String)>) -> Result<(), String> {
    let entries = std::fs::read_dir(dir).map_err(|e| format!("{}: {e}", dir.display()))?;
    for entry in entries {
        let path = entry.map_err(|e| e.to_string())?.path();
        if path.is_dir() {
            collect_notices(&path, notices)?;
            continue;
        }
        let name = path
            .file_name()
            .unwrap_or_default()
            .to_string_lossy()
            .to_uppercase();
        if !["LICENSE", "COPYING", "PATENTS"]
            .iter()
            .any(|prefix| name.starts_with(prefix))
        {
            continue;
        }
        let data = std::fs::read(&path).map_err(|e| format!("{}: {e}", path.display()))?;
        notices.push((
            path.to_string_lossy().replace('\\', "/"),
            ms_tooling::sha256::hex(&data),
        ));
    }
    Ok(())
}
