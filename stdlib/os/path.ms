/*
Lexical path text: no function here touches the filesystem.

Every function exists twice: the module-level one follows the host's rules (backslash and drive roots on Windows, slash elsewhere), and `posix()` / `win32()` return the same operations for one chosen dialect, so a program can handle either spelling on any host.

```manuscript
import join, basename from "@std/os/path.ms"

let config = join(["/etc", "app", "main.toml"])
let name = basename(config)
```
*/
import msstd_path_matches_glob from "@std/internal/path.ms"
import Os, os from "@std/os/system.ms"

// Parsed path components using the familiar root, directory, base, extension, and name fields.
export type PathParts:
    // Root prefix under the chosen path rules, including a POSIX slash or Windows drive/UNC root.
    root: String
    // Directory portion, including the root when present; it takes precedence over root during format.
    directory: String
    // Final component with extension; it takes precedence over name/extension during format.
    base: String
    // Final extension including its dot; simple dotfiles and dot/dot-dot components have no extension.
    extension: String
    // Final component with its extension removed, retaining the original spelling.
    name: String

// Path operations using either POSIX or Windows path conventions.
export interface PathOperations:
    // Returns the last component after ignoring trailing separators under this view's path rules.
    fn basename(path: String) String
    // Removes an exact suffix under basename compatibility rules; it does not strip arbitrary extensions.
    fn basename_without(path: String, suffix: String) String
    // Returns the directory component using the selected POSIX or Windows convention.
    fn dirname(path: String) String
    // Returns the final dot extension, or empty text for extensionless names and simple dotfiles.
    fn extension(path: String) String
    // Tests absolute-root syntax; a Windows drive-relative spelling is not absolute.
    fn is_absolute(path: String) Bool
    // Joins nonempty parts and normalizes separators/dot segments without filesystem access.
    fn join(parts: List[String]) String
    // Cleans repeated separators and dot segments lexically; it does not resolve symlinks.
    fn normalize(path: String) String
    // Computes a lexical relative path from absolute anchors; different roots return the original target.
    // Nonabsolute anchors or invalid NUL input return EINVAL.
    fn relative(base: String, target: String) String!
    // Resolves parts against an explicit absolute base; no process working directory is consulted.
    fn resolve(base: String, parts: List[String]) String!
    // Splits the original spelling into root, directory, base, extension and name without filesystem access.
    fn parse(path: String) PathParts
    // Builds a path with directory preferred over root, and base preferred over name plus extension.
    fn format(parts: PathParts) String
    // Returns slash for POSIX or backslash for Windows path components.
    fn separator() String
    // Returns colon for POSIX or semicolon for Windows path-list entries.
    fn delimiter() String
    // Returns a Windows namespaced absolute path when applicable; POSIX paths are unchanged.
    fn to_namespaced_path(path: String) String
    // Tests one lexical path against the supported glob syntax; malformed patterns return EINVAL.
    fn matches_glob(path: String, pattern: String) Bool!

// One dialect's rules; the interface implementation forwards to the functions below with its flag.
type Dialect:
    windows: Bool

impl PathOperations for Dialect:
    fn basename(path: String) String:
        return basename_in(self.windows, path)

    fn basename_without(path: String, suffix: String) String:
        return basename_without_in(self.windows, path, suffix)

    fn dirname(path: String) String:
        return dirname_in(self.windows, path)

    fn extension(path: String) String:
        return extension_in(self.windows, path)

    fn is_absolute(path: String) Bool:
        return is_absolute_in(self.windows, path)

    fn join(parts: List[String]) String:
        return join_in(self.windows, parts)

    fn normalize(path: String) String:
        return normalize_in(self.windows, path)

    fn relative(base: String, target: String) String!:
        return relative_in(self.windows, base, target)

    fn resolve(base: String, parts: List[String]) String!:
        return resolve_in(self.windows, base, parts)

    fn parse(path: String) PathParts:
        return parse_in(self.windows, path)

    fn format(parts: PathParts) String:
        return format_in(self.windows, parts)

    fn separator() String:
        return if self.windows: "\\" else: "/"

    fn delimiter() String:
        return if self.windows: ";" else: ":"

    fn to_namespaced_path(path: String) String:
        return namespaced_in(self.windows, path)

    fn matches_glob(path: String, pattern: String) Bool!:
        return glob_in(self.windows, path, pattern)

fn host_windows() Bool:
    return os() == Os.Windows

fn invalid_input() Error:
    return Error("path: invalid input", kind: "EINVAL")

fn is_letter(c: String) Bool:
    let code = c.scalar_at(0, none)
    return (code >= 65 and code <= 90) or (code >= 97 and code <= 122)

// The path with every backslash read as a slash under Windows rules; POSIX text is unchanged.
fn slash(windows: Bool, text: String) String:
    if windows: return text.replace("\\", "/")

    return text.clone()

// The path with slashes written as the dialect's separator.
fn native(windows: Bool, text: String) String:
    if windows: return text.replace("/", "\\")

    return text.clone()

// Removes every trailing slash.
fn trim_end_slashes(text: String) String:
    if not text.ends_with("/"): return text.clone()

    var end = text.length()
    while end > 0 and text.get(end - 1, none) == "/": end -= 1
    return text.take(end)

// Removes every leading slash.
fn trim_start_slashes(text: String) String:
    var start = 0
    let count = text.length()
    while start < count and text.get(start, none) == "/": start += 1
    return text.drop(start)

// The root of an already slash-normalized path: a Windows drive or UNC share, `/`, or empty.
fn root_of(windows: Bool, text: String) String:
    if windows:
        let count = text.length()

        if count >= 2 and is_letter(text.get(0, none)) and text.get(1, none) == ":":
            if count > 2 and text.get(2, none) == "/": return text.take(3)

            return text.take(2)

        if text.starts_with("//"):
            let unc = unc_root(text)
            if unc != "": return unc

    if text.starts_with("/"): return "/"

    return ""

// The `//server/share` root of a slash-normalized UNC path, or empty when the text is not one.
fn unc_root(text: String) String:
    let count = text.length()
    var start = 2
    while start < count and text.get(start, none) == "/": start += 1

    let server_end = text.drop(start).index_of("/")
    if server_end.is_none(): return ""

    var share_start = start + server_end.get(0) + 1
    while share_start < count and text.get(share_start, none) == "/": share_start += 1
    if share_start >= count: return ""

    let share_end = text.drop(share_start).index_of("/")
    if share_end.is_none(): return text.clone()

    return text.take(share_start + share_end.get(0) + 1)

fn root_in(windows: Bool, text: String) String:
    return root_of(windows, slash(windows, text))

fn is_absolute_in(windows: Bool, text: String) Bool:
    let root = root_in(windows, text)
    return root.ends_with("/") or (windows and root.starts_with("//"))

fn normalize_in(windows: Bool, raw: String) String:
    let text = slash(windows, raw)
    if text.is_empty(): return "."

    var root = root_of(windows, text)
    let tail = text.drop(root.length())
    if windows and root.starts_with("//") and not root.ends_with("/"): root = "{root}/"

    var stack: List[String] = []

    for part in tail.split("/", none):
        if part == "" or part == ".": continue

        if part != "..":
            stack.append(part.clone())
        else if stack.length() > 0 and stack[stack.length() - 1] != "..":
            stack.pop()
        else if not root.ends_with("/"):
            stack.append(part.clone())

    var value = "{root}{stack.join("/")}"
    if value.is_empty(): value = "."
    if text.ends_with("/") and not value.ends_with("/"): value = "{value}/"
    if windows and root.length() == 2 and stack.is_empty(): value = "{root}."

    // A relative first component shaped like a drive ("./C:") must not become a drive-relative path
    // once the leading "." is removed.
    if (
        windows
        and root.is_empty()
        and stack.length() > 0
        and root_of(windows, stack[0]) != ""
    ):
        value = "./{value}"
    return native(windows, value)

// The final extension of a basename that holds no slash: a leading dot alone and `..` have none.
fn extension_of_base(base: String) String:
    let dot = base.last_index_of(".")
    if dot.is_none(): return ""

    let at = dot.get(0)
    if at == 0 or base == "..": return ""

    return base.drop(at)

fn parse_in(windows: Bool, original: String) PathParts:
    let text = slash(windows, original)
    let root = root_of(windows, text)
    let trimmed = trim_end_slashes(text)
    let root_original = original.take(root.length())
    var base = ""
    var directory = ""

    if trimmed.length() > trim_end_slashes(root).length():
        let at = trimmed.last_index_of("/")

        if let cut = at:
            base = trimmed.drop(cut + 1)
            directory = original.take(cut)
        else:
            base = trimmed.clone()

        if windows and root.length() == 2 and at.is_none():
            base = trimmed.drop(2)
            directory = root_original.clone()

        if directory.length() < root.length(): directory = root_original.clone()

    if base.is_empty() and not root.is_empty(): directory = root_original.clone()

    let extension = extension_of_base(base)
    let name = base.take(base.length() - extension.length())
    return PathParts(
        root: root_original.clone(), directory: directory, base: base,
        extension: extension, name: name
    )

fn extension_in(windows: Bool, text: String) String:
    if windows: return parse_in(true, text).extension

    let trimmed = trim_end_slashes(text)
    let slash_at = trimmed.last_index_of("/")
    let base = if slash_at.is_none(): trimmed else: trimmed.drop(slash_at.get(0) + 1)
    return extension_of_base(base)

fn equal_fold(left: String, right: String) Bool:
    return left.lower() == right.lower()

// Resolves `parts` against the absolute `base`; none when `base` is not absolute or any text holds NUL.
fn resolve_inner(windows: Bool, base: String, parts: List[String]) String?:
    if not is_absolute_in(windows, base) or base.contains("\u{0}"): return none

    for part in parts:
        if part.contains("\u{0}"): return none

    var value = ""

    if windows:
        // Resolve from the last component: absolute paths supersede earlier tails, while an earlier
        // absolute path on the chosen drive supplies its base.
        var device = ""
        var tail = ""
        var absolute = false
        var components = [base.clone()]
        for part in parts:
            components.append(part.clone())

        var at = components.length()

        while at > 0:
            at -= 1

            let part = slash(true, components[at])
            if part.is_empty(): continue

            let root = root_of(true, part)
            let part_device = root.cut_suffix("/").get(root)

            if not part_device.is_empty():
                if not device.is_empty() and not equal_fold(device, part_device): continue

                device = part_device.clone()

            if not absolute:
                tail = "{part.drop(root.length())}/{tail}"
                absolute = is_absolute_in(true, part)

            if absolute and not device.is_empty(): break

        if not absolute: return none

        value = "{device}/{tail}"
    else:
        value = base.clone()

        for part in parts:
            if is_absolute_in(false, part):
                value = part.clone()
            else if not part.is_empty():
                value = "{trim_end_slashes(value)}/{part}"

    var normalized = normalize_in(windows, value)
    if normalized != native(windows, root_in(windows, normalized)):
        if let stripped = normalized.cut_suffix(native(windows, "/")): normalized = stripped.clone()
    return normalized

fn resolve_in(windows: Bool, base: String, parts: List[String]) String!:
    if let value = resolve_inner(windows, base, parts): return ok(value)

    return error(invalid_input())

fn basename_in(windows: Bool, raw: String) String:
    return basename_inner(windows, raw, "", false)

fn basename_without_in(windows: Bool, raw: String, suffix: String) String:
    return basename_inner(windows, raw, suffix, true)

fn basename_inner(windows: Bool, raw: String, suffix: String, strip: Bool) String:
    var text = slash(windows, raw)
    var prefix = 0

    if (
        windows
        and text.length() >= 2
        and text.get(1, none) == ":"
        and is_letter(text.get(0, none))
    ):
        prefix = 2
        text = text.drop(2)

    var base = trim_end_slashes(text)
    if let at = base.last_index_of("/"): base = base.drop(at + 1)

    if strip and not suffix.is_empty() and suffix.length() <= raw.length():
        if raw == suffix: return ""
        if base.is_empty(): return raw.drop(prefix)

        if suffix != base:
            if let stripped = base.cut_suffix(suffix): base = stripped.clone()

    return base

fn dirname_in(windows: Bool, original: String) String:
    let text = slash(windows, original)
    let root = root_of(windows, text)
    let trimmed = trim_end_slashes(text)
    let at = trimmed.last_index_of("/")

    if at.is_none():
        if root.is_empty(): return "."

        return original.take(root.length())

    if at.get(0) < root.length(): return original.take(root.length())

    return original.take(at.get(0))

fn join_in(windows: Bool, items: List[String]) String:
    let parts = items.filter(fn part: not part.is_empty())
    var joined = parts.join("/")

    if windows and slash(true, joined).starts_with("//"):
        let first = slash(true, parts[0])
        let unc = (
            first.length() > 2
            and first.starts_with("//")
            and first.get(2, none) != "/"
        )
        if not unc: joined = "/{trim_start_slashes(slash(true, joined))}"

    return normalize_in(windows, joined)

fn relative_in(windows: Bool, base_arg: String, target_arg: String) String!:
    let base_resolved = resolve_inner(windows, base_arg, [])
    let target_resolved = resolve_inner(windows, target_arg, [])
    if base_resolved.is_none() or target_resolved.is_none(): return error(
        invalid_input()
    )

    let base = slash(windows, base_resolved.get(""))
    let target = slash(windows, target_resolved.get(""))
    let base_root = root_of(windows, base)
    let target_root = root_of(windows, target)
    if not same_text(windows, base_root, target_root): return ok(
        target_resolved.get("")
    )

    let base_parts = components_after(base, base_root)
    let target_parts = components_after(target, target_root)
    var shared = 0
    while (
        shared < base_parts.length()
        and shared < target_parts.length()
        and same_text(windows, base_parts[shared], target_parts[shared])
    ): shared += 1

    var out: List[String] = []
    for _step in shared..base_parts.length():
        out.append("..")
    for at in shared..target_parts.length():
        out.append(target_parts[at].clone())
    return ok(native(windows, out.join("/")))

fn same_text(windows: Bool, left: String, right: String) Bool:
    if windows: return equal_fold(left, right)

    return left == right

// The slash-separated components of `text` after its `root`; an empty remainder has none.
fn components_after(text: String, root: String) List[String]:
    let rest = text.cut_prefix(root).get(text)
    if rest.is_empty(): return []

    return rest.split("/", none)

fn format_in(windows: Bool, parts: PathParts) String:
    let directory = if parts.directory.is_empty(): parts.root else: parts.directory
    var base = parts.base.clone()

    if base.is_empty():
        let extension = parts.extension

        if not extension.is_empty() and not extension.starts_with("."):
            base = "{parts.name}.{extension}"
        else:
            base = "{parts.name}{extension}"

    if directory.is_empty(): return base
    if directory == parts.root: return "{directory}{base}"

    return "{directory}{native(windows, "/")}{base}"

fn namespaced_in(windows: Bool, text: String) String:
    let root = root_in(windows, text)
    if (
        not windows
        or not is_absolute_in(true, text)
        or root == "/"
        or text.starts_with("\\\\?\\")
        or text.starts_with("\\\\.\\")
    ): return text.clone()

    let resolved = resolve_inner(true, text, [])
    if resolved.is_none(): return text.clone()

    let value = resolved.get("")
    if value.starts_with("\\\\"): return "\\\\?\\UNC\\{value.drop(2)}"

    return "\\\\?\\{value}"

fn glob_in(windows: Bool, path: String, pattern: String) Bool!:
    return msstd_path_matches_glob(windows, path, pattern)

// Returns path operations using POSIX separators and parsing rules.
export fn posix() PathOperations:
    return Dialect(windows: false)

// Returns path operations using Windows separators and parsing rules.
export fn win32() PathOperations:
    return Dialect(windows: true)

// Returns the final path component, excluding trailing separators.
export fn basename(path: String) String:
    return basename_in(host_windows(), path)

// Returns the basename with the supplied suffix removed when it matches.
export fn basename_without(path: String, suffix: String) String:
    return basename_without_in(host_windows(), path, suffix)

// Returns the directory portion of a path.
export fn dirname(path: String) String:
    return dirname_in(host_windows(), path)

// Returns the final extension, including its leading dot, or an empty string.
export fn extension(path: String) String:
    return extension_in(host_windows(), path)

// Reports whether a path is absolute according to the host path rules.
export fn is_absolute(path: String) Bool:
    return is_absolute_in(host_windows(), path)

// Joins path parts using the host separator and normalizes the result.
export fn join(parts: List[String]) String:
    return join_in(host_windows(), parts)

// Normalizes separators and dot segments without accessing the filesystem.
export fn normalize(path: String) String:
    return normalize_in(host_windows(), path)

// Computes a relative path from `base` to `target` using host path rules.
export fn relative(base: String, target: String) String!:
    return relative_in(host_windows(), base, target)

// Resolves path parts against a base using host path conventions.
export fn resolve(base: String, parts: List[String]) String!:
    return resolve_in(host_windows(), base, parts)

// Splits a path into its root, directory, base, extension, and name.
export fn parse(path: String) PathParts:
    return parse_in(host_windows(), path)

// Formats parsed path components as a path string.
export fn format(parts: PathParts) String:
    return format_in(host_windows(), parts)

// Returns the host's path separator.
export fn separator() String:
    return if host_windows(): "\\" else: "/"

// Returns the host's path-list delimiter.
export fn delimiter() String:
    return if host_windows(): ";" else: ":"

// Converts a path to the host's namespaced representation when applicable.
export fn to_namespaced_path(path: String) String:
    return namespaced_in(host_windows(), path)

// Tests a path against a glob pattern.
export fn matches_glob(path: String, pattern: String) Bool!:
    return glob_in(host_windows(), path, pattern)
