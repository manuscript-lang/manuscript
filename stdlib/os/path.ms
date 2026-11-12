/*
Lexical path text: no function here touches the filesystem.

Every function exists twice: the module-level one follows the host's rules (backslash and drive roots on Windows, slash elsewhere), and `posix()` / `win32()` return the same operations for one chosen dialect, so a program can handle either spelling on any host.

<!-- manuscript-example: {"mode":"fragment"} -->
```manuscript
import join, basename from "@std/os/path.ms"

config := join(["/etc", "app", "main.toml"])
name := basename(config)
```
*/
import (
	Bytes, BytesBuilder from "@std/bytes.ms",
	Os, os from "@std/os/system.ms",
	StringBuilder from "@std/string.ms",

	msstd_path_matches_glob from "@std/internal/path.ms",
)

// Parsed path components using the familiar root, directory, base, extension, and name
// fields.
export type PathParts:
	// Root prefix under the chosen path rules, including a POSIX slash or Windows
	// drive/UNC root.
	root: String
	// Directory portion, including the root when present; it takes precedence over root
	// during format.
	directory: String
	// Final component with extension; it takes precedence over name/extension during
	// format.
	base: String
	// Final extension including its dot; simple dotfiles and dot/dot-dot components
	// have no extension.
	extension: String
	// Final component with its extension removed, retaining the original spelling.
	name: String

// Path operations using either POSIX or Windows path conventions.
export interface PathOperations:
	// Returns the last component after ignoring trailing separators under this view's
	// path rules.
	fn basename(path: String) String
	// Removes an exact suffix under basename compatibility rules; it does not strip
	// arbitrary extensions.
	fn basename_without(path: String, suffix: String) String
	// Returns the directory component using the selected POSIX or Windows convention.
	fn dirname(path: String) String
	// Returns the final dot extension, or empty text for extensionless names and simple
	// dotfiles.
	fn extension(path: String) String
	// Tests absolute-root syntax; a Windows drive-relative spelling is not absolute.
	fn is_absolute(path: String) Bool
	// Joins nonempty parts and normalizes separators/dot segments without filesystem
	// access.
	fn join(parts: List[String]) String
	// Cleans repeated separators and dot segments lexically; it does not resolve
	// symlinks.
	fn normalize(path: String) String
	// Computes a lexical relative path from absolute anchors; different roots return
	// the original target. Nonabsolute anchors or invalid NUL input return EINVAL.
	fn relative(base: String, target: String) String!
	// Resolves parts against an explicit absolute base; no process working directory is
	// consulted.
	fn resolve(base: String, parts: List[String]) String!
	// Splits the original spelling into root, directory, base, extension and name
	// without filesystem access.
	fn parse(path: String) PathParts
	// Builds a path with directory preferred over root, and base preferred over name
	// plus extension.
	fn format(parts: PathParts) String
	// Returns slash for POSIX or backslash for Windows path components.
	fn separator() String
	// Returns colon for POSIX or semicolon for Windows path-list entries.
	fn delimiter() String
	// Returns a Windows namespaced absolute path when applicable; POSIX paths are
	// unchanged.
	fn to_namespaced_path(path: String) String
	// Tests one lexical path against the supported glob syntax; malformed patterns
	// return EINVAL.
	fn matches_glob(path: String, pattern: String) Bool!

// One dialect's rules; the interface implementation forwards to the functions below
// with its flag.
type Dialect:
	windows: Bool

fn Dialect.basename(path: String) String:
	return basename_in(self.windows, path)

fn Dialect.basename_without(path: String, suffix: String) String:
	return basename_without_in(self.windows, path, suffix)

fn Dialect.dirname(path: String) String:
	return dirname_in(self.windows, path)

fn Dialect.extension(path: String) String:
	return extension_in(self.windows, path)

fn Dialect.is_absolute(path: String) Bool:
	return is_absolute_in(self.windows, path)

fn Dialect.join(parts: List[String]) String:
	return join_in(self.windows, parts)

fn Dialect.normalize(path: String) String:
	return normalize_in(self.windows, path)

fn Dialect.relative(base: String, target: String) String!:
	return relative_in(self.windows, base, target)

fn Dialect.resolve(base: String, parts: List[String]) String!:
	return resolve_in(self.windows, base, parts)

fn Dialect.parse(path: String) PathParts:
	return parse_in(self.windows, path)

fn Dialect.format(parts: PathParts) String:
	return format_in(self.windows, parts)

fn Dialect.separator() String:
	return if self.windows: "\\" else: "/"

fn Dialect.delimiter() String:
	return if self.windows: ";" else: ":"

fn Dialect.to_namespaced_path(path: String) String:
	return namespaced_in(self.windows, path)

fn Dialect.matches_glob(path: String, pattern: String) Bool!:
	return glob_in(self.windows, path, pattern)

fn host_windows() Bool:
	return os() == Os.Windows

fn invalid_input() Error:
	return Error("path: invalid input", kind: "EINVAL")

fn is_letter(c: String) Bool:
	code := c.scalar_at(0, none)
	return (code >= 65 and code <= 90) or (code >= 97 and code <= 122)

// The path with every backslash read as a slash under Windows rules; POSIX text is
// unchanged.
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
	if not text.ends_with("//"): return text.take(text.length() - 1)

	data := text.to_bytes()
	var end = data.length()
	while end > 0 and data.get(end - 1, none).to_int() == 47: end -= 1
	return text_of(data, 0, end)

// Removes every leading slash.
fn trim_start_slashes(text: String) String:
	if not text.starts_with("/"): return text.clone()
	if not text.starts_with("//"): return text.drop(1)

	data := text.to_bytes()
	var start = 0
	count := data.length()
	while start < count and data.get(start, none).to_int() == 47: start += 1
	return text_of(data, start, count)

// The root of an already slash-normalized path: a Windows drive or UNC share, `/`, or
// empty.
fn root_of(windows: Bool, text: String) String:
	if windows:
		count := text.length()

		if (
			count >= 2
			and is_letter(text.get(0, none))
			and text.scalar_at(1, none) == 58
		):
			if count > 2 and text.scalar_at(2, none) == 47: return text.take(3)
			return text.take(2)

		if text.starts_with("//"):
			unc := unc_root(text)
			if unc != "": return unc

	if text.starts_with("/"): return "/"

	return ""

// The `//server/share` root of a slash-normalized UNC path, or empty when the text is
// not one.
fn unc_root(text: String) String:
	data := text.to_bytes()
	count := data.length()
	var start = 2
	while start < count and data.get(start, none).to_int() == 47: start += 1

	server_end := data.index_of_byte(47, start).get(count)
	if server_end == count: return ""

	var share_start = server_end + 1
	while share_start < count and data.get(share_start, none).to_int() == 47: share_start += 1
	if share_start >= count: return ""

	share_end := data.index_of_byte(47, share_start).get(count)
	if share_end == count: return text.clone()

	return text_of(data, 0, share_end + 1)

fn root_in(windows: Bool, text: String) String:
	return root_of(windows, slash(windows, text))

fn is_absolute_in(windows: Bool, text: String) Bool:
	root := root_in(windows, text)
	return root.ends_with("/") or (windows and root.starts_with("//"))

// A segment of the bytes being normalized, packed as `start * 2^32 + end`.
fn span(start: Int, end: Int) Int:
	return start * 4294967296 + end

fn span_start(packed: Int) Int:
	return packed / 4294967296

fn span_end(packed: Int) Int:
	return packed % 4294967296

// True when the segment is `..`.
fn span_is_parent(data: Bytes, packed: Int) Bool:
	start := span_start(packed)
	return (
		span_end(packed) - start == 2
		and data.get(start, none).to_int() == 46
		and data.get(start + 1, none).to_int() == 46
	)

fn normalize_in(windows: Bool, raw: String) String:
	if windows: return normalize_core(true, slash(true, raw))
	return normalize_core(false, raw)

// A POSIX path that normalizing would leave unchanged: no empty, `.` or `..` segment
// and no trailing separator (the root alone is clean). One scan, so already-clean paths
// skip the span list and the rebuild.
fn is_clean(data: Bytes) Bool:
	count := data.length()
	if count == 1: return data.get(0, none).to_int() == 47

	var start = if data.get(0, none).to_int() == 47: 1 else: 0
	var at = start

	while at <= count:
		if at == count or data.get(at, none).to_int() == 47:
			size := at - start
			if size == 0: return false
			if size == 1 and data.get(start, none).to_int() == 46: return false
			if (
				size == 2
				and data.get(start, none).to_int() == 46
				and data.get(start + 1, none).to_int() == 46
			): return false

			start = at + 1

		at += 1

	return true

// `text` already reads backslashes as slashes under Windows rules.
fn normalize_core(windows: Bool, text: String) String:
	if text.is_empty(): return "."

	root := root_of(windows, text)
	root_bytes := root.byte_length()

	// A UNC root without a trailing separator gets one in the result.
	unc_open := windows and root.starts_with("//") and not root.ends_with("/")
	root_ends_slash := unc_open or root.ends_with("/")

	// One pass over the bytes after the root: segments are spans into `data`, never
	// copied until written.
	data := text.to_bytes()
	count := data.length()
	if not windows and is_clean(data): return text.clone()

	var stack: List[Int] = []
	var start = root_bytes
	var at = root_bytes

	while at <= count:
		if at == count or data.get(at, none).to_int() == 47:
			size := at - start
			dot := size == 1 and data.get(start, none).to_int() == 46

			if size == 0 or dot:
				start = at + 1
			else if (
				size == 2
				and data.get(start, none).to_int() == 46
				and data.get(start + 1, none).to_int() == 46
			):
				if (
					not stack.is_empty()
					and not span_is_parent(
						data,
						stack[stack.length() - 1],
					)
				):
					stack.pop()
				else if not root_ends_slash:
					stack.append(span(start, at))

				start = at + 1
			else:
				stack.append(span(start, at))
				start = at + 1

		at += 1

	var out = BytesBuilder()
	out.append_bytes(data.view(0, root_bytes))
	if unc_open: out.append(47)

	for index in 0..stack.length():
		if index > 0: out.append(47)

		packed := stack[index]
		out.append_bytes(data.view(span_start(packed), span_end(packed)))

	if root.is_empty() and stack.is_empty(): out.append(46)

	// A trailing separator survives unless the result already ends with one.
	if text.ends_with("/") and not (stack.is_empty() and root_ends_slash): out.append(
		47
	)

	var value = out.build().decode_utf8().get("")
	if not windows: return value

	if root.length() == 2 and stack.is_empty(): value = "{root}."

	// A relative first component shaped like a drive ("./C:") must not become a
	// drive-relative path once the leading "." is removed.
	if root.is_empty() and not stack.is_empty():
		first := stack[0]
		head := data.view(span_start(first), span_end(first)).decode_utf8().get("")
		if root_of(true, head) != "": value = "./{value}"

	return native(true, value)

// The final extension of a basename that holds no slash: a leading dot alone and `..`
// have none.
fn extension_of_base(base: String) String:
	dot := base.last_index_of(".")
	if dot.is_none(): return ""

	at := dot.get(0)
	if at == 0 or base == "..": return ""

	return base.drop(at)

fn parse_in(windows: Bool, original: String) PathParts:
	if windows: return parse_core(true, slash(true, original), original)
	return parse_core(false, original, original)

// Splits by byte positions, so every field is one view of `original` decoded; `text` is
// `original` with backslashes read as slashes (the same positions).
fn parse_core(windows: Bool, text: String, original: String) PathParts:
	root_len := root_of(windows, text).byte_length()
	data := text.to_bytes()
	source := original.to_bytes()
	var end = data.length()
	while end > 0 and data.get(end - 1, none).to_int() == 47: end -= 1

	var root_core = root_len
	while root_core > 0 and data.get(root_core - 1, none).to_int() == 47: root_core -= 1

	var base_start = 0
	var base_end = 0
	var directory_end = 0

	if end > root_core:
		var at = end - 1
		while at >= 0 and data.get(at, none).to_int() != 47: at -= 1
		base_end = end

		if at >= 0:
			base_start = at + 1
			directory_end = at
		else if windows and root_len == 2:
			base_start = 2
			directory_end = root_len

		if directory_end < root_len: directory_end = root_len

	if base_end == 0 and root_len > 0: directory_end = root_len

	// The extension starts at the last dot of the base, unless that dot is the base's
	// first byte or the base is `..`.
	var dot = base_end - 1
	while dot >= base_start and data.get(dot, none).to_int() != 46: dot -= 1

	is_parent := (
		base_end - base_start == 2
		and dot == base_start + 1
		and data.get(base_start, none).to_int() == 46
	)
	extension_start := if dot < base_start or dot == base_start or is_parent: base_end else: dot
	return PathParts(
		root: text_of(source, 0, root_len),
		directory: text_of(source, 0, directory_end),
		base: text_of(source, base_start, base_end),
		extension: text_of(source, extension_start, base_end),
		name: text_of(source, base_start, extension_start),
	)

// The text of bytes [start, end) of `data`.
fn text_of(data: Bytes, start: Int, end: Int) String:
	if start >= end: return ""
	return data.view(start, end).decode_utf8().get("")

fn extension_in(windows: Bool, text: String) String:
	if windows: return parse_in(true, text).extension

	trimmed := trim_end_slashes(text)
	slash_at := trimmed.last_index_of("/")
	base := if slash_at.is_none(): trimmed else: trimmed.drop(slash_at.get(0) + 1)
	return extension_of_base(base)

fn equal_fold(left: String, right: String) Bool:
	if left == right: return true
	return lowercase_path(left) == lowercase_path(right)

// Path comparisons retain the original per-scalar lowercase mapping. Whole-string
// lowercasing makes a capital sigma contextual (Σ -> ς at word end), unlike that
// mapping (Σ -> σ).
fn lowercase_path(text: String) String:
	if text.contains("Σ"): return text.replace("Σ", "σ").lower()
	return text.lower()

// Resolves `parts` against the absolute `base`; none when `base` is not absolute or any
// text holds NUL.
fn resolve_inner(windows: Bool, base: String, parts: List[String]) String?:
	if not is_absolute_in(windows, base) or base.contains("\u{0}"): return none

	for part in parts:
		if part.contains("\u{0}"): return none

	var value = ""

	if windows:
		// Resolve from the last component: absolute paths supersede earlier tails,
		// while an earlier absolute path on the chosen drive supplies its base.
		var device = ""
		var tail = ""
		var absolute = false
		var components = [base.clone()]
		components.extend(parts)

		var at = components.length()

		while at > 0:
			at -= 1

			part := slash(true, components[at])
			if part.is_empty(): continue

			root := root_of(true, part)
			part_device := root.cut_suffix("/").get(root)

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
		// Only the last absolute part and its following tails survive resolution.
		var start = parts.length()
		var has_tail = false

		while start > 0:
			part := parts[start - 1]
			if is_absolute_in(false, part): break

			if not part.is_empty(): has_tail = true
			start -= 1

		anchor := if start == 0: base else: parts[start - 1]

		if not has_tail:
			value = anchor.clone()
		else:
			var out = StringBuilder()
			out.append(anchor)

			var separated = anchor.ends_with("/")

			for at in start..parts.length():
				part := parts[at]
				if part.is_empty(): continue

				if not separated: out.append("/")
				out.append(part)
				separated = part.ends_with("/")

			value = out.build()

	var normalized = normalize_in(windows, value)
	if normalized != native(windows, root_in(windows, normalized)):
		if stripped := normalized.cut_suffix(native(windows, "/")): normalized = stripped.clone()
	return normalized

fn resolve_in(windows: Bool, base: String, parts: List[String]) String!:
	if value := resolve_inner(windows, base, parts): return ok(value)
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
		and text.scalar_at(1, none) == 58
		and is_letter(text.get(0, none))
	):
		prefix = 2
		text = text.drop(2)

	var base = trim_end_slashes(text)
	if at := base.last_index_of("/"): base = base.drop(at + 1)

	if strip and not suffix.is_empty() and suffix.length() <= raw.length():
		if raw == suffix: return ""
		if base.is_empty(): return raw.drop(prefix)

		if suffix != base:
			if stripped := base.cut_suffix(suffix): base = stripped.clone()

	return base

fn dirname_in(windows: Bool, original: String) String:
	text := slash(windows, original)
	root := root_of(windows, text)
	trimmed := trim_end_slashes(text)
	at := trimmed.last_index_of("/")

	if at.is_none():
		if root.is_empty(): return "."
		return original.take(root.length())

	if at.get(0) < root.length(): return original.take(root.length())

	return original.take(at.get(0))

fn join_in(windows: Bool, items: List[String]) String:
	var out = BytesBuilder()
	var first = ""
	var count = 0

	for part in items:
		if part.is_empty(): continue

		if windows and count == 0: first = slash(true, part)
		if count > 0: out.append(47)
		out.append_bytes(part.to_bytes())
		count += 1

	var joined = out.build().decode_utf8().get("")

	if windows and slash(true, joined).starts_with("//"):
		unc := (
			first.length() > 2
			and first.starts_with("//")
			and first.scalar_at(2, none) != 47
		)
		if not unc: joined = "/{trim_start_slashes(slash(true, joined))}"

	return normalize_in(windows, joined)

fn relative_in(windows: Bool, base_arg: String, target_arg: String) String!:
	base_resolved := resolve_inner(windows, base_arg, [])
	target_resolved := resolve_inner(windows, target_arg, [])
	if base_resolved.is_none() or target_resolved.is_none(): return error(
		invalid_input()
	)

	base := slash(windows, base_resolved.get(""))
	target := slash(windows, target_resolved.get(""))
	base_root := root_of(windows, base)
	target_root := root_of(windows, target)
	if not same_text(windows, base_root, target_root): return ok(
		target_resolved.get("")
	)

	base_parts := components_after(base, base_root)
	target_parts := components_after(target, target_root)
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

// The slash-separated components of `text` after its `root`; an empty remainder has
// none.
fn components_after(text: String, root: String) List[String]:
	rest := text.cut_prefix(root).get(text)
	if rest.is_empty(): return []

	return rest.split("/", none)

fn format_in(windows: Bool, parts: PathParts) String:
	directory := if parts.directory.is_empty(): parts.root else: parts.directory
	var base = parts.base.clone()

	if base.is_empty():
		extension := parts.extension

		if not extension.is_empty() and not extension.starts_with("."):
			base = "{parts.name}.{extension}"
		else:
			base = "{parts.name}{extension}"

	if directory.is_empty(): return base
	if directory == parts.root: return "{directory}{base}"

	return "{directory}{native(windows, "/")}{base}"

fn namespaced_in(windows: Bool, text: String) String:
	root := root_in(windows, text)
	if (
		not windows
		or not is_absolute_in(true, text)
		or root == "/"
		or text.starts_with("\\\\?\\")
		or text.starts_with("\\\\.\\")
	): return text.clone()

	resolved := resolve_inner(true, text, [])
	if resolved.is_none(): return text.clone()

	value := resolved.get("")
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
