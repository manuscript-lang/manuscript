// ms: allow_effect std.fs.read

import (
	Bytes from "@std/bytes.ms",
	DirectoryEntry, canonicalize, list, read_file from "@std/os/fs.ms",
)

/*
Read-only file trees you can swap: code that takes a `FileTree` reads the host disk (`host_tree`) or an in-memory
tree (`MemoryTree`) the same way, so tests need no temporary directories. `walk` visits every entry under a root.

Paths in a tree are `/`-separated and relative to the tree's root. `.` and empty parts are ignored and `..` steps
up; a path that would leave the root is `EINVAL`.

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
import FileTree, walk from "@std/os/tree.ms"

fn names(tree FileTree) List[String] {
    found := walk(tree).get_or(List())
    return found.map(e => e.path.clone())
}
```
*/

// Read files and list directories through one interface: use `host_tree(root)` for disk
// files or `memory_tree()` to supply test data without temporary files.
export interface FileTree {
	// Reads a whole file; more than `max_bytes` bytes returns `EOVERFLOW`. A missing
	// path is `ENOENT`.
	fn read(path String, max_bytes Int?) Bytes!
	// Lists a directory's children, sorted by name. A missing path is `ENOENT`, a file
	// is `EINVAL`, and more than `max_entries` children (when given) is `EOVERFLOW`.
	fn children(path String, max_entries Int?) List[DirectoryEntry]!
}

// Normalizes `path` to a clean path under the root: its parts joined by `/`, with the
// root as the empty string. A NUL byte or a `..` that would leave the root is `EINVAL`.
fn clean(path String) String! {
	if path.contains(
		"\u{0}"
	) { return error(fs_invalid_input()) }

	var parts = List[String]()

	for part in path.split("/") {
		if part == "" or part == "." { continue }

		if part == ".." {
			if parts.is_empty() { return error(fs_invalid_input()) }

			parts.remove(parts.length() - 1)
			continue
		}

		parts.append(part.clone())
	}

	return ok(parts.join("/"))
}

fn child_path(directory, name String) String {
	if directory == "" { return name.clone() }
	return f"{directory}/{name}"
}

fn parent_of(path String) String {
	parts := path.split("/").collect()
	return (parts.slice(0, parts.length() - 1)).get().join("/")
}

fn name_of(path String) String {
	parts := path.split("/").collect()
	return parts.get_or(parts.length() - 1, "").clone()
}

fn by_name(a, b DirectoryEntry) Int {
	return a.name.compare(b.name)
}

fn limited(move entries List[DirectoryEntry], max_entries Int?) List[DirectoryEntry]! {
	if (max_entries != null) and max_entries < 0 { return error(fs_invalid_input()) }
	if (max_entries != null) and entries.length() > max_entries {
		return error(Error("filesystem: limit exceeded", kind: "EOVERFLOW"))
	}

	return ok(entries)
}

// True when the resolved `target` is the resolved `root` or below it.
fn below(root, target String) Bool {
	if target == root { return true }
	if not target.starts_with(root) { return false }

	rest := target.view(root.length(), target.length())
	return (
		root.ends_with("/")
		or root.ends_with("\\")
		or rest.starts_with("/")
		or rest.starts_with("\\")
	)
}

// The host filesystem below `root`, read through the `FileTree` interface. A path
// cannot climb out of `root`, and a symbolic link that leads outside it is `EINVAL`;
// links that stay inside are followed.
export type HostTree {
	// Directory that is the tree's root, in the host's spelling.
	root String
}

// Checks that `full`, once its symbolic links are resolved, is inside the root. A path
// that does not resolve is left to the read or listing, which reports why.
fn HostTree.confine(full String) Void! {
	real := canonicalize(full)
	if real.is_error() { return ok() }

	root := canonicalize(self.root)?
	if not below(root, real.get()) { return error(fs_invalid_input()) }

	return ok()
}

// Reads a file below the root from the host disk; failures are the host's `Error`.
fn HostTree.read(path String, max_bytes Int?) Bytes! {
	inside := clean(path)?
	full := child_path(self.root, inside)
	self.confine(full)?
	return read_file(full, max_bytes).wait()
}

// Lists a directory below the root from the host disk, sorted by name.
fn HostTree.children(path String, max_entries Int?) List[DirectoryEntry]! {
	inside := clean(path)?
	full := child_path(self.root, inside)
	self.confine(full)?

	entries := list(full, max_entries)?
	return ok(entries.sorted(by_name).clone())
}

// Returns a tree over the directory `root` of the host filesystem.
export fn host_tree(root String) HostTree {
	return HostTree(root.clone())
}

// A file tree held in memory: build it with `write_file` and `create_directory`, change
// it with `remove`, and read it through `FileTree`.
export type MemoryTree {
	// File contents by clean path.
	files Map[String, Bytes]
	// Clean paths of directories; the root is the empty string and always present.
	directories Set[String]
	// Internal state: clean paths of the entries directly under each directory, so
	// listing is not a scan of the tree.
	kids Map[String, Set[String]] = Map[String, Set[String]]()
}

// Records `path` as a child of its parent directory.
fn var MemoryTree.link(path String) Void {
	parent := parent_of(path)

	if var set = self.kids[parent]? {
		set.add(path.clone())
		return
	}

	var fresh = Set[String]()
	fresh.add(path.clone())
	self.kids[parent] = fresh
	return
}

// Forgets `path` as a child of its parent directory.
fn var MemoryTree.unlink(path String) Void {
	if var set = self.kids[parent_of(path)]? {
		set.remove(path.clone())
	}
	return
}

// True when `path` names a file or directory.
fn MemoryTree.exists(path String) Bool {
	inside := clean(path)
	if inside.is_error() { return false }

	key := inside.get()
	return self.files.contains(key) or self.directories.contains(key)
}

// Creates `path` and any missing parent directories. An existing directory is fine; an
// existing file is `EEXIST`, and a file where a parent directory should be is `EINVAL`.
fn var MemoryTree.create_directory(path String) Void! {
	inside := clean(path)?
	if self.files.contains(
		inside
	) { return error(Error("filesystem: already exists", kind: "EEXIST")) }

	var at = parent_of(inside)

	while not self.directories.contains(at) {
		if self.files.contains(
			at
		) { return error(fs_invalid_input()) }

		at = parent_of(at)
	}

	at = inside.clone()

	while not self.directories.contains(at) {
		self.directories.add(at.clone())
		if at != "" { self.link(at) }
		at = parent_of(at)
	}
}

// Writes a file, replacing any earlier content and creating missing parent directories.
// A path that is a directory, or that has a file for an ancestor, is `EINVAL`; the root
// cannot be written.
fn var MemoryTree.write_file(path String, data Bytes) Void! {
	inside := clean(path)?
	if inside == "" or self.directories.contains(
		inside
	) { return error(fs_invalid_input()) }

	parent := parent_of(inside)
	if self.files.contains(
		parent
	) { return error(fs_invalid_input()) }

	self.create_directory(parent)?
	self.files.add(inside.clone(), data.clone())
	self.link(inside.clone())
}

// Removes a file or an empty directory; `recursive` removes a directory with
// everything under it. A missing path is `ENOENT`, a non-empty directory without
// `recursive` is `ENOTEMPTY`, and the root cannot be removed.
fn var MemoryTree.remove(path String, recursive Bool = false) Void! {
	inside := clean(path)?
	if inside == "" { return error(fs_invalid_input()) }

	if self.files.contains(inside) {
		self.files.remove(inside.clone())
		self.unlink(inside.clone())
		return ok()
	}

	if not self.directories.contains(
		inside
	) { return error(Error("filesystem: file or directory not found", kind: "ENOENT")) }

	prefix := f"{inside}/"
	below_files := self.files.keys().filter(k => k.starts_with(prefix)).clone()
	below_dirs := self.directories.values().filter(k => k.starts_with(prefix)).clone()
	if not recursive and (below_files.length() + below_dirs.length()) > 0 {
		return error(Error("filesystem: directory not empty", kind: "ENOTEMPTY"))
	}

	for key in below_files {
		self.files.remove(key.clone())
	}

	for key in below_dirs {
		self.directories.remove(key.clone())
		self.kids.remove(key.clone())
	}

	self.directories.remove(inside.clone())
	self.kids.remove(inside.clone())
	self.unlink(inside.clone())
}

// Reads a file held in this tree.
fn MemoryTree.read(path String, max_bytes Int?) Bytes! {
	inside := clean(path)?
	if self.directories.contains(
		inside
	) { return error(fs_invalid_input()) }

	found := self.files.get(inside)
	if found == null {
		return error(Error("filesystem: file or directory not found", kind: "ENOENT"))
	}
	if (max_bytes != null) and found.length() > max_bytes {
		return error(Error("filesystem: limit exceeded", kind: "EOVERFLOW"))
	}

	return ok(found.clone())
}

// Lists the files and directories directly under `path`, sorted by name.
fn MemoryTree.children(path String, max_entries Int?) List[DirectoryEntry]! {
	inside := clean(path)?
	if self.files.contains(
		inside
	) { return error(fs_invalid_input()) }
	if not self.directories.contains(
		inside
	) { return error(Error("filesystem: file or directory not found", kind: "ENOENT")) }

	var entries = List[DirectoryEntry]()
	names := self.kids.get(inside)
	if names != null {
		for key in names.values() {
			entries.append(
				DirectoryEntry(
					name_of(key),
					self.directories.contains(key),
					false,
				)
			)
		}
	}
	return limited(entries.sorted(by_name), max_entries)
}

// Returns an empty in-memory tree holding only its root directory.
export fn memory_tree() MemoryTree {
	var directories = Set[String]()
	directories.add("")
	return MemoryTree(Map[String, Bytes](), directories)
}

/*
Bytes held in the program's read-only data. `[embed]` modules call this with the Base64 text of a file as a
string literal; the compiler decodes the text when it builds the program, so the running program holds the raw bytes
and a read decodes nothing. The argument must be a string literal.
*/
export extern fn msstd_embed_bytes(encoded String) Bytes

/*
A read-only tree over files held in the program. Generated modules for `[embed]` in `ms.toml` build one with
`embedded_tree`: making it costs one map entry per file and one index entry per path, and `read` copies only the
file asked for.
*/
export type EmbeddedTree {
	// The number each file is loaded by, by clean path.
	indexes Map[String, Int]
	// Clean paths of every directory, including the root (the empty string).
	directories Set[String]
	// Internal state: clean paths directly under each directory, so listing is not a
	// scan of the tree.
	kids Map[String, List[String]]
	// Returns the bytes of the file with that number.
	load fn(Int) Bytes
}

// Returns a copy of one file; the other files are not touched.
fn EmbeddedTree.read(path String, max_bytes Int?) Bytes! {
	inside := clean(path)?
	if self.directories.contains(
		inside
	) { return error(fs_invalid_input()) }

	found := self.indexes.get(inside)
	if found == null {
		return error(Error("filesystem: file or directory not found", kind: "ENOENT"))
	}

	load := self.load
	data := load(found)
	if (max_bytes != null) and data.length() > max_bytes {
		return error(Error("filesystem: limit exceeded", kind: "EOVERFLOW"))
	}

	return ok(data)
}

// Lists the files and directories directly under `path`, sorted by name.
fn EmbeddedTree.children(path String, max_entries Int?) List[DirectoryEntry]! {
	inside := clean(path)?
	if self.indexes.contains(
		inside
	) { return error(fs_invalid_input()) }
	if not self.directories.contains(
		inside
	) { return error(Error("filesystem: file or directory not found", kind: "ENOENT")) }

	var entries = List[DirectoryEntry]()
	names := self.kids.get(inside)
	if names != null {
		for key in names {
			entries.append(
				DirectoryEntry(
					name_of(key),
					self.directories.contains(key),
					false,
				)
			)
		}
	}
	return limited(entries.sorted(by_name), max_entries)
}

// Returns a read-only tree over file numbers by clean path, the clean paths of every
// directory (the root, the empty string, included) and the function that returns the
// bytes of a file number.
export fn embedded_tree(
	move indexes Map[String, Int],
	move directories Set[String],
	load fn(Int) Bytes
) EmbeddedTree {
	var kids = Map[String, List[String]]()
	for key in indexes.keys() {
		index_child(kids, key)
	}
	for key in directories.values() {
		if key != "" { index_child(kids, key) }
	}
	return EmbeddedTree(indexes, directories, kids, load)
}

fn index_child(var kids Map[String, List[String]], path String) Void {
	parent := parent_of(path)

	if var names = kids[parent]? {
		names.append(path.clone())
		return
	}

	kids[parent] = [path.clone()]
	return
}

// One file or directory found by `walk`.
export type WalkEntry {
	// Path relative to the walked root, `/`-separated.
	path String
	// True when the entry is a directory (its children follow it).
	directory Bool
}

/*
Lists everything below `root` depth first, a directory before its children and siblings sorted by name.
Symbolic links on a host tree appear as non-directory entries and are not followed. `max_entries` bounds the
number of entries found, returning `EOVERFLOW` rather than a partial list.
*/
export fn walk(
	tree FileTree,
	root String = "",
	max_entries Int? = null,
) List[WalkEntry]! {
	start := clean(root)?
	var found = List[WalkEntry]()
	var pending = List[WalkEntry]()
	push_children(tree, start, pending)?

	while not pending.is_empty() {
		top := pending.length() - 1
		entry := WalkEntry(pending[top].path.clone(), pending[top].directory)
		pending.remove(top)
		found.append(WalkEntry(relative(entry.path, start), entry.directory))
		if (max_entries != null) and found.length() > max_entries {
			return error(Error("filesystem: limit exceeded", kind: "EOVERFLOW"))
		}

		if entry.directory { push_children(tree, entry.path, pending)? }
	}

	return ok(found)
}

// Lists `directory` and pushes its children onto `pending` in reverse, so popping
// yields them in name order.
fn push_children(tree FileTree, directory String, var pending List[WalkEntry]) Void! {
	children := tree.children(directory, null)?
	var i = children.length()

	while i > 0 {
		i -= 1

		child := children[i]
		pending.append(
			WalkEntry(
				child_path(directory, child.name),
				child.directory and not child.symlink,
			)
		)
	}
}

fn relative(path, start String) String {
	if start == "" { return path.clone() }
	return path.slice(start.length() + 1, path.length()).clone()
}

fn fs_invalid_input() Error {
	return Error("filesystem: invalid input", kind: "EINVAL")
}
