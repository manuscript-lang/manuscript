//! Dependency resolution the way Cargo does it: one copy of a repository per compatible range.
//!
//! The resolver reads requirements from the project and from every package it has picked, picks
//! the highest tag that satisfies all requirements in a bucket (see [`Bucket`]), and repeats
//! until the picks stop changing, because a package that is picked no longer asks for what the
//! package it replaced asked for. All network and disk work goes through [`Remote`], so the
//! procedure is checked against a table of tags in the tests.

use std::collections::{BTreeMap, BTreeSet};

use crate::project::manifest::{Dependency, Project, Source};
use crate::project::packages::{LockEntry, is_hex};
use crate::project::semver::{Bucket, Version};

/// The most rounds before the resolver gives up on a graph whose picks keep changing.
const MAX_ROUNDS: usize = 64;

/// A downloaded package: the lock entry that pins it and its manifest.
pub struct Fetched {
    pub entry: LockEntry,
    pub manifest: Project,
}

/// What the resolver needs from the network and the cache.
pub trait Remote {
    /// The tag names of the repository at `url`.
    fn tags(&mut self, url: &str) -> Result<Vec<String>, String>;
    /// Download `url` at `reference` (a tag or a 40-digit commit) and read its manifest. With
    /// `locked`, fetch exactly that revision and check its hash. `nested` limits the transport
    /// to `https`.
    fn fetch(
        &mut self,
        url: &str,
        reference: &str,
        locked: Option<&LockEntry>,
        nested: bool,
    ) -> Result<Fetched, String>;
}

/// One picked copy of a repository.
pub struct Copy {
    pub id: String,
    pub url: String,
    /// The tag or commit it was fetched at.
    pub reference: String,
    pub entry: LockEntry,
    pub manifest: Project,
}

/// The result: the copies, their lock entries, and which copy each top-level name reaches.
pub struct Resolved {
    pub copies: BTreeMap<String, Copy>,
    pub roots: BTreeMap<String, String>,
}

impl Resolved {
    pub fn lock(&self) -> BTreeMap<String, LockEntry> {
        self.copies
            .iter()
            .map(|(id, copy)| (id.clone(), copy.entry.clone()))
            .collect()
    }
}

/// `github.com/acme/wire` for any spelling of the repository URL: the scheme is dropped, the host
/// is lowercase, and a trailing `/` and `.git` are removed. A `file://` URL keeps its path as
/// `file/path`.
pub fn repo_key(url: &str) -> String {
    let (local, rest) = match url.split_once("://") {
        Some(("file", rest)) => (true, rest),
        Some((_, rest)) => (false, rest),
        None => (false, url),
    };
    let rest = rest.trim_end_matches('/');
    let rest = rest.strip_suffix(".git").unwrap_or(rest);
    if local {
        return format!("file/{}", rest.trim_start_matches('/'));
    }
    match rest.split_once('/') {
        Some((host, path)) => format!("{}/{path}", host.to_ascii_lowercase()),
        None => rest.to_ascii_lowercase(),
    }
}

/// The id of the copy of `url` fetched at `reference`, the tag exactly as the repository spells it
/// or the commit: `github.com/acme/wire@v1.4.2`.
pub fn copy_id(url: &str, reference: &str) -> String {
    format!("{}@{reference}", repo_key(url))
}

/// The id a lock entry's `url#reference` spec names.
pub fn id_of_spec(spec: &str) -> Option<String> {
    let (url, reference) = spec.split_once('#')?;
    Some(copy_id(url, reference))
}

/// The version a lock entry's tag names, if it is a version tag.
pub fn entry_version(entry: &LockEntry) -> Option<Version> {
    let (_, reference) = entry.spec.split_once('#')?;
    Version::of_tag(reference)
}

/// A tagged release whose manifest names another version is a mistake in the repository that
/// blocks every user of it, so the error says how to get past it.
pub fn check_version_agrees(
    what: &str,
    url: &str,
    reference: &str,
    manifest: &Project,
) -> Result<(), String> {
    let (Some(tagged), Some(declared)) = (Version::of_tag(reference), &manifest.version) else {
        return Ok(());
    };
    if tagged == *declared {
        return Ok(());
    }
    Err(format!(
        "{what} tag {reference} of {url} holds ms.toml version {declared}, not {tagged}; ask the author to fix the tag, or require an earlier version such as ={}",
        earlier(&tagged)
    ))
}

/// A requirement that names the release before `v`, as a hint in an error.
fn earlier(v: &Version) -> String {
    if v.patch > 0 {
        format!("{}.{}.{}", v.major, v.minor, v.patch - 1)
    } else if v.minor > 0 {
        format!("{}.{}", v.major, v.minor - 1)
    } else {
        format!("{}", v.major.saturating_sub(1))
    }
}

/// A requirement some manifest makes of a repository.
#[derive(Clone)]
struct Ask {
    /// Who asks: `the project` or a copy's id.
    asker: String,
    alias: String,
    dep: Dependency,
    repo: String,
    nested: bool,
}

/// A copy to build: the repository and bucket (or pin) it stands for.
#[derive(Clone, PartialEq, Eq, PartialOrd, Ord)]
struct Group(String, Option<Bucket>);

#[derive(Clone, PartialEq, Eq)]
struct Choice {
    url: String,
    reference: String,
}

/// Resolve the dependencies of `roots` (each a manifest and the name diagnostics call it).
/// `old` is the existing lock, whose picks are kept while they still satisfy every requirement;
/// `update` holds names whose repositories are re-picked.
pub fn resolve(
    roots: &[(&str, &Project)],
    old: &BTreeMap<String, LockEntry>,
    update: &BTreeSet<String>,
    remote: &mut dyn Remote,
) -> Result<Resolved, String> {
    let mut downloads: BTreeMap<(String, String), Fetched> = BTreeMap::new();
    let mut tags: BTreeMap<String, Vec<(Version, String)>> = BTreeMap::new();
    let mut chosen: BTreeMap<Group, Choice> = BTreeMap::new();
    let mut matched = BTreeSet::new();
    for _ in 0..MAX_ROUNDS {
        let asks = collect(roots, &chosen, &downloads)?;
        for ask in &asks {
            if update.contains(&ask.alias) {
                matched.insert(ask.alias.clone());
            }
        }
        let next = choose(&asks, old, update, remote, &mut tags, &mut downloads)?;
        if next == chosen {
            for name in update {
                if !matched.contains(name) {
                    return Err(format!("--update {name}: no such dependency"));
                }
            }
            return finish(&asks, next, downloads, roots);
        }
        chosen = next;
    }
    let moving = chosen
        .keys()
        .map(|g| g.0.as_str())
        .next()
        .unwrap_or("a repository");
    Err(format!(
        "dependencies do not settle after {MAX_ROUNDS} rounds; the picks for {moving} keep changing, so pin one version with tag or sha"
    ))
}

/// Every requirement of the roots and of the copies picked so far.
fn collect(
    roots: &[(&str, &Project)],
    chosen: &BTreeMap<Group, Choice>,
    downloads: &BTreeMap<(String, String), Fetched>,
) -> Result<Vec<Ask>, String> {
    let mut asks = Vec::new();
    let add = |asker: &str, manifest: &Project, nested: bool, asks: &mut Vec<Ask>| {
        for (alias, dep) in &manifest.dependencies {
            asks.push(Ask {
                asker: asker.to_string(),
                alias: alias.clone(),
                dep: dep.clone(),
                repo: repo_key(&dep.url),
                nested,
            });
        }
    };
    for (name, manifest) in roots {
        add(name, manifest, false, &mut asks);
    }
    // A copy is a node once, however many ask for it; its own requirements count while it is picked.
    let mut seen = BTreeSet::new();
    let mut frontier: Vec<Choice> = chosen.values().cloned().collect();
    while let Some(choice) = frontier.pop() {
        let key = (choice.url.clone(), choice.reference.clone());
        if !seen.insert(key.clone()) {
            continue;
        }
        if let Some(fetched) = downloads.get(&key) {
            add(
                &copy_id(&choice.url, &choice.reference),
                &fetched.manifest,
                true,
                &mut asks,
            );
        }
    }
    asks.sort_by(|a, b| (&a.asker, &a.alias).cmp(&(&b.asker, &b.alias)));
    Ok(asks)
}

#[allow(clippy::too_many_arguments)]
fn choose(
    asks: &[Ask],
    old: &BTreeMap<String, LockEntry>,
    update: &BTreeSet<String>,
    remote: &mut dyn Remote,
    tags: &mut BTreeMap<String, Vec<(Version, String)>>,
    downloads: &mut BTreeMap<(String, String), Fetched>,
) -> Result<BTreeMap<Group, Choice>, String> {
    let mut by_repo: BTreeMap<&str, Vec<&Ask>> = BTreeMap::new();
    for ask in asks {
        by_repo.entry(&ask.repo).or_default().push(ask);
    }
    let mut next = BTreeMap::new();
    for (repo, list) in by_repo {
        for ask in &list {
            if ask.nested && !ask.dep.url.starts_with("https://") {
                return Err(format!(
                    "{} depends on {} = {}; a package's own dependencies must use https:// URLs, because file:// reads the machine running ms install",
                    ask.asker, ask.alias, ask.dep.url
                ));
            }
        }
        let pins: Vec<&&Ask> = list
            .iter()
            .filter(|a| !matches!(a.dep.source, Source::Version(_)))
            .collect();
        let wants: Vec<&&Ask> = list
            .iter()
            .filter(|a| matches!(a.dep.source, Source::Version(_)))
            .collect();
        if !pins.is_empty() && !wants.is_empty() {
            return Err(format!(
                "{repo} is needed at {} by {} and at {} by {}; use one kind of dependency for a repository, either pinned with tag or sha or by version",
                pins[0].dep.describe(),
                pins[0].asker,
                wants[0].dep.describe(),
                wants[0].asker
            ));
        }
        if !pins.is_empty() {
            let pinned = pick_pin(repo, &pins, old, update, remote, downloads)?;
            next.insert(Group(repo.to_string(), None), pinned);
            continue;
        }
        let mut buckets: BTreeMap<Bucket, Vec<&Ask>> = BTreeMap::new();
        for ask in &wants {
            if let Source::Version(req) = &ask.dep.source {
                buckets.entry(req.bucket()).or_default().push(ask);
            }
        }
        let url = &wants[0].dep.url;
        for (bucket, members) in buckets {
            let group = Group(repo.to_string(), Some(bucket));
            let keep = |tag: &str| {
                members
                    .iter()
                    .all(|a| satisfies(&a.dep.source, Version::of_tag(tag).as_ref()))
            };
            let updating = members.iter().any(|a| update.contains(&a.alias));
            let locked = old
                .values()
                .filter(|e| {
                    id_of_spec(&e.spec).is_some_and(|id| id.starts_with(&format!("{repo}@")))
                })
                .find_map(|e| {
                    let (_, tag) = e.spec.split_once('#')?;
                    let version = Version::of_tag(tag)?;
                    (version.bucket() == bucket && keep(tag)).then(|| tag.to_string())
                });
            let reference = if let Some(tag) = locked.filter(|_| !updating) {
                tag
            } else {
                let listed = tags_of(remote, tags, url)?;
                best(repo, bucket, &members, listed)?
            };
            next.insert(
                group,
                Choice {
                    url: url.clone(),
                    reference,
                },
            );
        }
    }
    // Make sure every choice is downloaded and its manifest agrees with its tag.
    for choice in next.values() {
        let key = (choice.url.clone(), choice.reference.clone());
        if downloads.contains_key(&key) {
            continue;
        }
        let nested = asks
            .iter()
            .any(|a| a.nested && repo_key(&a.dep.url) == repo_key(&choice.url));
        let locked = old
            .values()
            .find(|e| e.spec == format!("{}#{}", choice.url, choice.reference));
        let fetched = remote.fetch(&choice.url, &choice.reference, locked, nested)?;
        check_version_agrees("package", &choice.url, &choice.reference, &fetched.manifest)?;
        downloads.insert(key, fetched);
    }
    Ok(next)
}

fn satisfies(source: &Source, version: Option<&Version>) -> bool {
    match (source, version) {
        (Source::Version(req), Some(v)) => req.matches(v),
        _ => false,
    }
}

fn tags_of<'a>(
    remote: &mut dyn Remote,
    cache: &'a mut BTreeMap<String, Vec<(Version, String)>>,
    url: &str,
) -> Result<&'a [(Version, String)], String> {
    let key = repo_key(url);
    if !cache.contains_key(&key) {
        let mut found: Vec<(Version, String)> = Vec::new();
        for tag in remote.tags(url)? {
            let Some(version) = Version::of_tag(&tag) else {
                continue;
            };
            if let Some((_, other)) = found.iter().find(|(v, _)| *v == version) {
                return Err(format!(
                    "{url} has both {other} and {tag} for version {version}; delete one of the tags"
                ));
            }
            found.push((version, tag));
        }
        found.sort();
        cache.insert(key.clone(), found);
    }
    Ok(&cache[&key])
}

/// The highest tag in `bucket` that satisfies every requirement.
fn best(
    repo: &str,
    bucket: Bucket,
    members: &[&Ask],
    listed: &[(Version, String)],
) -> Result<String, String> {
    let in_bucket: Vec<&(Version, String)> = listed
        .iter()
        .filter(|(v, _)| v.bucket() == bucket)
        .collect();
    if let Some((_, tag)) = in_bucket
        .iter()
        .rev()
        .find(|(v, _)| members.iter().all(|a| satisfies(&a.dep.source, Some(v))))
    {
        return Ok(tag.clone());
    }
    let asked: Vec<String> = members
        .iter()
        .map(|a| format!("{} asks {}", a.asker, a.dep.describe()))
        .collect();
    let available: Vec<String> = listed.iter().map(|(v, _)| v.to_string()).collect();
    let by_one = members.len() > 1
        && members.iter().any(|a| {
            in_bucket
                .iter()
                .any(|(v, _)| satisfies(&a.dep.source, Some(v)))
        });
    if by_one {
        Err(format!(
            "{repo}: {}; no tag satisfies all of them (tags: {})",
            asked.join(" and "),
            available.join(", ")
        ))
    } else {
        Err(format!(
            "no tag of {repo} satisfies {} (tags: {})",
            asked.join(" and "),
            if available.is_empty() {
                "none".to_string()
            } else {
                available.join(", ")
            }
        ))
    }
}

/// One copy for all pins of a repository, which must name one commit.
fn pick_pin(
    repo: &str,
    pins: &[&&Ask],
    old: &BTreeMap<String, LockEntry>,
    update: &BTreeSet<String>,
    remote: &mut dyn Remote,
    downloads: &mut BTreeMap<(String, String), Fetched>,
) -> Result<Choice, String> {
    let mut chosen: Option<(Choice, String, &Ask)> = None;
    for ask in pins {
        let reference = match &ask.dep.source {
            Source::Tag(r) | Source::Sha(r) => r.clone(),
            Source::Version(_) => continue,
        };
        let key = (ask.dep.url.clone(), reference.clone());
        if !downloads.contains_key(&key) {
            let locked = old
                .values()
                .find(|e| e.spec == format!("{}#{reference}", ask.dep.url))
                .filter(|_| !update.contains(&ask.alias));
            let fetched = remote.fetch(&ask.dep.url, &reference, locked, ask.nested)?;
            check_version_agrees("package", &ask.dep.url, &reference, &fetched.manifest)?;
            downloads.insert(key.clone(), fetched);
        }
        let commit = downloads[&key].entry.revision.clone();
        match &chosen {
            None => {
                chosen = Some((
                    Choice {
                        url: ask.dep.url.clone(),
                        reference,
                    },
                    commit,
                    ask,
                ));
            }
            Some((choice, first, by)) => {
                if *first != commit {
                    return Err(format!(
                        "{repo} is pinned to {} by {} and to {} by {}, which are different commits; pin one",
                        by.dep.describe(),
                        by.asker,
                        ask.dep.describe(),
                        ask.asker
                    ));
                }
                // Prefer a tag over a commit as the copy's name, then the smaller spelling.
                let better = (is_hex(&choice.reference, 40), &reference)
                    > (is_hex(&reference, 40), &choice.reference);
                if better {
                    chosen = Some((
                        Choice {
                            url: ask.dep.url.clone(),
                            reference,
                        },
                        commit,
                        ask,
                    ));
                }
            }
        }
    }
    chosen
        .map(|(choice, _, _)| choice)
        .ok_or_else(|| format!("{repo} has no pin"))
}

fn finish(
    asks: &[Ask],
    chosen: BTreeMap<Group, Choice>,
    mut downloads: BTreeMap<(String, String), Fetched>,
    roots: &[(&str, &Project)],
) -> Result<Resolved, String> {
    let mut copies = BTreeMap::new();
    for choice in chosen.values() {
        let key = (choice.url.clone(), choice.reference.clone());
        let Some(fetched) = downloads.remove(&key) else {
            continue;
        };
        let id = copy_id(&choice.url, &choice.reference);
        let mut entry = fetched.entry;
        entry.spec = format!("{}#{}", choice.url, choice.reference);
        copies.insert(
            id.clone(),
            Copy {
                id,
                url: choice.url.clone(),
                reference: choice.reference.clone(),
                entry,
                manifest: fetched.manifest,
            },
        );
    }
    let mut named = BTreeMap::new();
    for ask in asks {
        if !roots.iter().any(|(name, _)| *name == ask.asker) {
            continue;
        }
        let group = group_of(&ask.dep, &ask.repo, &chosen)
            .ok_or_else(|| format!("{} was not resolved", ask.alias))?;
        let choice = &chosen[&group];
        named.insert(ask.alias.clone(), copy_id(&choice.url, &choice.reference));
    }
    Ok(Resolved {
        copies,
        roots: named,
    })
}

fn group_of(dep: &Dependency, repo: &str, chosen: &BTreeMap<Group, Choice>) -> Option<Group> {
    let group = match &dep.source {
        Source::Version(req) => Group(repo.to_string(), Some(req.bucket())),
        _ => Group(repo.to_string(), None),
    };
    chosen.contains_key(&group).then_some(group)
}

#[cfg(test)]
mod tests {
    use super::*;

    const WIRE: &str = "https://github.com/acme/wire.git";

    /// A repository table: url -> tag -> (commit, manifest).
    #[derive(Default)]
    struct Table {
        repos: BTreeMap<String, BTreeMap<String, (String, Project)>>,
        listed: usize,
        fetched: Vec<String>,
    }

    /// A manifest with `version` and `deps` as `(name, url, field, value)`.
    fn manifest(version: Option<&str>, deps: &[(&str, &str, &str, &str)]) -> Project {
        let mut project = Project {
            version: version.map(|v| Version::parse(v).unwrap()),
            ..Project::default()
        };
        for (name, url, field, value) in deps {
            let source = match *field {
                "version" => {
                    Source::Version(crate::project::semver::Requirement::parse(value).unwrap())
                }
                "tag" => Source::Tag((*value).to_string()),
                _ => Source::Sha((*value).to_string()),
            };
            project.dependencies.insert(
                (*name).to_string(),
                Dependency {
                    url: (*url).to_string(),
                    source,
                },
            );
        }
        project
    }

    impl Table {
        fn tag(&mut self, url: &str, tag: &str, project: Project) -> &mut Self {
            let commit = format!(
                "{:040x}",
                self.repos.values().map(BTreeMap::len).sum::<usize>() + 1
            );
            self.repos
                .entry(url.to_string())
                .or_default()
                .insert(tag.to_string(), (commit, project));
            self
        }
        fn plain(&mut self, url: &str, tags: &[&str]) -> &mut Self {
            for tag in tags {
                self.tag(url, tag, manifest(None, &[]));
            }
            self
        }
    }

    impl Remote for Table {
        fn tags(&mut self, url: &str) -> Result<Vec<String>, String> {
            self.listed += 1;
            self.repos
                .iter()
                .find(|(u, _)| repo_key(u) == repo_key(url))
                .map(|(_, tags)| tags.keys().cloned().collect())
                .ok_or_else(|| format!("no repository {url}"))
        }
        fn fetch(
            &mut self,
            url: &str,
            reference: &str,
            _locked: Option<&LockEntry>,
            _nested: bool,
        ) -> Result<Fetched, String> {
            self.fetched.push(format!("{url}#{reference}"));
            let tags = self
                .repos
                .iter()
                .find(|(u, _)| repo_key(u) == repo_key(url))
                .map(|(_, tags)| tags)
                .ok_or_else(|| format!("no repository {url}"))?;
            let (commit, project) = tags
                .get(reference)
                .or_else(|| tags.values().find(|(c, _)| c == reference))
                .ok_or_else(|| format!("{url} has no {reference}"))?;
            Ok(Fetched {
                entry: LockEntry {
                    spec: format!("{url}#{reference}"),
                    revision: commit.clone(),
                    sha256: "0".repeat(64),
                },
                manifest: project.clone(),
            })
        }
    }

    fn run(
        table: &mut Table,
        root: &Project,
        old: &BTreeMap<String, LockEntry>,
    ) -> Result<Resolved, String> {
        resolve(&[("the project", root)], old, &BTreeSet::new(), table)
    }

    fn ids(resolved: &Resolved) -> Vec<&str> {
        resolved.copies.keys().map(String::as_str).collect()
    }

    /// `@a` and `@b` both need `wire`; `a_wants` and `b_wants` are their requirements.
    fn diamond(a_wants: &str, b_wants: &str) -> (Table, Project) {
        let mut table = Table::default();
        table.plain(WIRE, &["v1.2.0", "v1.4.2", "v1.5.0", "v2.0.1"]);
        table.tag(
            "https://h/a.git",
            "v1.0.0",
            manifest(None, &[("@wire", WIRE, "version", a_wants)]),
        );
        table.tag(
            "https://h/b.git",
            "v1.0.0",
            manifest(None, &[("@wire", WIRE, "version", b_wants)]),
        );
        let root = manifest(
            None,
            &[
                ("@a", "https://h/a.git", "version", "1"),
                ("@b", "https://h/b.git", "version", "1"),
            ],
        );
        (table, root)
    }

    #[test]
    fn requirements_in_one_range_share_the_highest_tag_that_satisfies_all() {
        let (mut table, root) = diamond("^1.2", "^1.4");
        let resolved = run(&mut table, &root, &BTreeMap::new()).unwrap();
        assert_eq!(
            ids(&resolved),
            ["github.com/acme/wire@v1.5.0", "h/a@v1.0.0", "h/b@v1.0.0"]
        );
        assert_eq!(resolved.roots["@a"], "h/a@v1.0.0");
        // The two tags above 1.4 satisfy both; a requirement of =1.4.2 narrows it.
        let (mut table, root) = diamond("^1.2", "=1.4.2");
        let resolved = run(&mut table, &root, &BTreeMap::new()).unwrap();
        assert!(resolved.copies.contains_key("github.com/acme/wire@v1.4.2"));
        assert_eq!(resolved.copies.len(), 3);
    }

    #[test]
    fn a_new_major_is_a_separate_copy() {
        let (mut table, root) = diamond("^1.2", "^2");
        let resolved = run(&mut table, &root, &BTreeMap::new()).unwrap();
        let wires: Vec<&str> = ids(&resolved)
            .into_iter()
            .filter(|id| id.starts_with("github.com/acme/wire@"))
            .collect();
        assert_eq!(
            wires,
            ["github.com/acme/wire@v1.5.0", "github.com/acme/wire@v2.0.1"]
        );
    }

    #[test]
    fn zero_versions_split_at_the_minor() {
        let mut table = Table::default();
        table.plain(WIRE, &["v0.4.1", "v0.4.5", "v0.5.0"]);
        let root = manifest(
            None,
            &[
                ("@x", WIRE, "version", "^0.4.1"),
                ("@y", WIRE, "version", "^0.4.3"),
                ("@z", WIRE, "version", "^0.5"),
            ],
        );
        let resolved = run(&mut table, &root, &BTreeMap::new()).unwrap();
        assert_eq!(
            ids(&resolved),
            ["github.com/acme/wire@v0.4.5", "github.com/acme/wire@v0.5.0"]
        );
        assert_eq!(resolved.roots["@x"], resolved.roots["@y"]);
    }

    #[test]
    fn calver_stays_within_its_year() {
        let mut table = Table::default();
        table.plain(WIRE, &["2026.11.0", "2026.12.0", "2027.1.0"]);
        let root = manifest(None, &[("@w", WIRE, "version", "2026.11")]);
        let resolved = run(&mut table, &root, &BTreeMap::new()).unwrap();
        assert_eq!(ids(&resolved), ["github.com/acme/wire@2026.12.0"]);
    }

    #[test]
    fn a_pick_that_changes_withdraws_what_the_old_pick_asked_for() {
        let mut table = Table::default();
        table.plain(WIRE, &["v1.0.5"]);
        table.tag(
            "https://h/x.git",
            "v1.0.0",
            manifest(None, &[("@wire", WIRE, "version", "=1.0.5")]),
        );
        table.tag("https://h/x.git", "v1.1.0", manifest(None, &[]));
        table.tag("https://h/w.git", "v1.0.0", manifest(None, &[]));
        table.tag(
            "https://h/w.git",
            "v1.1.0",
            manifest(None, &[("@x", "https://h/x.git", "version", "=1.0.0")]),
        );
        let root = manifest(
            None,
            &[
                ("@x", "https://h/x.git", "version", "1"),
                ("@w", "https://h/w.git", "version", "1"),
            ],
        );
        let resolved = run(&mut table, &root, &BTreeMap::new()).unwrap();
        // w 1.1.0 asks for x =1.0.0, and x 1.0.0 asks for wire; the first round saw x 1.1.0.
        assert!(resolved.copies.contains_key("h/x@v1.0.0"));
        assert!(!resolved.copies.contains_key("h/x@v1.1.0"));
        assert!(resolved.copies.contains_key("github.com/acme/wire@v1.0.5"));
    }

    #[test]
    fn picks_that_never_settle_are_an_error_not_a_loop() {
        let mut table = Table::default();
        table.tag("https://h/x.git", "v1.0.0", manifest(None, &[]));
        table.tag(
            "https://h/x.git",
            "v1.1.0",
            manifest(None, &[("@y", "https://h/y.git", "version", "=1.0.0")]),
        );
        table.tag("https://h/y.git", "v1.0.0", manifest(None, &[]));
        table.tag(
            "https://h/y.git",
            "v1.1.0",
            manifest(None, &[("@x", "https://h/x.git", "version", "=1.0.0")]),
        );
        let root = manifest(
            None,
            &[
                ("@x", "https://h/x.git", "version", "1"),
                ("@y", "https://h/y.git", "version", "1"),
            ],
        );
        let error = run(&mut table, &root, &BTreeMap::new()).err().unwrap();
        assert!(error.contains("do not settle"), "{error}");
    }

    #[test]
    fn requirements_with_no_common_tag_name_both_askers() {
        let (mut table, root) = diamond("^1.2", "=1.1.0");
        let error = run(&mut table, &root, &BTreeMap::new()).err().unwrap();
        assert!(
            error.contains("h/a@v1.0.0 asks ^1.2 and h/b@v1.0.0 asks =1.1.0")
                && error.contains("no tag satisfies all of them"),
            "{error}"
        );
        let (mut table, root) = diamond("^3.0", "^3.0");
        let error = run(&mut table, &root, &BTreeMap::new()).err().unwrap();
        assert!(
            error.contains("no tag of github.com/acme/wire satisfies"),
            "{error}"
        );
        assert!(
            error.contains("tags: 1.2.0, 1.4.2, 1.5.0, 2.0.1"),
            "{error}"
        );
    }

    #[test]
    fn a_pin_and_a_version_for_one_repository_are_an_error_naming_both() {
        let mut table = Table::default();
        table.plain(WIRE, &["v1.2.0"]);
        table.tag(
            "https://h/a.git",
            "v1.0.0",
            manifest(None, &[("@wire", WIRE, "tag", "v1.2.0")]),
        );
        let root = manifest(
            None,
            &[
                ("@a", "https://h/a.git", "version", "1"),
                ("@wire", WIRE, "version", "^1.2"),
            ],
        );
        let error = run(&mut table, &root, &BTreeMap::new()).err().unwrap();
        assert!(
            error.contains("v1.2.0 by h/a@v1.0.0") && error.contains("^1.2 by the project"),
            "{error}"
        );
    }

    #[test]
    fn pins_unify_only_on_one_commit() {
        let mut table = Table::default();
        table.plain(WIRE, &["v1.2.0", "v1.3.0"]);
        let same = manifest(
            None,
            &[
                ("@a", WIRE, "tag", "v1.2.0"),
                ("@b", "https://GitHub.com/acme/wire", "tag", "v1.2.0"),
            ],
        );
        let resolved = run(&mut table, &same, &BTreeMap::new()).unwrap();
        assert_eq!(ids(&resolved), ["github.com/acme/wire@v1.2.0"]);
        let moved = manifest(
            None,
            &[("@a", WIRE, "tag", "v1.2.0"), ("@b", WIRE, "tag", "v1.3.0")],
        );
        let error = run(&mut table, &moved, &BTreeMap::new()).err().unwrap();
        assert!(error.contains("different commits"), "{error}");
    }

    #[test]
    fn one_repository_under_two_names_is_one_copy() {
        let mut table = Table::default();
        table.plain(WIRE, &["v1.2.0"]);
        let root = manifest(
            None,
            &[
                ("@pg", WIRE, "version", "1"),
                (
                    "@postgres",
                    "http://github.com/acme/wire/",
                    "version",
                    "^1.2",
                ),
            ],
        );
        let resolved = run(&mut table, &root, &BTreeMap::new()).unwrap();
        assert_eq!(resolved.copies.len(), 1);
        assert_eq!(resolved.roots["@pg"], resolved.roots["@postgres"]);
    }

    #[test]
    fn a_satisfied_lock_lists_no_tags_and_update_picks_again() {
        let (mut table, root) = diamond("^1.2", "^1.4");
        let first = run(&mut table, &root, &BTreeMap::new()).unwrap();
        let mut old = first.lock();
        // The lock holds wire 1.4.2 although 1.5.0 exists upstream.
        let wire = old.remove("github.com/acme/wire@v1.5.0").unwrap();
        old.insert(
            "github.com/acme/wire@v1.4.2".into(),
            LockEntry {
                spec: format!("{WIRE}#v1.4.2"),
                ..wire
            },
        );
        table.listed = 0;
        let kept = run(&mut table, &root, &old).unwrap();
        assert!(
            kept.copies.contains_key("github.com/acme/wire@v1.4.2"),
            "{:?}",
            ids(&kept)
        );
        assert_eq!(table.listed, 0, "the lock satisfied every requirement");
        // `--update @wire` names the dependency under whichever package declares it.
        let update = BTreeSet::from(["@wire".to_string()]);
        let again = resolve(&[("the project", &root)], &old, &update, &mut table).unwrap();
        assert!(again.copies.contains_key("github.com/acme/wire@v1.5.0"));
        let unknown = BTreeSet::from(["@nope".to_string()]);
        let refused = resolve(&[("the project", &root)], &old, &unknown, &mut table).err();
        assert!(refused.unwrap().contains("no such dependency"));
    }

    #[test]
    fn update_picks_the_highest_tag_again() {
        let mut table = Table::default();
        table.plain(WIRE, &["v1.2.0", "v1.4.2"]);
        let root = manifest(None, &[("@wire", WIRE, "version", "1")]);
        let old = BTreeMap::from([(
            "github.com/acme/wire@v1.2.0".to_string(),
            LockEntry {
                spec: format!("{WIRE}#v1.2.0"),
                revision: "1".repeat(40),
                sha256: "0".repeat(64),
            },
        )]);
        let kept = run(&mut table, &root, &old).unwrap();
        assert_eq!(ids(&kept), ["github.com/acme/wire@v1.2.0"]);
        let update = BTreeSet::from(["@wire".to_string()]);
        let moved = resolve(&[("the project", &root)], &old, &update, &mut table).unwrap();
        assert_eq!(ids(&moved), ["github.com/acme/wire@v1.4.2"]);
    }

    #[test]
    fn a_tag_and_the_manifest_version_must_agree() {
        for (tag, declared, ok) in [
            ("v1.4.2", Some("1.4.2"), true),
            ("1.4.2", Some("1.4.2"), true),
            ("v1.4.2", None, true),
            ("v1.4.2", Some("1.4.1"), false),
            ("release-1", Some("9.9.9"), true),
        ] {
            let mut table = Table::default();
            table.tag(WIRE, tag, manifest(declared, &[]));
            let source = if Version::of_tag(tag).is_some() {
                "version"
            } else {
                "tag"
            };
            let root = manifest(
                None,
                &[(
                    "@wire",
                    WIRE,
                    source,
                    if source == "tag" { tag } else { "1" },
                )],
            );
            let result = run(&mut table, &root, &BTreeMap::new());
            assert_eq!(result.is_ok(), ok, "{tag} {declared:?}");
            if let Err(message) = result.map(|_| ()) {
                assert!(
                    message.contains("holds ms.toml version 1.4.1, not 1.4.2")
                        && message.contains("ask the author to fix the tag")
                        && message.contains("=1.4.1"),
                    "{message}"
                );
            }
        }
    }

    #[test]
    fn a_commit_pin_is_named_by_its_commit_whatever_the_manifest_says() {
        let sha = "a".repeat(40);
        for declared in [None, Some("3.0.0")] {
            let mut table = Table::default();
            table.tag(WIRE, "v1.0.0", manifest(None, &[]));
            let commit = table.repos[WIRE]["v1.0.0"].0.clone();
            table
                .repos
                .get_mut(WIRE)
                .unwrap()
                .insert(sha.clone(), (commit, manifest(declared, &[])));
            let root = manifest(None, &[("@wire", WIRE, "sha", &sha)]);
            let resolved = run(&mut table, &root, &BTreeMap::new()).unwrap();
            assert_eq!(ids(&resolved), [format!("github.com/acme/wire@{sha}")]);
        }
    }

    #[test]
    fn a_package_may_not_depend_on_a_local_repository() {
        let mut table = Table::default();
        table.tag(
            "https://h/a.git",
            "v1.0.0",
            manifest(None, &[("@w", "file:///tmp/w", "tag", "v1")]),
        );
        let root = manifest(None, &[("@a", "https://h/a.git", "version", "1")]);
        let error = run(&mut table, &root, &BTreeMap::new()).err().unwrap();
        assert!(error.contains("must use https://"), "{error}");
    }

    #[test]
    fn repository_keys_ignore_scheme_case_and_suffix() {
        for url in [
            "https://github.com/acme/wire.git",
            "http://GitHub.com/acme/wire",
            "https://github.com/acme/wire/",
        ] {
            assert_eq!(repo_key(url), "github.com/acme/wire", "{url}");
        }
        assert_eq!(repo_key("file:///tmp/x"), "file/tmp/x");
        assert_ne!(repo_key("https://github.com/Acme/wire"), repo_key(WIRE));
    }
}
