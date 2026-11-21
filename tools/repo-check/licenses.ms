// The dependency license inventory: crate licenses from `cargo metadata` plus the
// hashes of the bundled notice files. `licenses` writes it; `licenses -check` fails
// when it is stale.
import (
	JsonValue, parse from "@std/data/json.ms",
	list, write_file from "@std/os/fs.ms",

	capture, file_sha256 from "../lib.ms",
	read_text from "./util.ms",
)

INVENTORY := "documentation/contributing/dependency-licenses.json"
NOTICE_ROOTS := ["website/themes/hugo-book", "skills"]
// The licenses of the C libraries folded into the runtime archives.
// `src/runtime/third_party/c-libs.lock` records the versions of all but llhttp and mimalloc, which
// are compiled by CMake from their vendored sources and listed below. Programs carry
// their members, so their notices belong in the inventory. Rows are `name license`.
C_LIBRARIES := [
	"curl curl", "libuv MIT", "llhttp MIT", "mimalloc MIT", "nghttp2 MIT",
	"openssl Apache-2.0", "pcre2 BSD-3-Clause", "zlib Zlib"
]
VENDORED_VERSIONS := ["llhttp 9.2.1", "mimalloc 3.7.0"]

// `name\tversion\tlicense` rows of the C libraries, versions from the lock file; an error text
// when one is missing.
fn c_library_rows() Result[List[String], Error]:
	lock := "src/runtime/third_party/c-libs.lock"
	text := read_text(lock).ok_or(Error(f"{lock}: cannot read"))?
	var rows = List[String]()

	for row in C_LIBRARIES:
		parts := row.split(" ")
		name := parts[0].clone()
		var version = ""

		for line in text.lines():
			words := line.fields()

			if words.length() > 1 and words[0] == name:
				version = words[1].clone()
				break

		if version.is_empty():
			for vendored in VENDORED_VERSIONS:
				if vendored.starts_with(name + " "): version = (
					vendored
					.split(" ")[1]
					.clone()
				)
		if version.is_empty(): return error(Error(f"{lock}: no version of {name}"))

		rows.append(f"{name}\t{version}\t{parts[1]}")

	return ok(rows)

// A JSON string with Go's HTML-safe escapes, the form the inventory has always had.
fn quoted(text: String) String:
	var out = "\""

	for char in text.chars():
		if char == "\"": out += "\\\""
		else if char == "\\": out += "\\\\"
		else if char == "<": out += "\\u003c"
		else if char == ">": out += "\\u003e"
		else if char == "&": out += "\\u0026"
		else if char == "\n": out += "\\n"
		else if char == "\t": out += "\\t"
		else: out += char

	return out + "\""

// `name\tversion\tlicense` rows sorted as the (name, version, license) triples they stand for:
// the tab sorts below every character a crate name or version holds.
fn crate_rows() Result[List[String], Error]:
	metadata := capture("cargo", ["metadata", "--locked", "--format-version", "1"])
	if metadata.is_empty(): return error(Error("cargo metadata failed"))

	doc := parse(metadata)?
	packages := doc.get(
		"packages"
	).ok_or(
		Error("cargo metadata: no packages")
	)?.as_list().ok_or(Error("cargo metadata: no packages"))?
	var rows = List[String]()

	for package in packages:
		manifest := package.get("manifest_path").get_or(
			JsonValue.Null
		).as_string().get_or("")
		vendored := manifest.contains("/vendor/")
		source := package.get("source").get_or(JsonValue.Null)
		if source.is_null() and not vendored: continue

		license := package.get("license").get_or(JsonValue.Null).as_string().get_or("")
		name := package.get("name").get_or(JsonValue.Null).as_string().get_or("")
		version := package.get("version").get_or(JsonValue.Null).as_string().get_or("")
		shown := if license.is_empty(): "UNKNOWN" else: license
		rows.append(f"{name}\t{version}\t{shown}")

	rows.sort()
	return ok(rows)

// Notice files (LICENSE, COPYING, PATENTS) under `dir`, as `path\tsha256` rows.
fn collect_notices(dir: String, var rows: List[String]) Void:
	entries := list(dir).get_or([])

	for entry in entries:
		path := f"{dir}/{entry.name}"

		if entry.directory:
			collect_notices(path, rows)
			continue

		upper := entry.name.upper()
		if (
			upper.starts_with("LICENSE")
			or upper.starts_with("COPYING")
			or upper.starts_with("PATENTS")
		):
			rows.append(f"{path}\t{file_sha256(path)}")

// A JSON array of objects: `rows` are tab-separated, one value per key.
fn objects(rows: List[String], keys: List[String]) String:
	var out = ""

	for at in 0..rows.length():
		parts := rows[at].split("\t")
		if at > 0: out += ",\n"
		out += "    {\n"

		for k in 0..keys.length():
			if k > 0: out += ",\n"
			out += "      " + quoted(keys[k]) + ": " + quoted(parts[k])

		out += "\n    }"

	return out

fn array(name: String, rows: List[String], keys: List[String], last: Bool) String:
	tail := if last: "" else: ","
	if rows.is_empty(): return "  " + quoted(name) + ": []" + tail + "\n"

	return "  " + quoted(name) + ": [\n" + objects(rows, keys) + "\n  ]" + tail + "\n"

fn document(
	crates: List[String],
	c_libraries: List[String],
	notices: List[String],
) String:
	version_keys := ["name", "version", "license"]
	return (
		"{\n"
		+ array("crates", crates, version_keys, false)
		+ array("c_libraries", c_libraries, version_keys, false)
		+ array("notices", notices, ["path", "sha256"], true)
		+ "}\n"
	)

// Writes the inventory, or with `check` compares it. Returns an error message, "" on
// success.
export fn licenses(check: Bool) String:
	crates := crate_rows()
	if crates.is_error(): return crates.err().message

	var notices = List[String]()
	for root in NOTICE_ROOTS: collect_notices(root, notices)
	notices.sort()

	c_libraries := c_library_rows()
	if c_libraries.is_error(): return c_libraries.err().message

	text := document(crates.get(), c_libraries.get(), notices)

	if check:
		actual := read_text(INVENTORY).get_or("")
		if actual != text: return "dependency notices changed; run make licenses"

		return ""

	if _written := write_file(INVENTORY, text, replace: true).wait(): return ""

	return f"{INVENTORY}: cannot write"
