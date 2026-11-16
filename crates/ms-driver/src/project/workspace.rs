//! Workspaces: a root `ms.toml` with `[workspace] members` names directories that each hold a
//! project. Members import one another through `{ path = "../util" }` dependencies and share
//! the root's `ms.lock`.

use std::collections::BTreeMap;

use crate::project::error::ProjectError;
use crate::project::manifest::Project;
use crate::project::pathops;

/// One project of a workspace.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Member {
    /// `[project] name`, unique in the workspace.
    pub name: String,
    /// The canonical directory holding the member's `ms.toml`.
    pub root: String,
}

/// A workspace root and the members it lists, the root's own project first when it has one.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Workspace {
    /// The canonical directory holding the root `ms.toml` and `ms.lock`.
    pub root: String,
    pub members: Vec<Member>,
}

impl Workspace {
    /// The member whose directory is `dir`.
    pub fn member_at(&self, dir: &str) -> Option<&Member> {
        self.members.iter().find(|m| m.root == dir)
    }

    /// The path of the member's manifest.
    pub fn manifest(member: &Member) -> String {
        pathops::join(&[&member.root, "ms.toml"])
    }
}

/// The workspace that contains the project whose `ms.toml` is `manifest`: the manifest itself
/// when it has `[workspace]`, else the nearest ancestor manifest that lists this directory.
/// `Ok(None)` for a project outside any workspace; a nearer, unrelated project does not make an
/// ancestor workspace its own.
pub fn find(manifest: &str) -> Result<Option<Workspace>, ProjectError> {
    let manifest = pathops::abs(manifest)?;
    let here = pathops::eval_symlinks(&pathops::dir(&manifest))?;
    let mut dir = here.clone();
    loop {
        let candidate = pathops::join(&[&dir, "ms.toml"]);
        if std::fs::metadata(&candidate).is_ok_and(|m| m.is_file()) {
            let mut root = Project::default();
            // A broken or unrelated ancestor manifest is not a workspace; its own errors
            // surface when it is the project being built.
            let is_workspace = crate::project::manifest::read_manifest(&candidate, &mut root)
                .is_ok()
                && root.members.is_some();
            if is_workspace {
                let workspace = read(&root)?;
                if dir == here || workspace.member_at(&here).is_some() {
                    return Ok(Some(workspace));
                }
                return Ok(None);
            }
        }
        let parent = pathops::dir(&dir);
        if parent == dir {
            return Ok(None);
        }
        dir = parent;
    }
}

/// Expands and checks the members of a parsed workspace root.
pub fn read(root_project: &Project) -> Result<Workspace, ProjectError> {
    let root = root_project.root.clone();
    let patterns = root_project.members.clone().unwrap_or_default();
    let mut dirs: Vec<String> = Vec::new();
    // The root's own project, when it has one, is a member.
    if !root_project.name.is_empty() {
        dirs.push(root.clone());
    }
    for pattern in &patterns {
        let (base, wildcard) = match pattern.strip_suffix("/*") {
            Some(base) => (base, true),
            None => (pattern.as_str(), false),
        };
        let bad = |why: &str| {
            ProjectError::msg(format!(
                "workspace member {pattern:?} {why}; write a directory below the workspace root such as \"app\" or \"libs/*\""
            ))
        };
        if base.is_empty() || pathops::is_abs(base) || pathops::escapes(base) || base.contains('*')
        {
            return Err(bad("is not a relative directory inside the workspace"));
        }
        let parent = pathops::eval_symlinks(&pathops::join(&[&root, base]))
            .map_err(|_| bad("does not exist"))?;
        if !within(&root, &parent) {
            return Err(bad("leaves the workspace root"));
        }
        if !wildcard {
            dirs.push(parent);
            continue;
        }
        let mut children = Vec::new();
        let entries = std::fs::read_dir(&parent)
            .map_err(|e| ProjectError::path("read directory", &parent, &e))?;
        for entry in entries {
            let entry = entry.map_err(|e| ProjectError::path("read directory", &parent, &e))?;
            let path = entry.path();
            // A hidden directory (.git, .cache) is never a member.
            if entry.file_name().to_string_lossy().starts_with('.') {
                continue;
            }
            if path.join("ms.toml").is_file() {
                let canonical = pathops::eval_symlinks(&path.to_string_lossy())?;
                if within(&root, &canonical) {
                    children.push(canonical);
                }
            }
        }
        children.sort();
        dirs.extend(children);
    }
    if dirs.is_empty() {
        return Err(ProjectError::msg(
            "workspace lists no members; name each member directory under [workspace], such as members = [\"app\", \"libs/*\"]",
        ));
    }
    let mut members: Vec<Member> = Vec::new();
    let mut seen: BTreeMap<String, String> = BTreeMap::new();
    for dir in dirs {
        if members.iter().any(|m| m.root == dir) {
            continue;
        }
        let manifest = pathops::join(&[&dir, "ms.toml"]);
        let mut project = Project::default();
        crate::project::manifest::read_manifest(&manifest, &mut project).map_err(|e| {
            ProjectError::msg(format!("workspace member {}: {e}", rel_or(&root, &dir)))
        })?;
        if dir != root && std::path::Path::new(&dir).join("ms.lock").is_file() {
            return Err(ProjectError::msg(format!(
                "workspace member {} has its own ms.lock, which is never read; the workspace keeps one ms.lock at {}, so delete the member's",
                rel_or(&root, &dir),
                root
            )));
        }
        if project.name.is_empty() {
            return Err(ProjectError::msg(format!(
                "workspace member {} has no [project]; a member is a project with a name and source",
                rel_or(&root, &dir)
            )));
        }
        if let Some(first) = seen.insert(project.name.clone(), dir.clone()) {
            return Err(ProjectError::msg(format!(
                "workspace members {} and {} are both named {:?}; rename one in [project]",
                rel_or(&root, &first),
                rel_or(&root, &dir),
                project.name
            )));
        }
        members.push(Member {
            name: project.name,
            root: dir,
        });
    }
    Ok(Workspace { root, members })
}

fn within(root: &str, dir: &str) -> bool {
    std::path::Path::new(dir).starts_with(root)
}

fn rel_or(root: &str, dir: &str) -> String {
    pathops::rel(root, dir)
        .ok()
        .filter(|r| r != ".")
        .unwrap_or_else(|| dir.to_string())
}

/// The members of `manifest` when it is a workspace root with no `[project]` of its own, so a
/// command aimed at it means "every member". `Ok(None)` for any other manifest or file.
pub fn root_members(manifest: &str) -> Result<Option<Workspace>, ProjectError> {
    if pathops::base(manifest) != "ms.toml" || !std::path::Path::new(manifest).is_file() {
        return Ok(None);
    }
    let mut root = Project::default();
    // A manifest that does not parse is reported by the command itself, in its own format.
    if crate::project::manifest::read_manifest(manifest, &mut root).is_err() {
        return Ok(None);
    }
    if root.members.is_none() || !root.name.is_empty() {
        return Ok(None);
    }
    read(&root).map(Some)
}
