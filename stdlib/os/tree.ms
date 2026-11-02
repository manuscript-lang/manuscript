import Bytes from "@std/bytes.ms"
import DirectoryEntry, FileSystemError, list, read_file from "@std/os/fs.ms"

# Read-only file trees you can swap: code that takes a `FileTree` reads the host disk (`host_tree`) or an in-memory
# tree (`MemoryTree`) the same way, so tests need no temporary directories. `walk` visits every entry under a root.
#
# Paths in a tree are `/`-separated and relative to the tree's root. `.` and empty parts are ignored and `..` steps
# up; a path that would leave the root is `InvalidInput`.
#
# ```manuscript
# import FileTree, walk from "@std/os/tree.ms"
#
# fn names(tree: FileTree) List[String]:
#     let found = walk(tree).get(List())
#     return found.map(fn e: e.path.clone())
# ```

# A directory tree whose files can be read and whose directories can be listed.
export interface FileTree:
    # Reads a whole file; more than `max_bytes` bytes returns `LimitExceeded`. A missing path is `NotFound`.
    fn read(path: String, max_bytes: Int?) Bytes!FileSystemError
    # Lists a directory's children, sorted by name. A missing path is `NotFound`, a file is `InvalidInput`.
    fn children(path: String, max_entries: Int?) List[DirectoryEntry]!FileSystemError

# Resolves `path` to its parts under the root. Returns the clean path joined by `/`; the root is the empty string.
fn clean(path: String) String!FileSystemError:
    if path.contains("\u{0}"): return error(FileSystemError.InvalidInput)

    var parts = List[String]()

    for part in path.split("/", none):
        if part == "" or part == ".": continue

        if part == "..":
            if parts.length() == 0: return error(FileSystemError.InvalidInput)

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

fn limited(
    entries: List[DirectoryEntry],
    max_entries: Int?
) List[DirectoryEntry]!FileSystemError:
    if max_entries.is_some() and max_entries.get() < 0: return error(
        FileSystemError.InvalidInput
    )
    if max_entries.is_some() and entries.length() > max_entries.get(): return error(
        FileSystemError.LimitExceeded
    )

    return ok(entries)

# The host filesystem below `root`, read through the `FileTree` interface. Paths cannot climb out of `root`.
export type HostTree:
    # Directory that is the tree's root, in the host's spelling.
    root: String

# Returns a tree over the directory `root` of the host filesystem.
export fn host_tree(root: String) HostTree:
    return HostTree(root)

impl FileTree for HostTree:
    # Reads a file below the root from the host disk; failures are the host's `FileSystemError`.
    fn read(path: String, max_bytes: Int?) Bytes!FileSystemError:
        let inside = try clean(path)
        return read_file(child_path(self.root, inside), max_bytes)

    # Lists a directory below the root from the host disk, sorted by name.
    fn children(path: String, max_entries: Int?) List[DirectoryEntry]!FileSystemError:
        let inside = try clean(path)
        let entries = try list(child_path(self.root, inside), max_entries)
        return ok(entries.sorted(by_name))

# A file tree held in memory: build it with `write_file` and `create_directory`, read it through `FileTree`.
export type MemoryTree:
    # File contents by clean path.
    files: Map[String, Bytes]
    # Clean paths of directories; the root is the empty string and always present.
    directories: Set[String]

# Returns an empty in-memory tree holding only its root directory.
export fn memory_tree() MemoryTree:
    var directories = Set[String]()
    directories.add("")
    return MemoryTree(Map[String, Bytes](), directories)

impl MemoryTree:
    # True when `path` names a file or directory.
    fn exists(path: String) Bool:
        let inside = clean(path)
        if inside.is_error(): return false

        let key = inside.get()
        return self.files.contains(key) or self.directories.contains(key)

    # Creates `path` and any missing parent directories. An existing directory is fine; an existing file is `AlreadyExists`.
    var fn create_directory(path: String) Unit!FileSystemError:
        let inside = try clean(path)
        if self.files.contains(inside): return error(FileSystemError.AlreadyExists)

        var at = inside.clone()

        while not self.directories.contains(at):
            self.directories.add(at.clone())
            at = parent_of(at)

        return ok(unit)

    # Writes a file, replacing any earlier content and creating missing parent directories.
    # A path that is a directory, or whose parent is a file, is `InvalidInput`; the root cannot be written.
    var fn write_file(path: String, data: Bytes) Unit!FileSystemError:
        let inside = try clean(path)
        if inside == "" or self.directories.contains(inside): return error(
            FileSystemError.InvalidInput
        )

        let parent = parent_of(inside)
        if self.files.contains(parent): return error(FileSystemError.InvalidInput)

        try self.create_directory(parent)
        self.files.add(inside.clone(), data)
        return ok(unit)

    # Removes a file or an empty directory; `recursive` removes a directory with everything under it.
    # A missing path is `NotFound`, a non-empty directory without `recursive` is `NotEmpty`, and the root cannot be removed.
    var fn remove(path: String, recursive: Bool = false) Unit!FileSystemError:
        let inside = try clean(path)
        if inside == "": return error(FileSystemError.InvalidInput)

        if self.files.contains(inside):
            self.files.remove(inside)
            return ok(unit)

        if not self.directories.contains(inside): return error(FileSystemError.NotFound)

        let prefix = "{inside}/"
        let below_files = self.files.keys().filter(fn k: k.starts_with(prefix))
        let below_dirs = self.directories.values().filter(fn k: k.starts_with(prefix))
        if not recursive and (below_files.length() + below_dirs.length()) > 0: return error(
            FileSystemError.NotEmpty
        )

        for key in below_files:
            self.files.remove(key)
        for key in below_dirs:
            self.directories.remove(key)
        self.directories.remove(inside)
        return ok(unit)

impl FileTree for MemoryTree:
    # Reads a file held in this tree.
    fn read(path: String, max_bytes: Int?) Bytes!FileSystemError:
        let inside = try clean(path)
        if self.directories.contains(inside): return error(FileSystemError.InvalidInput)

        let found = self.files.get(inside)
        if found.is_none(): return error(FileSystemError.NotFound)
        if max_bytes.is_some() and found.get().length() > max_bytes.get(): return error(
            FileSystemError.LimitExceeded
        )

        return ok(found.get().clone())

    # Lists the files and directories directly under `path`, sorted by name.
    fn children(path: String, max_entries: Int?) List[DirectoryEntry]!FileSystemError:
        let inside = try clean(path)
        if self.files.contains(inside): return error(FileSystemError.InvalidInput)
        if not self.directories.contains(inside): return error(FileSystemError.NotFound)

        var entries = List[DirectoryEntry]()
        for key in self.files.keys():
            if key != "" and parent_of(key) == inside:
                entries.append(DirectoryEntry(name_of(key), false, false))
        for key in self.directories.values():
            if key != "" and parent_of(key) == inside:
                entries.append(DirectoryEntry(name_of(key), true, false))
        return limited(entries.sorted(by_name), max_entries)

# One file or directory found by `walk`.
export type WalkEntry:
    # Path below the walked root, `/`-separated, starting with the walked root's own children.
    path: String
    # True when the entry is a directory (its children follow it).
    directory: Bool

# Lists everything below `root` depth first, a directory before its children and siblings sorted by name.
# Symbolic links on a host tree appear as non-directory entries and are not followed. `max_entries` bounds the
# number of entries found, returning `LimitExceeded` rather than a partial list.
export fn walk(
    tree: FileTree,
    root: String = "",
    max_entries: Int? = none
) List[WalkEntry]!FileSystemError:
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
            FileSystemError.LimitExceeded
        )

        if entry.directory: try push_children(tree, entry.path, var pending)

    return ok(found)

# Lists `directory` and pushes its children onto `pending` in reverse, so popping yields them in name order.
fn push_children(
    tree: FileTree,
    directory: String,
    var pending: List[WalkEntry]
) Unit!FileSystemError:
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
