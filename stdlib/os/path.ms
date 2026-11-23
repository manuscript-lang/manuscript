/*
Lexical path text: no function here touches the filesystem.

Every function exists twice. The module-level one follows the host's rules (backslash and drive roots on Windows, slash elsewhere). `posix()` and `win32()` return the same operations for one chosen dialect, so a program can handle either spelling on any host.

<!-- manuscript-example: {"mode":"fragment","given":[]} -->
```manuscript
import join, basename from "@std/os/path.ms"

config := join(["/etc", "app", "main.toml"])
name := basename(config)
print(name)
```
*/
import (
	Bytes, BytesBuilder from "@std/bytes.ms",
	StringBuilder from "@std/string_builder.ms",

	msstd_path_compile_glob,
	msstd_path_glob_matches,
	msstd_path_host_windows from "@std/internal/path.ms",
)

// The components of a path: root, directory, base, extension, and name. `parse` splits
// a path into them and `format` joins them again.
export type PathParts:
	// Root prefix under the chosen path rules, including a POSIX slash or Windows
	// drive/UNC root.
	root: String
	// Directory portion, including the root when present; `format` prefers it over
	// `root`.
	directory: String
	// Final component with its extension; `format` prefers it over `name` plus
	// `extension`.
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
	fn basename(path: String) move String
	// Returns the basename with `suffix` removed when it matches exactly. It is not an
	// extension stripper: a suffix equal to the whole basename is not removed.
	fn basename_without(path: String, suffix: String) move String
	// Returns the directory component using the selected POSIX or Windows convention.
	fn dirname(path: String) move String
	// Returns the final dot extension, or empty text for extensionless names and simple
	// dotfiles.
	fn extension(path: String) move String
	// Tests absolute-root syntax; a Windows drive-relative spelling is not absolute.
	fn is_absolute(path: String) Bool
	// Joins nonempty parts and normalizes separators/dot segments without filesystem
	// access.
	fn join(parts: List[String]) move String
	// Cleans repeated separators and dot segments lexically; it does not resolve
	// symlinks.
	fn normalize(path: String) move String
	// Computes the lexical relative path from `base` to `target`, both absolute. Paths
	// with different roots, such as Windows drives, return `target` normalized. A
	// relative argument or a NUL byte returns EINVAL.
	fn relative(base: String, target: String) move String!
	// Resolves `parts` against the absolute `base`, without consulting the process
	// working directory. A relative `base` or a NUL byte returns EINVAL.
	fn resolve(base: String, parts: List[String]) move String!
	// Splits the original spelling into root, directory, base, extension and name
	// without filesystem access.
	fn parse(path: String) move PathParts
	// Builds a path from `parts`, preferring `directory` over `root` and `base` over
	// `name` plus `extension`.
	fn format(parts: PathParts) move String
	// Returns slash for POSIX or backslash for Windows path components.
	fn separator() move String
	// Returns colon for POSIX or semicolon for Windows path-list entries.
	fn delimiter() move String
	// Returns a Windows namespaced absolute path when applicable; POSIX paths are
	// unchanged.
	fn to_namespaced_path(path: String) move String
	// Tests one lexical path against the supported glob syntax; malformed patterns
	// return EINVAL.
	fn matches_glob(path: String, pattern: String) Bool!
	// Compiles a glob pattern once for matching many paths under this dialect's rules;
	// malformed patterns return EINVAL.
	fn compile_glob(pattern: String) move Glob!

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

fn Dialect.compile_glob(pattern: String) Glob!:
	return msstd_path_compile_glob(self.windows, pattern)

fn host_windows() Bool:
	return msstd_path_host_windows()

fn invalid_input() Error:
	return Error("path: invalid input", kind: "EINVAL")

fn is_letter(text: String) Bool:
	code := text.scalar_at(0, -1)
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
	if not text.ends_with("//"): return text.view(0, text.length() - 1).clone()

	data := text.to_bytes()
	var end = data.length()
	while end > 0 and data.get_or(end - 1, null).to_int() == 47: end -= 1
	return text_of(data, 0, end)

// Removes every leading slash.
fn trim_start_slashes(text: String) String:
	if not text.starts_with("/"): return text.clone()
	if not text.starts_with("//"): return text.view(1, text.length()).clone()

	data := text.to_bytes()
	var start = 0
	count := data.length()
	while start < count and data.get_or(start, null).to_int() == 47: start += 1
	return text_of(data, start, count)

// The root of an already slash-normalized path: a Windows drive or UNC share, `/`, or
// empty.
fn root_of(windows: Bool, text: String) String:
	if windows:
		count := text.length()

		if (count >= 2 and is_letter(text) and text.scalar_at(1, -1) == 58):
			if count > 2 and text.scalar_at(2, -1) == 47: return text.view(0, 3).clone()
			return text.view(0, 2).clone()

		if is_device(text):
			// `//?/` and `//./` are namespace prefixes: the first segment after them
			// belongs to the root, but `.`, `..` and nothing leave the prefix alone.
			rest := text.view(4, text.length())
			if (
				rest.is_empty()
				or rest.starts_with("./")
				or rest == "."
				or rest.starts_with("../")
				or rest == ".."
			): return text.view(0, 4).clone()

		if text.starts_with("//"):
			unc := unc_root(text)
			if unc != "": return unc

	if text.starts_with("/"): return "/"

	return ""

// Whether a slash-normalized Windows path starts with a `//?/` or `//./` namespace
// prefix.
fn is_device(text: String) Bool:
	return text.starts_with("//?/") or text.starts_with("//./")

// The `//server/share` root of a slash-normalized UNC path, or empty when the text is
// not one.
fn unc_root(text: String) String:
	data := text.to_bytes()
	count := data.length()
	var start = 2

	// A third leading separator makes the text a rooted path, not a UNC server.
	if start < count and data.get_or(start, null).to_int() == 47: return ""

	server_end := data.index_of_byte(47, start) or count
	if server_end == count: return ""

	var share_start = server_end + 1
	while share_start < count and data.get_or(share_start, null).to_int() == 47: share_start += 1
	if share_start >= count: return ""

	share_end := data.index_of_byte(47, share_start) or count
	if share_end == count: return text.clone()

	return text_of(data, 0, share_end + 1)

// A `//server//share/` root with its repeated separators collapsed to `//server/share`
// plus the trailing separator the root already had.
fn canonical_unc_root(root: String) String:
	parts := root.split("/").filter(fn part: not part.is_empty())
	joined := "//" + parts.join("/")
	if root.ends_with("/"): return joined + "/"

	return joined

fn root_in(windows: Bool, text: String) String:
	if not windows: return root_of(false, text)
	return root_of(true, slash(true, text))

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
		and data.get_or(start, null).to_int() == 46
		and data.get_or(start + 1, null).to_int() == 46
	)

fn normalize_in(windows: Bool, raw: String) String:
	if windows:
		text := slash(true, raw)
		if is_device(text) and text.view(4, text.length()).starts_with("/"): return normalize_core(
			true,
			f"{text.view(0, 4)}{trim_start_slashes(text.view(4, text.length()))}",
		)

		return normalize_core(true, text)

	return normalize_core(false, raw)

// A POSIX path that normalizing would leave unchanged: no empty, `.` or `..` segment
// and no trailing separator (the root alone is clean). One scan, so already-clean paths
// skip the span list and the rebuild.
fn is_clean(data: Bytes) Bool:
	count := data.length()
	if count == 1: return data.get_or(0, null).to_int() == 47

	var start = if data.get_or(0, null).to_int() == 47: 1 else: 0

	while start <= count:
		end := data.index_of_byte(47, start) or count
		size := end - start
		if size == 0: return false
		if size == 1 and data.get_or(start, null).to_int() == 46: return false
		if (
			size == 2
			and data.get_or(start, null).to_int() == 46
			and data.get_or(start + 1, null).to_int() == 46
		): return false

		start = end + 1

	return true

// `text` already reads backslashes as slashes under Windows rules.
fn normalize_core(windows: Bool, text: String) String:
	if text.is_empty(): return "."

	root := root_of(windows, text)
	root_bytes := root.length()

	// A UNC root without a trailing separator gets one in the result.
	unc_open := (
		windows
		and root.starts_with("//")
		and not root.ends_with("/")
		and not is_device(root)
	)
	root_ends_slash := unc_open or root.ends_with("/")

	// One pass over the bytes after the root: segments are spans into `data`, never
	// copied until written.
	data := text.view_bytes()
	count := data.length()
	if not windows and is_clean(data): return text.clone()

	var stack: List[Int] = []
	var start = root_bytes

	while start <= count:
		end := data.index_of_byte(47, start) or count
		size := end - start
		dot := size == 1 and data.get_or(start, null).to_int() == 46

		if size == 0 or dot:
			start = end + 1
			continue

		if (
			size == 2
			and data.get_or(start, null).to_int() == 46
			and data.get_or(start + 1, null).to_int() == 46
		):
			if (
				not stack.is_empty()
				and not span_is_parent(data, stack[stack.length() - 1])
			):
				stack.pop()
			else if not root_ends_slash:
				stack.append(span(start, end))
		else:
			stack.append(span(start, end))

		start = end + 1

	// Segments are runs between slashes of valid text, so they are copied as views.
	var out = StringBuilder()

	if windows and root.starts_with("//") and not is_device(root):
		out.append(canonical_unc_root(root))
	else:
		out.append(text.view(0, root_bytes))

	if unc_open: out.append("/")

	// Segments one separator apart in the input are one run of the input: copy a run
	// at a time, not a segment and a separator at a time.
	var index = 0
	var first_run = true

	while index < stack.length():
		run_start := span_start(stack[index])
		var run_end = span_end(stack[index])
		index += 1

		while index < stack.length() and span_start(stack[index]) == run_end + 1:
			run_end = span_end(stack[index])
			index += 1

		if not first_run: out.append("/")
		first_run = false
		out.append(text.view(run_start, run_end))

	if root.is_empty() and stack.is_empty(): out.append(".")

	// A trailing separator survives unless the result already ends with one.
	if text.ends_with("/") and not (stack.is_empty() and root_ends_slash): out.append(
		"/"
	)

	var value = out.build()
	if not windows: return value

	if root.length() == 2 and stack.is_empty(): value = f"{root}."

	// A relative first component shaped like a drive ("./C:") must not become a
	// drive-relative path once the leading "." is removed.
	if root.is_empty() and not stack.is_empty():
		first := stack[0]
		head := data.view(span_start(first), span_end(first)).decode_utf8() or ""
		if root_of(true, head) != "": value = f"./{value}"

	return native(true, value)

// The final extension of a basename that holds no slash: a leading dot alone and `..`
// have null.
fn extension_of_base(base: String) String:
	dot := base.last_index_of(".")
	if dot == null: return ""

	at := dot
	if at == 0 or base == "..": return ""

	return base.view(at, base.length()).clone()

fn parse_in(windows: Bool, original: String) PathParts:
	if windows: return parse_core(true, slash(true, original), original)
	return parse_core(false, original, original)

// Splits by byte positions, so every field is one view of `original` decoded; `text` is
// `original` with backslashes read as slashes (the same positions).
fn parse_core(windows: Bool, text: String, original: String) PathParts:
	root_len := root_of(windows, text).length()
	data := text.to_bytes()
	source := original.to_bytes()
	var end = data.length()
	while end > 0 and data.get_or(end - 1, null).to_int() == 47: end -= 1

	var root_core = root_len
	while root_core > 0 and data.get_or(root_core - 1, null).to_int() == 47: root_core -= 1

	var base_start = 0
	var base_end = 0
	var directory_end = 0

	if end > root_core:
		var at = end - 1
		while at >= 0 and data.get_or(at, null).to_int() != 47: at -= 1
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
	while dot >= base_start and data.get_or(dot, null).to_int() != 46: dot -= 1

	is_parent := (
		base_end - base_start == 2
		and dot == base_start + 1
		and data.get_or(base_start, null).to_int() == 46
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
	return data.view(start, end).decode_utf8() or ""

fn extension_in(windows: Bool, text: String) String:
	if windows: return parse_in(true, text).extension.clone()

	trimmed := trim_end_slashes(text)
	slash_at := trimmed.last_index_of("/")
	base := if slash_at == null: trimmed.clone() else: trimmed.view(
		(slash_at or 0) + 1,
		trimmed.length(),
	)
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

// Resolves `parts` against the absolute `base`; null when `base` is not absolute or any
// text holds NUL.
fn resolve_inner(windows: Bool, base: String, parts: List[String]) String?:
	if not is_absolute_in(windows, base) or base.contains("\u{0}"): return null

	for part in parts:
		if part.contains("\u{0}"): return null

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
			part_device := root.cut_suffix("/") or root.clone()

			if not part_device.is_empty():
				if not device.is_empty() and not equal_fold(device, part_device): continue

				device = part_device.clone()

			if not absolute:
				tail = f"{part.view(root.length(), part.length())}/{tail}"
				absolute = is_absolute_in(true, part)

			if absolute and not device.is_empty(): break

		if not absolute: return null

		value = f"{device}/{tail}"
	else:
		// Only the last absolute part and its following tails survive resolution.
		var start = parts.length()
		var has_tail = false

		while start > 0:
			part := parts[start - 1]
			if is_absolute_in(false, part): break

			if not part.is_empty(): has_tail = true
			start -= 1

		anchor := if start == 0: base.clone() else: parts[start - 1].clone()

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

	if windows:
		if normalized != native(true, root_in(true, normalized)):
			stripped := normalized.cut_suffix("\\")
			if stripped != null: normalized = stripped.clone()

		return normalized

	// POSIX: a trailing separator survives only on the root itself.
	if normalized.length() > 1 and normalized.ends_with("/"): return normalized.view(
		0,
		normalized.length() - 1,
	).clone()

	return normalized

fn resolve_in(windows: Bool, base: String, parts: List[String]) String!:
	value := resolve_inner(windows, base, parts)
	if value != null: return ok(value)

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
		and text.scalar_at(1, -1) == 58
		and is_letter(text)
	):
		prefix = 2
		text = text.view(2, text.length()).clone()

	var base = trim_end_slashes(text)
	at := base.last_index_of("/")
	if at != null: base = base.view(at + 1, base.length()).clone()

	if strip and not suffix.is_empty() and suffix.length() <= raw.length():
		if raw == suffix: return ""
		if base.is_empty(): return raw.view(prefix, raw.length()).clone()

		if suffix != base:
			stripped := base.cut_suffix(suffix)
			if stripped != null: base = stripped.clone()

	return base

fn dirname_in(windows: Bool, original: String) String:
	text := slash(windows, original)
	root := root_of(windows, text)
	trimmed := trim_end_slashes(text)
	at := trimmed.last_index_of("/")

	if at == null:
		if root.is_empty(): return "."
		return original.view(0, root.length()).clone()

	if (at) < root.length(): return original.view(0, root.length()).clone()

	return original.view(0, at).clone()

fn join_in(windows: Bool, items: List[String]) String:
	var first = ""
	var has_empty = false

	for part in items:
		if part.is_empty():
			has_empty = true
			continue

		if windows and first.is_empty(): first = slash(true, part)

	// Without empty parts the joined text is one exact-size allocation.
	var joined = ""

	if not has_empty:
		joined = items.join("/")
	else:
		var out = StringBuilder()
		var count = 0

		for part in items:
			if part.is_empty(): continue

			if count > 0: out.append("/")
			out.append(part)
			count += 1

		joined = out.build()

	if windows and slash(true, joined).starts_with("//"):
		unc := (
			first.length() > 2
			and first.starts_with("//")
			and first.scalar_at(2, -1) != 47
		)
		if not unc: joined = f"/{trim_start_slashes(slash(true, joined))}"

	return normalize_in(windows, joined)

fn relative_in(windows: Bool, base_arg: String, target_arg: String) String!:
	base_resolved := resolve_inner(windows, base_arg, [])
	target_resolved := resolve_inner(windows, target_arg, [])
	if (base_resolved == null) or (target_resolved == null): return error(
		invalid_input()
	)

	base := slash(windows, base_resolved)
	target := slash(windows, target_resolved.clone())
	base_root := root_of(windows, base)
	target_root := root_of(windows, target)
	if not same_text(windows, base_root, target_root): return ok(target_resolved)

	// The components borrow `base` and `target` for the comparison; only the result
	// copies.
	base_rest := base.view(
		if base.starts_with(base_root): base_root.length() else: 0,
		base.length(),
	)
	target_rest := target.view(
		if target.starts_with(target_root): target_root.length() else: 0,
		target.length(),
	)
	base_data := base_rest.view_bytes()
	target_data := target_rest.view_bytes()
	base_count := base_rest.length()
	target_count := target_rest.length()

	// Skip the leading components both paths share, then climb out of what is left of
	// `base` and descend into what is left of `target`.
	var base_at = 0
	var target_at = 0

	while base_at < base_count and target_at < target_count:
		base_end := base_data.index_of_byte(47, base_at) or base_count
		target_end := target_data.index_of_byte(47, target_at) or target_count
		if not same_text(
			windows,
			base_rest.view(base_at, base_end),
			target_rest.view(target_at, target_end),
		): break

		base_at = base_end + 1
		target_at = target_end + 1

	var out = StringBuilder()
	var climbs = 0
	var scan = base_at

	while scan < base_count:
		climbs += 1
		scan = (base_data.index_of_byte(47, scan) or base_count) + 1

	for step in 0..climbs:
		if step > 0: out.append("/")
		out.append("..")

	if target_at < target_count:
		if climbs > 0: out.append("/")
		out.append(target_rest.view(target_at, target_count))

	return ok(native(windows, out.build()))

fn same_text(windows: Bool, left: String, right: String) Bool:
	if windows: return equal_fold(left, right)
	return left == right

// Builds a path from `parts`: `directory` (else `root`), then `base` (else `name` plus
// `extension`), joined by the dialect's separator.
fn format_in(windows: Bool, parts: PathParts) String:
	directory := if parts.directory.is_empty(): parts.root.clone() else: parts.directory.clone()
	var base = parts.base.clone()

	if base.is_empty():
		extension := parts.extension

		if not extension.is_empty() and not extension.starts_with("."):
			base = f"{parts.name}.{extension}"
		else:
			base = f"{parts.name}{extension}"

	if directory.is_empty(): return base
	if directory == parts.root: return f"{directory}{base}"

	return f"{directory}{native(windows, "/")}{base}"

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
	if resolved == null: return text.clone()

	value := resolved
	if value.starts_with("\\\\"): return f"\\\\?\\UNC\\{value.view(2, value.length())}"

	return f"\\\\?\\{value}"

fn glob_in(windows: Bool, path: String, pattern: String) Bool!:
	glob := msstd_path_compile_glob(windows, pattern)?
	return msstd_path_glob_matches(glob, path)

// Returns path operations using POSIX separators and parsing rules.
export fn posix() PathOperations:
	return Dialect(windows: false)

// Returns path operations using Windows separators and parsing rules.
export fn win32() PathOperations:
	return Dialect(windows: true)

// Returns the final path component, excluding trailing separators.
export fn basename(path: String) String:
	return basename_in(host_windows(), path)

// Returns the basename with `suffix` removed when it matches exactly. A suffix equal to
// the whole basename is not removed.
export fn basename_without(path: String, suffix: String) String:
	return basename_without_in(host_windows(), path, suffix)

// Returns the directory portion of a path, or `.` when it has null.
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

// Returns the final component without its extension: `stem("a/b.tar.gz")` is `"b.tar"`
// and a dotfile such as `.bashrc` keeps its whole name.
export fn stem(path: String) String:
	return parse(path).name

// Replaces the final extension, or adds one when there is null, keeping the directory:
// `with_extension("a/b.txt", "md")` is `"a/b.md"`. A leading dot in `extension` is
// optional and an empty `extension` removes the current one. A path with no final
// component, such as `"/"`, comes back unchanged.
export fn with_extension(path: String, extension: String) String:
	parts := parse(path)
	if parts.name.is_empty(): return path.clone()

	return format(
		PathParts(
			root: parts.root.clone(),
			directory: parts.directory.clone(),
			base: "",
			extension: extension.clone(),
			name: parts.name.clone(),
		)
	)

// Returns the host's path separator.
export fn separator() String:
	return if host_windows(): "\\" else: "/"

// Returns the host's path-list delimiter.
export fn delimiter() String:
	return if host_windows(): ";" else: ":"

// On Windows, returns the `\\?\` namespaced form of an absolute path; elsewhere, and
// for other paths, returns the path unchanged.
export fn to_namespaced_path(path: String) String:
	return namespaced_in(host_windows(), path)

// Tests a path against a glob pattern. To test many paths against one pattern, compile
// it once with `compile_glob`.
export fn matches_glob(path: String, pattern: String) Bool!:
	return glob_in(host_windows(), path, pattern)

// A compiled glob pattern that can be reused across paths. It matches `*`, `?`, `[...]`
// classes, `{a,b}` and `{1..3}` braces, `@(..)`, `+(..)`, `?(..)`, `!(..)` and `*(..)`
// groups, and `**` segments, as `matches_glob` does.
export extern type Glob

// Tests one lexical path against the compiled pattern; a path with a NUL byte returns
// EINVAL.
fn Glob.matches(path: String) Bool!:
	return msstd_path_glob_matches(self, path)

// Compiles a glob pattern under the host path rules. Malformed patterns return EINVAL.
export fn compile_glob(pattern: String) Glob!:
	return msstd_path_compile_glob(host_windows(), pattern)
