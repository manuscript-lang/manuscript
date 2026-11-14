//! Tree operations: glob queries and `copy`.
use crate::err::{Fail, Res};
use crate::ops;
use crate::ops::poll_cancel;
use crate::path;
use crate::sys::{self, CPath};
use alloc::string::String;
use alloc::vec::Vec;
use ms_rt_abi::{STATUS_ALREADY_EXISTS, STATUS_LIMIT_EXCEEDED};
use ms_std_path::glob::Glob;

pub const UNLIMITED: i64 = i64::MAX;

fn limit_exceeded() -> Fail {
    Fail::status(STATUS_LIMIT_EXCEEDED)
}

fn cpath(p: &[u8]) -> Res<CPath> {
    CPath::new(p).ok_or_else(Fail::invalid)
}

fn lstat(p: &[u8]) -> Res<sys::Stat> {
    sys::stat(&cpath(p)?, false).map_err(|e| Fail::errno(e, "lstat", p))
}

fn is_dir(st: &sys::Stat) -> bool {
    st.is_dir()
}

fn is_link(st: &sys::Stat) -> bool {
    st.is_link()
}

fn is_regular(st: &sys::Stat) -> bool {
    st.is_regular()
}

fn same_file(a: &sys::Stat, b: &sys::Stat) -> bool {
    a.same_file(b)
}

/// The entries of a directory in native order.
fn read_dir(p: &[u8]) -> Res<sys::DirEntries> {
    sys::read_dir(&cpath(p)?).map_err(|e| Fail::errno(e, "open", p))
}

// ---------------------------------------------------------------------------
// copy support
// ---------------------------------------------------------------------------

/// Whether `target` is `source` or lies inside it (both absolute and cleaned).
fn within_path(source: &[u8], target: &[u8]) -> bool {
    let source = path::clean(source);
    let target = path::clean(target);
    if source.last().is_some_and(|&c| path::is_sep(c)) {
        return target.starts_with(&source);
    }
    target == source
        || (target.starts_with(&source)
            && target.get(source.len()).is_some_and(|&c| path::is_sep(c)))
}

/// `resolveDestination`: resolves the existing ancestors of `dest` through links.
fn resolve_destination(dest: &[u8]) -> Result<Vec<u8>, Fail> {
    let mut ancestor = dest.to_vec();
    let mut suffix: Vec<Vec<u8>> = Vec::new();
    loop {
        let c = cpath(&ancestor)?;
        match sys::stat(&c, false) {
            Ok(_) => break,
            Err(e) if sys::is_not_found(e) => {}
            Err(e) => return Err(Fail::errno(e, "lstat", &ancestor)),
        }
        let parent = path::dir(&ancestor);
        if parent == ancestor {
            return Err(Fail::invalid());
        }
        suffix.push(path::base(&ancestor));
        ancestor = parent;
    }
    let mut real = match ops::eval_symlinks(&ancestor) {
        Ok(real) => real,
        // A dangling link has no target to resolve; it is the entry a replacing copy unlinks.
        Err(e) if sys::is_not_found(e) && ancestor != path::dir(&ancestor) => {
            let parent = path::dir(&ancestor);
            let parent =
                ops::eval_symlinks(&parent).map_err(|e| Fail::errno(e, "lstat", &parent))?;
            path::join(&parent, &path::base(&ancestor))
        }
        Err(e) => return Err(Fail::errno(e, "lstat", &ancestor)),
    };
    for part in suffix.iter().rev() {
        real = path::join(&real, part);
    }
    Ok(real)
}

fn remove_ignoring_missing(p: &[u8]) -> Res<()> {
    match sys::remove(&cpath(p)?) {
        Err(e) if !sys::is_not_found(e) => Err(Fail::errno(e, "remove", p)),
        _ => Ok(()),
    }
}

fn open_out(dest: &[u8], mode: u32) -> Res<sys::Fd> {
    let c = cpath(dest)?;
    sys::open(&c, sys::O_WRONLY | sys::O_CREAT | sys::O_EXCL, mode)
        .map_err(|e| Fail::errno(e, "open", dest))
}

/// Copies `input` to `output`, charging `bytes`; fails with `LimitExceeded` past the budget.
fn copy_stream(input: sys::Fd, output: sys::Fd, dest: &[u8], bytes: &mut i64) -> Res<()> {
    let mut buffer = alloc::vec![0u8; 65536];
    loop {
        poll_cancel()?;
        let n = sys::read(input, &mut buffer).map_err(|e| Fail::errno(e, "read", b""))?;
        if n == 0 {
            return Ok(());
        }
        if n as i64 > *bytes {
            return Err(limit_exceeded());
        }
        let mut chunk = &buffer[..n];
        while !chunk.is_empty() {
            let written = sys::write(output, chunk).map_err(|e| Fail::errno(e, "write", dest))?;
            if written == 0 {
                return Err(Fail::failed("short write"));
            }
            chunk = &chunk[written..];
        }
        *bytes -= n as i64;
    }
}

// ---------------------------------------------------------------------------
// copy
// ---------------------------------------------------------------------------

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Clone {
    None,
    Try,
    Force,
}

impl Clone {
    pub fn parse(text: &[u8]) -> Option<Clone> {
        match text {
            b"none" => Some(Clone::None),
            b"try" => Some(Clone::Try),
            b"force" => Some(Clone::Force),
            _ => None,
        }
    }
}

pub struct CopyOptions {
    pub recursive: bool,
    pub replace: bool,
    pub error_on_exists: bool,
    pub dereference: bool,
    pub preserve: bool,
    pub verbatim: bool,
    pub clone: Clone,
    pub entries: i64,
    pub bytes: i64,
}

/// A caller-supplied predicate over `(source, destination)`; return `false` to skip an entry.
pub type Filter<'a> = &'a mut dyn FnMut(&[u8], &[u8]) -> bool;

struct Copier<'a, 'b> {
    o: CopyOptions,
    filter: Option<Filter<'b>>,
    ancestors: Vec<Vec<u8>>,
    _marker: core::marker::PhantomData<&'a ()>,
}

fn copy_check_destination(source: &[u8], dest: &[u8], follow: bool) -> Res<()> {
    let mut canonical = ops::eval_symlinks(source).map_err(|e| Fail::errno(e, "lstat", source));
    if !follow
        && let Ok(info) = lstat(source)
        && is_link(&info)
    {
        let parent =
            ops::eval_symlinks(&path::dir(source)).map_err(|e| Fail::errno(e, "lstat", source));
        canonical = parent.map(|p| path::join(&p, &path::base(source)));
    }
    let canonical = canonical?;
    let canonical_dest = resolve_destination(dest)?;
    if within_path(&canonical, &canonical_dest) {
        return Err(Fail::invalid());
    }
    Ok(())
}

fn chtimes(dest: &[u8], info: &sys::Stat) -> Res<()> {
    let c = cpath(dest)?;
    sys::utimens(&c, info.accessed, info.modified, true)
        .map_err(|e| Fail::errno(e, "chtimes", dest))
}

fn chmod_path(dest: &[u8], mode: u32) -> Res<()> {
    sys::chmod(&cpath(dest)?, mode & 0o7777).map_err(|e| Fail::errno(e, "chmod", dest))
}

/// Shares the extents of `source` with a new `destination` where the host supports it.
fn clone_file(source: &[u8], destination: &[u8]) -> Result<(), Fail> {
    let input =
        sys::open(&cpath(source)?, sys::O_RDONLY, 0).map_err(|e| Fail::errno(e, "open", source))?;
    let result = (|| {
        let st = sys::fstat(input).map_err(|e| Fail::errno(e, "stat", source))?;
        let output = open_out(destination, st.mode & 0o7777)?;
        let r = sys::clone_file(output, input);
        let _ = sys::close(output);
        if let Err(e) = r {
            let _ = sys::unlink(&cpath(destination)?);
            return Err(Fail::errno(e, "ioctl", destination));
        }
        Ok(())
    })();
    let _ = sys::close(input);
    result
}

impl Copier<'_, '_> {
    fn copy(&mut self, source: &[u8], dest: &[u8]) -> Res<()> {
        poll_cancel()?;
        if self.o.entries <= 0 {
            return Err(limit_exceeded());
        }
        self.o.entries -= 1;
        if let Some(f) = self.filter.as_mut()
            && !f(source, dest)
        {
            return Ok(());
        }
        let mut info = lstat(source)?;
        if self.o.dereference {
            info = sys::stat(&cpath(source)?, true).map_err(|e| Fail::errno(e, "stat", source))?;
        }
        let previous = match sys::stat(&cpath(dest)?, false) {
            Ok(st) => Some(st),
            Err(e) if sys::is_not_found(e) => None,
            Err(e) => return Err(Fail::errno(e, "lstat", dest)),
        };
        if let Some(prev) = &previous
            && same_file(&info, prev)
        {
            return Err(Fail::invalid());
        }
        if is_dir(&info) {
            return self.copy_directory(source, dest, &info, previous.as_ref());
        }
        let exists = previous.is_some();
        if exists && !self.o.replace {
            return if self.o.error_on_exists {
                Err(Fail::status(STATUS_ALREADY_EXISTS))
            } else {
                Ok(())
            };
        }
        if is_link(&info) {
            let mut target =
                sys::readlink(&cpath(source)?).map_err(|e| Fail::errno(e, "readlink", source))?;
            if !self.o.verbatim && !path::is_abs(&target) {
                target = path::join(&ops::absolute(&path::dir(source)), &target);
            }
            if exists {
                remove_ignoring_missing(dest)?;
            }
            return sys::symlink(&cpath(&target)?, &cpath(dest)?)
                .map_err(|e| Fail::errno_paths(e, "symlink", &[&target, dest]));
        }
        if !is_regular(&info) {
            return Err(Fail::invalid());
        }
        if info.size > self.o.bytes {
            return Err(limit_exceeded());
        }
        self.copy_file(source, dest, &info, exists)
    }

    fn copy_directory(
        &mut self,
        source: &[u8],
        dest: &[u8],
        info: &sys::Stat,
        previous: Option<&sys::Stat>,
    ) -> Res<()> {
        if !self.o.recursive {
            return Err(Fail::invalid());
        }
        if previous.is_some_and(|p| !is_dir(p)) {
            return Err(Fail::invalid());
        }
        if previous.is_some() && !self.o.replace && self.o.error_on_exists {
            return Err(Fail::status(STATUS_ALREADY_EXISTS));
        }
        let canonical = ops::eval_symlinks(source).map_err(|e| Fail::errno(e, "lstat", source))?;
        if self.ancestors.contains(&canonical) {
            return Err(Fail::invalid());
        }
        self.ancestors.push(canonical);
        let result = self.copy_directory_inner(source, dest, info, previous.is_some());
        self.ancestors.pop();
        result
    }

    fn copy_directory_inner(
        &mut self,
        source: &[u8],
        dest: &[u8],
        info: &sys::Stat,
        exists: bool,
    ) -> Res<()> {
        if !exists {
            sys::mkdir(&cpath(dest)?, 0o700).map_err(|e| Fail::errno(e, "mkdir", dest))?;
        }
        for (name, _) in read_dir(source)? {
            self.copy(&path::join(source, &name), &path::join(dest, &name))?;
        }
        if !exists {
            chmod_path(dest, info.mode)?;
        }
        if self.o.preserve {
            return chtimes(dest, info);
        }
        Ok(())
    }

    fn copy_file(&mut self, source: &[u8], dest: &[u8], info: &sys::Stat, exists: bool) -> Res<()> {
        let input = sys::open(&cpath(source)?, sys::O_RDONLY, 0)
            .map_err(|e| Fail::errno(e, "open", source))?;
        let result = self.copy_file_from(input, source, dest, info, exists);
        let _ = sys::close(input);
        result
    }

    fn copy_file_from(
        &mut self,
        input: sys::Fd,
        source: &[u8],
        dest: &[u8],
        info: &sys::Stat,
        exists: bool,
    ) -> Res<()> {
        let acquired = sys::fstat(input).map_err(|e| Fail::errno(e, "stat", source))?;
        if !same_file(info, &acquired) {
            return Err(Fail::invalid());
        }
        if exists {
            remove_ignoring_missing(dest)?;
        }
        if self.o.clone != Clone::None {
            match clone_file(source, dest) {
                Ok(()) => {
                    let cloned =
                        sys::stat(&cpath(dest)?, true).map_err(|e| Fail::errno(e, "stat", dest))?;
                    if cloned.size > self.o.bytes {
                        return Err(limit_exceeded());
                    }
                    self.o.bytes -= cloned.size;
                    chmod_path(dest, info.mode)?;
                    return if self.o.preserve {
                        chtimes(dest, info)
                    } else {
                        Ok(())
                    };
                }
                Err(e) => {
                    // A failed clone removed only the file it created; take the ordinary copy unless forced.
                    if self.o.clone == Clone::Force || sys::stat(&cpath(dest)?, false).is_ok() {
                        return Err(e);
                    }
                }
            }
        }
        let output = open_out(dest, info.mode & 0o7777)?;
        let copied = copy_stream(input, output, dest, &mut self.o.bytes);
        let chmoded = copied.and_then(|()| {
            sys::fchmod(output, info.mode & 0o7777).map_err(|e| Fail::errno(e, "chmod", dest))
        });
        let closed = sys::close(output).map_err(|e| Fail::errno(e, "close", dest));
        chmoded.and(closed)?;
        if self.o.preserve {
            chtimes(dest, info)
        } else {
            Ok(())
        }
    }
}

/// `copy`: copies a file or tree under `options`, asking `filter` about each `(source, destination)`.
pub fn copy(
    source: &[u8],
    destination: &[u8],
    options: CopyOptions,
    filter: Option<Filter<'_>>,
) -> Res<()> {
    copy_check_destination(source, destination, options.dereference)?;
    let mut c = Copier {
        o: options,
        filter,
        ancestors: Vec::new(),
        _marker: core::marker::PhantomData,
    };
    c.copy(source, destination)
}

// ---------------------------------------------------------------------------
// glob_entries
// ---------------------------------------------------------------------------

/// One match of `glob_entries`.
#[derive(Debug, Clone)]
pub struct PathEntry {
    pub path: Vec<u8>,
    pub name: Vec<u8>,
    pub directory: bool,
    pub symlink: bool,
}

pub struct GlobOptions<'a> {
    pub patterns: &'a [&'a [u8]],
    pub exclude: &'a [&'a [u8]],
    pub follow_links: bool,
    pub max_entries: i64,
    pub max_results: i64,
}

/// A parsed pattern list with the text it came from, so absolute patterns can be told apart.
struct Compiled {
    glob: Glob,
    absolute: bool,
}

fn compile(patterns: &[&[u8]]) -> Option<Vec<Compiled>> {
    patterns
        .iter()
        .map(|p| {
            let text = core::str::from_utf8(p).ok()?;
            Some(Compiled {
                glob: Glob::new(text)?,
                absolute: text.starts_with('/'),
            })
        })
        .collect()
}

/// `glob_entries`: matches of any `patterns` not hit by `exclude` or the callback, sorted by path.
pub fn glob_entries(
    root: &[u8],
    o: &GlobOptions<'_>,
    exclude: Option<&mut dyn FnMut(&PathEntry) -> bool>,
) -> Res<Vec<PathEntry>> {
    let (Some(patterns), Some(excluded)) = (compile(o.patterns), compile(o.exclude)) else {
        return Err(Fail::invalid());
    };
    if root.is_empty() {
        return Err(Fail::invalid());
    }
    // Keep every traversal start in the same coordinates, including `.` and parent patterns.
    let root = ops::absolute(root);
    let mut exclude = exclude;
    let mut state = GlobState {
        remaining: o.max_entries,
        items: alloc::collections::BTreeMap::new(),
        ancestors: Vec::new(),
    };

    // Relative parent and absolute patterns can start outside the root, as in Node.
    let mut roots: Vec<Vec<u8>> = alloc::vec![root.clone()];
    for pattern in o.patterns {
        let mut base = root.clone();
        let mut rest: &[u8] = pattern;
        if path::is_abs(rest) {
            base = alloc::vec![b'/'];
            while rest.first() == Some(&b'/') {
                rest = &rest[1..];
            }
        }
        for part in rest.split(|&c| c == b'/') {
            if part == b".." {
                base = path::dir(&base);
            } else if part == b"." || part.is_empty() {
                continue;
            } else if part.iter().any(|c| b"*?[]{}()!".contains(c)) {
                break;
            } else {
                base = path::join(&base, part);
            }
        }
        let is_directory = CPath::new(&base)
            .and_then(|c| sys::stat(&c, false).ok())
            .is_some_and(|st| is_dir(&st));
        if is_directory {
            roots.push(base);
        } else if base != root {
            roots.push(path::dir(&base));
        }
    }
    roots.sort();
    roots.dedup();
    roots.sort_by(|a, b| a.len().cmp(&b.len()).then_with(|| a.cmp(b)));
    let mut selected: Vec<Vec<u8>> = Vec::new();
    for start in roots {
        if !selected.iter().any(|parent| within_path(parent, &start)) {
            selected.push(start);
        }
    }
    for start in selected {
        match state.visit(&start, &root, &patterns, &excluded, o, &mut exclude) {
            Ok(()) => {}
            Err(f) if f.status == ms_rt_abi::STATUS_NOT_FOUND => continue,
            Err(f) => return Err(f),
        }
    }
    Ok(state.items.into_values().collect())
}

struct GlobState {
    remaining: i64,
    items: alloc::collections::BTreeMap<Vec<u8>, PathEntry>,
    ancestors: Vec<Vec<u8>>,
}

type ExcludeFn<'a> = Option<&'a mut dyn FnMut(&PathEntry) -> bool>;

impl GlobState {
    fn visit(
        &mut self,
        p: &[u8],
        root: &[u8],
        patterns: &[Compiled],
        excluded: &[Compiled],
        o: &GlobOptions<'_>,
        exclude: &mut ExcludeFn<'_>,
    ) -> Res<()> {
        poll_cancel()?;
        if self.remaining == 0 {
            return Err(limit_exceeded());
        }
        self.remaining -= 1;
        let mut info = lstat(p)?;
        let rel = portable_separators(ops::lossy_name(&relative(root, p)));
        let name = ops::lossy_name(&path::base(p));
        let value = PathEntry {
            path: rel.clone(),
            name,
            directory: is_dir(&info),
            symlink: is_link(&info),
        };
        let absolute_text = String::from_utf8_lossy(p).into_owned();
        let relative_text = String::from_utf8_lossy(&rel).into_owned();
        let target = |c: &Compiled| {
            if c.absolute {
                absolute_text.as_str()
            } else {
                relative_text.as_str()
            }
        };
        if excluded.iter().any(|c| c.glob.matches(target(c))) {
            return Ok(());
        }
        if let Some(f) = exclude.as_mut()
            && f(&value)
        {
            return Ok(());
        }
        if patterns.iter().any(|c| c.glob.matches(target(c)))
            && !self.items.contains_key(&value.path)
        {
            if self.items.len() as i64 >= o.max_results {
                return Err(limit_exceeded());
            }
            self.items.insert(value.path.clone(), value.clone());
        }
        if is_link(&info) && o.follow_links {
            match sys::stat(&cpath(p)?, true) {
                Ok(st) => info = st,
                // A dangling or looping link has no directory to enter.
                Err(e) if sys::is_not_found(e) || sys::is_link_loop(e) => return Ok(()),
                Err(e) => return Err(Fail::errno(e, "stat", p)),
            }
        }
        if !is_dir(&info) {
            return Ok(());
        }
        let canonical = ops::eval_symlinks(p).map_err(|e| Fail::errno(e, "lstat", p))?;
        if self.ancestors.contains(&canonical) {
            return Ok(());
        }
        self.ancestors.push(canonical);
        let result = (|| {
            for (child, _) in read_dir(p)? {
                self.visit(&path::join(p, &child), root, patterns, excluded, o, exclude)?;
            }
            Ok(())
        })();
        self.ancestors.pop();
        result
    }
}

/// `filepath.Rel(root, p)` for an `p` at or under `root`, or reached through `..` patterns.
/// Matched paths use `/` on every host, as patterns do; a Windows backslash is a separator, not a name byte.
#[cfg(windows)]
fn portable_separators(path: Vec<u8>) -> Vec<u8> {
    path.into_iter()
        .map(|b| if b == b'\\' { b'/' } else { b })
        .collect()
}

#[cfg(not(windows))]
fn portable_separators(path: Vec<u8>) -> Vec<u8> {
    path
}

fn relative(root: &[u8], p: &[u8]) -> Vec<u8> {
    let root = path::clean(root);
    let p = path::clean(p);
    let root = sys::path_of(&root);
    let p = sys::path_of(&p);
    let meaningful = |c: &std::path::Component<'_>| *c != std::path::Component::CurDir;
    let mut from = root.components().filter(meaningful);
    let mut to = p.components().filter(meaningful);
    while let (Some(a), Some(b)) = (from.clone().next(), to.clone().next()) {
        if a != b {
            break;
        }
        from.next();
        to.next();
    }
    let mut out = std::path::PathBuf::new();
    for _ in from {
        out.push("..");
    }
    for part in to {
        out.push(part.as_os_str());
    }
    if out.as_os_str().is_empty() {
        out.push(".");
    }
    sys::os_bytes(out.as_os_str())
}

/// Test helper: the sorted relative matches of one pattern, as `glob_entries` returns them.
#[cfg(test)]
pub(crate) fn glob(root: &[u8], pattern: &[u8], max: i64) -> Res<Vec<Vec<u8>>> {
    let patterns: [&[u8]; 1] = [pattern];
    let options = GlobOptions {
        patterns: &patterns,
        exclude: &[],
        follow_links: false,
        max_entries: i64::MAX,
        max_results: max,
    };
    Ok(glob_entries(root, &options, None)?
        .into_iter()
        .map(|e| e.path)
        .collect())
}

/// Test helper: a recursive copy with entry and byte budgets.
#[cfg(test)]
pub(crate) fn copy_tree(
    source: &[u8],
    destination: &[u8],
    replace: bool,
    entries: i64,
    bytes: i64,
) -> Res<()> {
    let options = CopyOptions {
        recursive: true,
        replace,
        error_on_exists: true,
        dereference: false,
        preserve: false,
        verbatim: false,
        clone: Clone::None,
        entries,
        bytes,
    };
    copy(source, destination, options, None)
}

#[cfg(test)]
mod tests {
    use super::*;
    use alloc::string::String;
    use ms_rt_abi::STATUS_INVALID_INPUT;

    #[test]
    fn relative_paths_keep_whole_components() {
        let cases: &[(&[u8], &[u8], &[u8])] = &[
            (b".", b"a.txt", b"a.txt"),
            (b"./", b"./a.txt", b"a.txt"),
            (b".", b"sub/a.txt", b"sub/a.txt"),
            (b"sub", b"a.txt", b"../a.txt"),
            (b"sub/deep", b"a.txt", b"../../a.txt"),
            (b"sub", b"sub", b"."),
            (b"sub/deep", b"sub", b".."),
            (b"sub", b"sub/deep/a.txt", b"deep/a.txt"),
            (b"sub", b"submarine/a.txt", b"../submarine/a.txt"),
        ];
        for &(root, target, expected) in cases {
            assert_eq!(
                portable_separators(relative(root, target)),
                expected,
                "relative({root:?}, {target:?})"
            );
        }

        // On Windows the root includes its drive or UNC volume; it is not one separator byte.
        let cwd = std::env::current_dir().unwrap();
        let volume = cwd.ancestors().last().unwrap();
        let root = sys::os_bytes(volume.as_os_str());
        let child = sys::os_bytes(volume.join("alpha/beta").as_os_str());
        assert_eq!(portable_separators(relative(&root, &child)), b"alpha/beta");
        assert_eq!(portable_separators(relative(&child, &root)), b"../..");
        assert_eq!(relative(&root, &root), b".");

        // Rejoining a relative result must reach the exact target, even for sibling prefixes.
        let suffixes = [
            "",
            "a",
            "ab",
            "a/b",
            "a/b/c",
            "ab/c",
            "caf\u{e9}",
            "a/../ab",
        ];
        for from in suffixes {
            for to in suffixes {
                let from = sys::os_bytes(volume.join(from).as_os_str());
                let to = sys::os_bytes(volume.join(to).as_os_str());
                assert_eq!(
                    path::clean(&path::join(&from, &relative(&from, &to))),
                    path::clean(&to),
                    "round trip {from:?} -> {to:?}"
                );
            }
        }
    }

    #[test]
    fn glob_relative_roots_match_the_same_files_as_absolute_roots() {
        const CHILD: &str = "MANUSCRIPT_FS_GLOB_RELATIVE_ROOT_CHILD";
        if std::env::var_os(CHILD).is_none() {
            let root = ops::temporary_directory(b"msfs-glob-relative-").unwrap();
            ops::create_directory(&path::join(&root, b"src/deep"), true).unwrap();
            for name in [
                "a.txt",
                "caf\u{e9}.txt",
                "peer.txt",
                "src/b.txt",
                "src/deep/c.txt",
            ] {
                ops::write_file(&path::join(&root, name.as_bytes()), b"file", false).unwrap();
            }
            let child = std::process::Command::new(std::env::current_exe().unwrap())
                .args([
                    "--exact",
                    "walk::tests::glob_relative_roots_match_the_same_files_as_absolute_roots",
                    "--nocapture",
                ])
                .env(CHILD, "1")
                .current_dir(sys::path_of(&root))
                .output()
                .unwrap();
            ops::remove(&root, true).unwrap();
            assert!(
                child.status.success(),
                "glob child failed:\n{}\n{}",
                String::from_utf8_lossy(&child.stdout),
                String::from_utf8_lossy(&child.stderr)
            );
            return;
        }

        let all: [&[u8]; 1] = [b"**/*.txt"];
        let o = GlobOptions {
            patterns: &all,
            exclude: &[],
            follow_links: false,
            max_entries: UNLIMITED,
            max_results: UNLIMITED,
        };
        let cwd = sys::getcwd().unwrap();
        let expected = [
            "a.txt",
            "caf\u{e9}.txt",
            "peer.txt",
            "src/b.txt",
            "src/deep/c.txt",
        ];
        assert_eq!(texts(glob(b".", b"**/*.txt", UNLIMITED).unwrap()), expected);

        let patterns: &[&[&[u8]]] = &[
            &[b"*"],
            &[b"*.txt"],
            &[b"**/*.txt"],
            &[b"src/**/*.txt"],
            &[b"{a,peer}.txt"],
            &[b"a.txt", b"src/**"],
        ];
        let excludes: &[&[&[u8]]] = &[&[], &[b"**/deep/**"], &[b"a.txt"]];
        for root in [
            b".".as_slice(),
            b"./",
            b"src/..",
            b"src",
            b"./src",
            b"src/deep",
        ] {
            let absolute = ops::absolute(root);
            for &patterns in patterns {
                for &exclude in excludes {
                    let options = GlobOptions {
                        patterns,
                        exclude,
                        ..o
                    };
                    let paths = |entries: Vec<PathEntry>| {
                        entries
                            .into_iter()
                            .map(|e| (e.path, e.name, e.directory))
                            .collect::<Vec<_>>()
                    };
                    assert_eq!(
                        paths(glob_entries(root, &options, None).unwrap()),
                        paths(glob_entries(&absolute, &options, None).unwrap()),
                        "root {root:?}, patterns {patterns:?}, excludes {exclude:?}"
                    );
                }
            }
        }

        assert_eq!(
            texts(glob(b"src", b"../*.txt", UNLIMITED).unwrap()),
            ["../a.txt", "../caf\u{e9}.txt", "../peer.txt"]
        );

        let absolute_src = path::join(&cwd, b"src");
        assert_eq!(
            texts(glob(&absolute_src, b"../*.txt", UNLIMITED).unwrap()),
            ["../a.txt", "../caf\u{e9}.txt", "../peer.txt"]
        );
        assert_eq!(
            glob_entries(b"", &o, None).unwrap_err().status,
            ms_rt_abi::STATUS_INVALID_INPUT
        );
        let bounded = GlobOptions {
            max_results: 1,
            ..o
        };
        assert_eq!(
            glob_entries(b".", &bounded, None).unwrap_err().status,
            STATUS_LIMIT_EXCEEDED
        );
        let bounded = GlobOptions {
            max_entries: 1,
            ..o
        };
        assert_eq!(
            glob_entries(b".", &bounded, None).unwrap_err().status,
            STATUS_LIMIT_EXCEEDED
        );

        let exclude: [&[u8]; 1] = [b"src/**"];
        let filtered = GlobOptions {
            exclude: &exclude,
            ..o
        };
        let mut seen: Vec<Vec<u8>> = Vec::new();
        let mut skip_a = |e: &PathEntry| {
            seen.push(e.path.clone());
            e.path == b"a.txt"
        };
        let found = glob_entries(b".", &filtered, Some(&mut skip_a)).unwrap();
        assert_eq!(
            found
                .iter()
                .map(|e| String::from_utf8_lossy(&e.path).into_owned())
                .collect::<Vec<_>>(),
            ["caf\u{e9}.txt", "peer.txt"]
        );
        assert!(seen.contains(&b"a.txt".to_vec()));
        assert!(!seen.iter().any(|p| p.starts_with(b"src/")));
    }

    fn tree() -> Vec<u8> {
        let root = ops::temporary_directory(b"msfs-walk-").unwrap();
        for d in ["sub", "sub/deep"] {
            ops::create_directory(&path::join(&root, d.as_bytes()), false).unwrap();
        }
        for (f, data) in [
            ("a.txt", "aa"),
            ("b.md", "b"),
            (".hidden.txt", ""),
            ("sub/c.txt", "ccc"),
            ("sub/deep/d.txt", "d"),
        ] {
            ops::write_file(&path::join(&root, f.as_bytes()), data.as_bytes(), false).unwrap();
        }
        ops::create_link(&path::join(&root, b"link"), b"sub").unwrap();
        root
    }

    fn texts(v: Vec<Vec<u8>>) -> Vec<String> {
        v.into_iter()
            .map(|b| {
                String::from_utf8(b)
                    .unwrap()
                    .replace(std::path::MAIN_SEPARATOR, "/")
            })
            .collect()
    }

    #[test]
    fn glob_queries() {
        let root = tree();
        assert_eq!(
            texts(glob(&root, b"**/*.{txt,md}", UNLIMITED).unwrap()),
            ["a.txt", "b.md", "sub/c.txt", "sub/deep/d.txt"]
        );
        assert_eq!(
            glob(&root, b"**/*.txt", 2).unwrap_err().status,
            STATUS_LIMIT_EXCEEDED
        );
        assert_eq!(
            glob(&root, b"{a.txt,[}", UNLIMITED).unwrap_err().status,
            STATUS_INVALID_INPUT
        );
        assert_eq!(
            texts(glob(&root, b"link/*", UNLIMITED).unwrap()),
            Vec::<String>::new()
        );
        ops::remove(&root, true).unwrap();
    }

    #[test]
    fn copy_tree_and_limits() {
        let root = tree();
        let dest = path::join(&root, b"out");
        assert_eq!(
            copy_tree(
                &path::join(&root, b"sub"),
                &path::join(&root, b"sub/deep/inside"),
                false,
                UNLIMITED,
                UNLIMITED
            )
            .unwrap_err()
            .status,
            STATUS_INVALID_INPUT
        );
        copy_tree(
            &path::join(&root, b"sub"),
            &dest,
            false,
            UNLIMITED,
            UNLIMITED,
        )
        .unwrap();
        assert_eq!(
            ops::read_file(&path::join(&dest, b"deep/d.txt"), UNLIMITED).unwrap(),
            b"d"
        );
        assert_eq!(
            copy_tree(
                &path::join(&root, b"sub"),
                &dest,
                false,
                UNLIMITED,
                UNLIMITED
            )
            .unwrap_err()
            .status,
            STATUS_ALREADY_EXISTS
        );
        copy_tree(
            &path::join(&root, b"sub"),
            &dest,
            true,
            UNLIMITED,
            UNLIMITED,
        )
        .unwrap();
        let dest2 = path::join(&root, b"out2");
        assert_eq!(
            copy_tree(&path::join(&root, b"sub"), &dest2, false, 2, UNLIMITED)
                .unwrap_err()
                .status,
            STATUS_LIMIT_EXCEEDED
        );
        let dest3 = path::join(&root, b"out3");
        assert_eq!(
            copy_tree(&path::join(&root, b"sub"), &dest3, false, UNLIMITED, 3)
                .unwrap_err()
                .status,
            STATUS_LIMIT_EXCEEDED
        );
        ops::remove(&root, true).unwrap();
    }

    fn options() -> CopyOptions {
        CopyOptions {
            recursive: true,
            replace: false,
            error_on_exists: false,
            dereference: false,
            preserve: false,
            verbatim: false,
            clone: Clone::None,
            entries: UNLIMITED,
            bytes: UNLIMITED,
        }
    }

    #[test]
    fn copy_rejects_existing_directories_before_copying_children() {
        let root = ops::temporary_directory(b"msfs-copy-existing-").unwrap();
        let source = path::join(&root, b"source");
        let dest = path::join(&root, b"dest");
        ops::create_directory(&source, false).unwrap();
        ops::create_directory(&dest, false).unwrap();

        let exclusive = || CopyOptions {
            error_on_exists: true,
            ..options()
        };
        assert_eq!(
            copy(&source, &dest, exclusive(), None).unwrap_err().status,
            STATUS_ALREADY_EXISTS
        );

        ops::write_file(&path::join(&source, b"new"), b"new", false).unwrap();
        ops::write_file(&path::join(&dest, b"keep"), b"keep", false).unwrap();
        assert_eq!(
            copy(&source, &dest, exclusive(), None).unwrap_err().status,
            STATUS_ALREADY_EXISTS
        );
        assert!(
            ops::list(&dest, UNLIMITED)
                .unwrap()
                .iter()
                .all(|e| e.name == b"keep")
        );
        assert_eq!(
            ops::read_file(&path::join(&dest, b"keep"), UNLIMITED).unwrap(),
            b"keep"
        );

        let mut filter_calls = 0;
        let mut skip_root = |_: &[u8], _: &[u8]| {
            filter_calls += 1;
            false
        };
        copy(&source, &dest, exclusive(), Some(&mut skip_root)).unwrap();
        assert_eq!(filter_calls, 1);

        let mut nonrecursive = exclusive();
        nonrecursive.recursive = false;
        assert_eq!(
            copy(&source, &dest, nonrecursive, None).unwrap_err().status,
            STATUS_INVALID_INPUT
        );

        let mut replacing = exclusive();
        replacing.replace = true;
        copy(&source, &dest, replacing, None).unwrap();
        assert_eq!(
            ops::read_file(&path::join(&dest, b"new"), UNLIMITED).unwrap(),
            b"new"
        );
        assert_eq!(
            ops::read_file(&path::join(&dest, b"keep"), UNLIMITED).unwrap(),
            b"keep"
        );
        copy(&source, &path::join(&root, b"fresh"), exclusive(), None).unwrap();

        ops::write_file(&path::join(&source, b"new"), b"changed", true).unwrap();
        copy(&source, &dest, options(), None).unwrap();
        assert_eq!(
            ops::read_file(&path::join(&dest, b"new"), UNLIMITED).unwrap(),
            b"new"
        );
        ops::remove(&root, true).unwrap();
    }

    #[test]
    fn copy_rewrites_relative_symlink_targets() {
        let root = tree();
        let link = path::join(&root, b"rel");
        sys::symlink(&cpath(b"a.txt").unwrap(), &cpath(&link).unwrap()).unwrap();
        let dest = path::join(&root, b"cp-rel");
        ops::create_directory(&dest, false).unwrap();
        let copy_path = path::join(&dest, b"rel");
        copy(&link, &copy_path, options(), None).unwrap();
        let target = sys::readlink(&cpath(&copy_path).unwrap()).unwrap();
        assert!(path::is_abs(&target));
        assert!(ops::stat(&copy_path, true).is_ok());
        assert!(path::is_abs(&ops::absolute(b"x")));
        ops::remove(&root, true).unwrap();
    }

    #[test]
    fn copy_replaces_a_dangling_destination_link_only_when_asked() {
        let root = tree();
        let dest = path::join(&root, b"dangling");
        sys::symlink(&cpath(b"missing").unwrap(), &cpath(&dest).unwrap()).unwrap();
        let source = path::join(&root, b"a.txt");

        let mut keep = options();
        keep.error_on_exists = true;
        let kept = copy(&source, &dest, keep, None).unwrap_err();
        assert_eq!(kept.status, STATUS_ALREADY_EXISTS);
        assert!(sys::readlink(&cpath(&dest).unwrap()).is_ok());

        let mut replace = options();
        replace.replace = true;
        copy(&source, &dest, replace, None).unwrap();
        assert!(sys::readlink(&cpath(&dest).unwrap()).is_err());
        assert_eq!(
            ops::read_file(&dest, UNLIMITED).unwrap(),
            ops::read_file(&source, UNLIMITED).unwrap()
        );
        ops::remove(&root, true).unwrap();
    }

    #[test]
    fn copy_with_options_and_filter() {
        let root = tree();
        let dest = path::join(&root, b"cp");
        let mut seen: Vec<String> = Vec::new();
        let mut filter = |s: &[u8], _d: &[u8]| {
            seen.push(String::from_utf8_lossy(&path::base(s)).into_owned());
            path::base(s) != b"deep"
        };
        let mut o = options();
        o.preserve = true;
        copy(&path::join(&root, b"sub"), &dest, o, Some(&mut filter)).unwrap();
        assert!(ops::stat(&path::join(&dest, b"c.txt"), true).is_ok());
        assert!(ops::stat(&path::join(&dest, b"deep"), true).is_err());
        assert_eq!(seen.len(), 3);
        let mut again = options();
        again.error_on_exists = true;
        assert_eq!(
            copy(
                &path::join(&root, b"sub/c.txt"),
                &path::join(&dest, b"c.txt"),
                again,
                None
            )
            .unwrap_err()
            .status,
            STATUS_ALREADY_EXISTS
        );
        let mut shallow = options();
        shallow.recursive = false;
        assert_eq!(
            copy(
                &path::join(&root, b"sub"),
                &path::join(&root, b"nr"),
                shallow,
                None
            )
            .unwrap_err()
            .status,
            STATUS_INVALID_INPUT
        );
        let mut cloned = options();
        cloned.clone = Clone::Try;
        copy(
            &path::join(&root, b"a.txt"),
            &path::join(&root, b"a2.txt"),
            cloned,
            None,
        )
        .unwrap();
        assert_eq!(
            ops::read_file(&path::join(&root, b"a2.txt"), UNLIMITED).unwrap(),
            b"aa"
        );
        let mut small = options();
        small.bytes = 1;
        assert_eq!(
            copy(
                &path::join(&root, b"a.txt"),
                &path::join(&root, b"a3.txt"),
                small,
                None
            )
            .unwrap_err()
            .status,
            STATUS_LIMIT_EXCEEDED
        );
        ops::remove(&root, true).unwrap();
    }

    #[test]
    fn glob_entries_queries() {
        let root = tree();
        let patterns: [&[u8]; 1] = [b"*.txt"];
        let exclude: [&[u8]; 1] = [b"sub/**"];
        let o = GlobOptions {
            patterns: &patterns,
            exclude: &exclude,
            follow_links: false,
            max_entries: UNLIMITED,
            max_results: UNLIMITED,
        };
        let got = glob_entries(&root, &o, None).unwrap();
        assert_eq!(
            got.iter()
                .map(|e| String::from_utf8_lossy(&e.path).into_owned())
                .collect::<Vec<_>>(),
            ["a.txt"]
        );
        let mut skip_a = |e: &PathEntry| e.path == b"a.txt";
        assert!(
            glob_entries(&root, &o, Some(&mut skip_a))
                .unwrap()
                .is_empty()
        );
        let all: [&[u8]; 1] = [b"**/*.txt"];
        let wide = GlobOptions {
            patterns: &all,
            exclude: &[],
            follow_links: true,
            max_entries: UNLIMITED,
            max_results: UNLIMITED,
        };
        let got = glob_entries(&root, &wide, None).unwrap();
        let names: Vec<String> = got
            .iter()
            .map(|e| String::from_utf8_lossy(&e.path).replace(std::path::MAIN_SEPARATOR, "/"))
            .collect();
        assert_eq!(
            names,
            [
                "a.txt",
                "link/c.txt",
                "link/deep/d.txt",
                "sub/c.txt",
                "sub/deep/d.txt"
            ]
        );
        let tiny = GlobOptions {
            patterns: &all,
            exclude: &[],
            follow_links: false,
            max_entries: 2,
            max_results: UNLIMITED,
        };
        assert_eq!(
            glob_entries(&root, &tiny, None).unwrap_err().status,
            STATUS_LIMIT_EXCEEDED
        );
        ops::remove(&root, true).unwrap();
    }
}
