import Bytes from "@std/bytes.ms"
import DirectoryEntry, list, read_file from "@std/os/fs.ms"
import base64_decode from "@std/data/encoding.ms"

// Read-only file trees you can swap: code that takes a `FileTree` reads the host disk (`host_tree`) or an in-memory
// tree (`MemoryTree`) the same way, so tests need no temporary directories. `walk` visits every entry under a root.
//
// Paths in a tree are `/`-separated and relative to the tree's root. `.` and empty parts are ignored and `..` steps
// up; a path that would leave the root is `InvalidInput`.
//
// ```manuscript
// import FileTree, walk from "@std/os/tree.ms"
//
// fn names(tree: FileTree) List[String]:
//     let found = walk(tree).get(List())
//     return found.map(fn e: e.path.clone())
// ```

// A directory tree whose files can be read and whose directories can be listed.
export interface FileTree:
    // Reads a whole file; more than `max_bytes` bytes returns `LimitExceeded`. A missing path is `NotFound`.
    fn read(path: String, max_bytes: Int?) Bytes!
    // Lists a directory's children, sorted by name. A missing path is `NotFound`, a file is `InvalidInput`.
    fn children(path: String, max_entries: Int?) List[DirectoryEntry]!

// Resolves `path` to its parts under the root. Returns the clean path joined by `/`; the root is the empty string.
fn clean(path: String) String!:
    if path.contains("\u{0}"): return error(
        Error("filesystem: invalid input", kind: ErrorCategory.InvalidInput)
    )

    var parts = List[String]()

    for part in path.split("/", none):
        if part == "" or part == ".": continue

        if part == "..":
            if parts.length() == 0: return error(
                Error(
                    "filesystem: invalid input", kind: ErrorCategory.InvalidInput
                )
            )

            parts.remove(parts.length() - 1)
            continue

        parts.append(part.clone())

    return ok(parts.join("/"))

fn child_path(directory: String, name: String) String:
    if directory == "": return name.clone()

    return "{directory}/{name}"

fn parent_of(path: String) String:
    let parts = path.split("/", none)
    return (parts.slice(0, parts.length() - 1)).get().join("/")

fn name_of(path: String) String:
    let parts = path.split("/", none)
    return parts.get(parts.length() - 1, "").clone()

fn by_name(a: DirectoryEntry, b: DirectoryEntry) Int:
    return a.name.compare(b.name)

fn limited(entries: List[DirectoryEntry], max_entries: Int?) List[DirectoryEntry]!:
    if max_entries.is_some() and max_entries.get() < 0: return error(
        Error("filesystem: invalid input", kind: ErrorCategory.InvalidInput)
    )
    if max_entries.is_some() and entries.length() > max_entries.get(): return error(
        Error("filesystem: limit exceeded", kind: ErrorCategory.LimitExceeded)
    )

    return ok(entries)

// The host filesystem below `root`, read through the `FileTree` interface. Paths cannot climb out of `root`.
export type HostTree:
    // Directory that is the tree's root, in the host's spelling.
    root: String

// Returns a tree over the directory `root` of the host filesystem.
export fn host_tree(root: String) HostTree:
    return HostTree(root)

impl FileTree for HostTree:
    // Reads a file below the root from the host disk; failures are the host's `Error`.
    fn read(path: String, max_bytes: Int?) Bytes!:
        let inside = try clean(path)
        return read_file(child_path(self.root, inside), max_bytes)

    // Lists a directory below the root from the host disk, sorted by name.
    fn children(path: String, max_entries: Int?) List[DirectoryEntry]!:
        let inside = try clean(path)
        let entries = try list(child_path(self.root, inside), max_entries)
        return ok(entries.sorted(by_name))

// A file tree held in memory: build it with `write_file` and `create_directory`, read it through `FileTree`.
export type MemoryTree:
    // File contents by clean path.
    files: Map[String, Bytes]
    // Clean paths of directories; the root is the empty string and always present.
    directories: Set[String]
    // Internal state: clean paths of the entries directly under each directory, so listing is not a scan of the tree.
    kids: Map[String, Set[String]] = Map[String, Set[String]]()

// Returns an empty in-memory tree holding only its root directory.
export fn memory_tree() MemoryTree:
    var directories = Set[String]()
    directories.add("")
    return MemoryTree(Map[String, Bytes](), directories)

impl MemoryTree:
    // Records `path` as a child of its parent directory.
    var fn link(path: String) Unit:
        let parent = parent_of(path)

        if var set = self.kids[parent]?:
            set.add(path.clone())
            return unit

        var fresh = Set[String]()
        fresh.add(path.clone())
        self.kids[parent] = fresh
        return unit

    // Forgets `path` as a child of its parent directory.
    var fn unlink(path: String) Unit:
        if var set = self.kids[parent_of(path)]?:
            set.remove(path)
        return unit

    // True when `path` names a file or directory.
    fn exists(path: String) Bool:
        let inside = clean(path)
        if inside.is_error(): return false

        let key = inside.get()
        return self.files.contains(key) or self.directories.contains(key)

    // Creates `path` and any missing parent directories. An existing directory is fine; an existing file is `AlreadyExists`.
    var fn create_directory(path: String) Unit!:
        let inside = try clean(path)
        if self.files.contains(inside): return error(
            Error(
                "filesystem: already exists", kind: ErrorCategory.AlreadyExists
            )
        )

        var at = inside.clone()

        while not self.directories.contains(at):
            self.directories.add(at.clone())
            if at != "": self.link(at)
            at = parent_of(at)

        return ok(unit)

    // Writes a file, replacing any earlier content and creating missing parent directories.
    // A path that is a directory, or whose parent is a file, is `InvalidInput`; the root cannot be written.
    var fn write_file(path: String, data: Bytes) Unit!:
        let inside = try clean(path)
        if inside == "" or self.directories.contains(inside): return error(
            Error(
                "filesystem: invalid input", kind: ErrorCategory.InvalidInput
            )
        )

        let parent = parent_of(inside)
        if self.files.contains(parent): return error(
            Error(
                "filesystem: invalid input", kind: ErrorCategory.InvalidInput
            )
        )

        try self.create_directory(parent)
        self.files.add(inside.clone(), data)
        self.link(inside.clone())
        return ok(unit)

    // Removes a file or an empty directory; `recursive` removes a directory with everything under it.
    // A missing path is `NotFound`, a non-empty directory without `recursive` is `NotEmpty`, and the root cannot be removed.
    var fn remove(path: String, recursive: Bool = false) Unit!:
        let inside = try clean(path)
        if inside == "": return error(
            Error(
                "filesystem: invalid input", kind: ErrorCategory.InvalidInput
            )
        )

        if self.files.contains(inside):
            self.files.remove(inside.clone())
            self.unlink(inside.clone())
            return ok(unit)

        if not self.directories.contains(inside): return error(
            Error(
                "filesystem: file or directory not found", kind: ErrorCategory.NotFound
            )
        )

        let prefix = "{inside}/"
        let below_files = self.files.keys().filter(fn k: k.starts_with(prefix))
        let below_dirs = self.directories.values().filter(fn k: k.starts_with(prefix))
        if not recursive and (below_files.length() + below_dirs.length()) > 0: return error(
            Error(
                "filesystem: directory not empty", kind: ErrorCategory.Other
            )
        )

        for key in below_files:
            self.files.remove(key.clone())

        for key in below_dirs:
            self.directories.remove(key.clone())
            self.kids.remove(key.clone())

        self.directories.remove(inside.clone())
        self.kids.remove(inside.clone())
        self.unlink(inside.clone())
        return ok(unit)

impl FileTree for MemoryTree:
    // Reads a file held in this tree.
    fn read(path: String, max_bytes: Int?) Bytes!:
        let inside = try clean(path)
        if self.directories.contains(inside): return error(
            Error(
                "filesystem: invalid input", kind: ErrorCategory.InvalidInput
            )
        )

        let found = self.files.get(inside)
        if found.is_none(): return error(
            Error(
                "filesystem: file or directory not found", kind: ErrorCategory.NotFound
            )
        )
        if max_bytes.is_some() and found.get().length() > max_bytes.get(): return error(
            Error(
                "filesystem: limit exceeded", kind: ErrorCategory.LimitExceeded
            )
        )

        return ok(found.get().clone())

    // Lists the files and directories directly under `path`, sorted by name.
    fn children(path: String, max_entries: Int?) List[DirectoryEntry]!:
        let inside = try clean(path)
        if self.files.contains(inside): return error(
            Error(
                "filesystem: invalid input", kind: ErrorCategory.InvalidInput
            )
        )
        if not self.directories.contains(inside): return error(
            Error(
                "filesystem: file or directory not found", kind: ErrorCategory.NotFound
            )
        )

        var entries = List[DirectoryEntry]()
        if let names = self.kids.get(inside):
            for key in names.values():
                entries.append(
                    DirectoryEntry(
                        name_of(key), self.directories.contains(key), false
                    )
                )
        return limited(entries.sorted(by_name), max_entries)

// A read-only tree whose files stay Base64 text until they are read. Generated modules for `[embed]` in
// `ms.toml` build one with `embedded_tree`: making it costs one map entry per file and one index entry per path,
// and `read` decodes only the file asked for.
export type EmbeddedTree:
    // Base64 text of each file, by clean path.
    encoded: Map[String, String]
    // Clean paths of every directory, including the root (the empty string).
    directories: Set[String]
    // Internal state: clean paths directly under each directory, so listing is not a scan of the tree.
    kids: Map[String, List[String]]

// Returns a read-only tree over Base64 file text by clean path and the clean paths of every directory (the root,
// the empty string, included).
export fn embedded_tree(
    encoded: Map[String, String],
    directories: Set[String]
) EmbeddedTree:
    var kids = Map[String, List[String]]()
    for key in encoded.keys():
        index_child(var kids, key)
    for key in directories.values():
        if key != "": index_child(var kids, key)
    return EmbeddedTree(encoded, directories, kids)

fn index_child(var kids: Map[String, List[String]], path: String) Unit:
    let parent = parent_of(path)

    if var names = kids[parent]?:
        names.append(path.clone())
        return unit

    kids[parent] = [path.clone()]
    return unit

impl FileTree for EmbeddedTree:
    // Decodes and returns one file; the other files are not touched.
    fn read(path: String, max_bytes: Int?) Bytes!:
        let inside = try clean(path)
        if self.directories.contains(inside): return error(
            Error(
                "filesystem: invalid input", kind: ErrorCategory.InvalidInput
            )
        )

        let found = self.encoded.get(inside)
        if found.is_none(): return error(
            Error(
                "filesystem: file or directory not found", kind: ErrorCategory.NotFound
            )
        )

        let decoded = base64_decode(found.get(), false, max_bytes)
        if decoded.is_error() and decoded.err().kind == ErrorCategory.LimitExceeded: return error(
            Error(
                "filesystem: limit exceeded", kind: ErrorCategory.LimitExceeded
            )
        )
        if decoded.is_error(): return error(
            Error(
                "filesystem: invalid data", kind: ErrorCategory.InvalidData
            )
        )

        return ok(decoded.get().clone())

    // Lists the files and directories directly under `path`, sorted by name.
    fn children(path: String, max_entries: Int?) List[DirectoryEntry]!:
        let inside = try clean(path)
        if self.encoded.contains(inside): return error(
            Error(
                "filesystem: invalid input", kind: ErrorCategory.InvalidInput
            )
        )
        if not self.directories.contains(inside): return error(
            Error(
                "filesystem: file or directory not found", kind: ErrorCategory.NotFound
            )
        )

        var entries = List[DirectoryEntry]()
        if let names = self.kids.get(inside):
            for key in names:
                entries.append(
                    DirectoryEntry(
                        name_of(key), self.directories.contains(key), false
                    )
                )
        return limited(entries.sorted(by_name), max_entries)

// One file or directory found by `walk`.
export type WalkEntry:
    // Path below the walked root, `/`-separated, starting with the walked root's own children.
    path: String
    // True when the entry is a directory (its children follow it).
    directory: Bool

// Lists everything below `root` depth first, a directory before its children and siblings sorted by name.
// Symbolic links on a host tree appear as non-directory entries and are not followed. `max_entries` bounds the
// number of entries found, returning `LimitExceeded` rather than a partial list.
export fn walk(
    tree: FileTree,
    root: String = "",
    max_entries: Int? = none
) List[WalkEntry]!:
    let start = try clean(root)
    var found = List[WalkEntry]()
    var pending = List[WalkEntry]()
    try push_children(tree, start, var pending)

    while pending.length() > 0:
        let top = pending.length() - 1
        let entry = WalkEntry(pending[top].path.clone(), pending[top].directory)
        pending.remove(top)
        found.append(WalkEntry(relative(entry.path, start), entry.directory))
        if max_entries.is_some() and found.length() > max_entries.get(): return error(
            Error(
                "filesystem: limit exceeded", kind: ErrorCategory.LimitExceeded
            )
        )

        if entry.directory: try push_children(tree, entry.path, var pending)

    return ok(found)

// Lists `directory` and pushes its children onto `pending` in reverse, so popping yields them in name order.
fn push_children(tree: FileTree, directory: String, var pending: List[WalkEntry]) Unit!:
    let children = try tree.children(directory, none)
    var i = children.length()

    while i > 0:
        i -= 1

        let child = children[i]
        pending.append(
            WalkEntry(
                child_path(directory, child.name), child.directory and not child.symlink
            )
        )

    return ok(unit)

fn relative(path: String, start: String) String:
    if start == "": return path.clone()

    return path.slice(start.length() + 1, path.length()).get().clone()
