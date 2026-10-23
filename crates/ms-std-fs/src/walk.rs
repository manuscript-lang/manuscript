//! Tree operations: glob queries, `copy_tree` and `copy`.
use crate::err::{Fail, Res};
use crate::ops;
use crate::path;
use crate::sys::{self, CPath};
use alloc::string::String;
use alloc::vec::Vec;
use ms_rt_abi::{STATUS_ALREADY_EXISTS, STATUS_LIMIT_EXCEEDED, STATUS_UNSUPPORTED};
use ms_std_path::glob::Glob;
use ms_std_rt::poll_cancel;

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

/// `filepath.WalkDir` without following links: `visit(path, relative, is_dir)` runs on the root
/// first, then each directory's children in name order. `relative` is `.` for the root.
type Visit<'a> = dyn FnMut(&[u8], &[u8], bool) -> Res<()> + 'a;

fn walk_dir(root: &[u8], visit: &mut Visit) -> Res<()> {
    let st = lstat(root)?;
    walk(root, b".", is_dir(&st), visit)
}

fn walk(p: &[u8], rel: &[u8], dir: bool, visit: &mut Visit) -> Res<()> {
    poll_cancel();
    visit(p, rel, dir)?;
    if !dir {
        return Ok(());
    }
    let mut entries = read_dir(p)?;
    entries.sort_by(|a, b| a.0.cmp(&b.0));
    for (name, kind) in entries {
        let child = path::join(p, &name);
        // Relative paths use `/` on every host, as glob patterns do.
        let child_rel = if rel == b"." {
            name.clone()
        } else {
            [rel, b"/", &name].concat()
        };
        let (directory, _) = ops::entry_kind(p, &name, kind);
        walk(&child, &child_rel, directory, visit)?;
    }
    Ok(())
}

fn utf8(b: &[u8]) -> Res<&str> {
    core::str::from_utf8(b).map_err(|_| Fail::status(STATUS_UNSUPPORTED))
}

/// `glob`: the sorted relative paths under `root` matching `pattern`.
pub fn glob(root: &[u8], pattern: &[u8], max: i64) -> Res<Vec<Vec<u8>>> {
    let compiled = core::str::from_utf8(pattern)
        .ok()
        .and_then(Glob::new)
        .ok_or_else(Fail::invalid)?;
    let mut items: Vec<Vec<u8>> = Vec::new();
    walk_dir(root, &mut |_, rel, _| {
        if rel == b"." {
            return Ok(());
        }
        let text = utf8(rel)?;
        if compiled.matches(text) {
            if items.len() as i64 >= max {
                return Err(limit_exceeded());
            }
            items.push(rel.to_vec());
        }
        Ok(())
    })?;
    items.sort();
    Ok(items)
}

// ---------------------------------------------------------------------------
// copy_tree
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
    let mut real = ops::eval_symlinks(&ancestor).map_err(|e| Fail::errno(e, "lstat", &ancestor))?;
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
        poll_cancel();
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

/// `copy_tree`: copies a tree without following source links; refuses to copy into itself.
pub fn copy_tree(
    source: &[u8],
    destination: &[u8],
    replace: bool,
    entries: i64,
    bytes: i64,
) -> Res<()> {
    if entries < 0 || bytes < 0 {
        return Err(Fail::invalid());
    }
    let real = ops::eval_symlinks(source).map_err(|e| Fail::errno(e, "lstat", source))?;
    let resolved = resolve_destination(destination)?;
    if within_path(&real, &resolved) {
        return Err(Fail::invalid());
    }
    let (mut entries, mut bytes) = (entries, bytes);
    copy_tree_at(source, destination, replace, &mut entries, &mut bytes)
}

fn copy_tree_at(
    source: &[u8],
    dest: &[u8],
    replace: bool,
    entries: &mut i64,
    bytes: &mut i64,
) -> Res<()> {
    poll_cancel();
    if *entries == 0 {
        return Err(limit_exceeded());
    }
    *entries -= 1;
    let info = lstat(source)?;
    match sys::stat(&cpath(dest)?, false) {
        Ok(old) => {
            if same_file(&info, &old) {
                return Err(Fail::failed("source and destination are the same file"));
            }
            if !replace {
                return Err(Fail::status(STATUS_ALREADY_EXISTS));
            }
        }
        Err(e) if sys::is_not_found(e) => {}
        Err(e) => return Err(Fail::errno(e, "lstat", dest)),
    }
    let perm = info.mode & 0o777;
    if is_link(&info) {
        let target =
            sys::readlink(&cpath(source)?).map_err(|e| Fail::errno(e, "readlink", source))?;
        if replace {
            remove_ignoring_missing(dest)?;
        }
        return sys::symlink(&cpath(&target)?, &cpath(dest)?)
            .map_err(|e| Fail::errno_paths(e, "symlink", &[&target, dest]));
    }
    if is_dir(&info) {
        if let Ok(old) = sys::stat(&cpath(dest)?, false)
            && !is_dir(&old)
        {
            return Err(Fail::failed("destination is not a directory"));
        }
        match sys::mkdir(&cpath(dest)?, perm as u32) {
            Ok(()) => {}
            Err(e) if sys::is_exists(e) => {}
            Err(e) => return Err(Fail::errno(e, "mkdir", dest)),
        }
        for (name, _) in read_dir(source)? {
            copy_tree_at(
                &path::join(source, &name),
                &path::join(dest, &name),
                replace,
                entries,
                bytes,
            )?;
        }
        return Ok(());
    }
    if !is_regular(&info) {
        return Err(Fail::failed(
            "copy_tree requires regular files, directories, or symlinks",
        ));
    }
    let input =
        sys::open(&cpath(source)?, sys::O_RDONLY, 0).map_err(|e| Fail::errno(e, "open", source))?;
    let result = (|| {
        if replace {
            remove_ignoring_missing(dest)?;
        }
        let output = open_out(dest, perm as u32)?;
        let copied = copy_stream(input, output, dest, bytes);
        let closed = sys::close(output).map_err(|e| Fail::errno(e, "close", dest));
        copied.and(closed)
    })();
    let _ = sys::close(input);
    result
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
        poll_cancel();
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
                target = path::join(&path::dir(source), &target);
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
    let mut exclude = exclude;
    let mut state = GlobState {
        remaining: o.max_entries,
        items: alloc::collections::BTreeMap::new(),
        ancestors: Vec::new(),
    };

    // Relative parent and absolute patterns can start outside the root, as in Node.
    let mut roots: Vec<Vec<u8>> = alloc::vec![root.to_vec()];
    for pattern in o.patterns {
        let mut base = root.to_vec();
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
        match state.visit(&start, root, &patterns, &excluded, o, &mut exclude) {
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
        poll_cancel();
        if self.remaining == 0 {
            return Err(limit_exceeded());
        }
        self.remaining -= 1;
        let mut info = lstat(p)?;
        let rel = relative(root, p);
        let name = path::base(p);
        if core::str::from_utf8(&rel).is_err() || core::str::from_utf8(&name).is_err() {
            return Err(Fail::status(STATUS_UNSUPPORTED));
        }
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
                Err(e) if sys::is_not_found(e) => return Ok(()),
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
fn relative(root: &[u8], p: &[u8]) -> Vec<u8> {
    let root = path::clean(root);
    let p = path::clean(p);
    if p == root {
        return alloc::vec![b'.'];
    }
    if within_path(&root, &p) {
        let skip = if root == b"/" { 1 } else { root.len() + 1 };
        return p[skip..].to_vec();
    }
    // Climb out of `root` for entries beyond it.
    let mut ups: Vec<u8> = Vec::new();
    let mut base = root.clone();
    while !within_path(&base, &p) {
        if !ups.is_empty() {
            ups.push(b'/');
        }
        ups.extend_from_slice(b"..");
        let parent = path::dir(&base);
        if parent == base {
            break;
        }
        base = parent;
    }
    let skip = if base == b"/" { 1 } else { base.len() + 1 };
    if p.len() > skip {
        ups.push(b'/');
        ups.extend_from_slice(&p[skip..]);
    }
    ups
}

#[cfg(test)]
mod tests {
    use super::*;
    use alloc::string::String;
    use ms_rt_abi::STATUS_INVALID_INPUT;

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
