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

fn document(crates: List[String], notices: List[String]) String:
	var out = "{\n  \"crates\": [\n"
	var first = true

	for row in crates:
		parts := row.split("\t")
		if not first: out += ",\n"
		first = false
		out += (
			"    {\n      \"name\": "
			+ quoted(parts[0])
			+ ",\n      \"version\": "
			+ quoted(parts[1])
		)
		out += ",\n      \"license\": " + quoted(parts[2]) + "\n    }"

	out += "\n  ],\n  \"notices\": ["

	if notices.is_empty():
		out += "]\n}\n"
		return out

	out += "\n"
	first = true

	for row in notices:
		parts := row.split("\t")
		if not first: out += ",\n"
		first = false
		out += (
			"    {\n      \"path\": "
			+ quoted(parts[0])
			+ ",\n      \"sha256\": "
			+ quoted(parts[1])
			+ "\n    }"
		)

	return out + "\n  ]\n}\n"

// Writes the inventory, or with `check` compares it. Returns an error message, "" on
// success.
export fn licenses(check: Bool) String:
	crates := crate_rows()
	if crates.is_error(): return crates.err().message

	var notices = List[String]()
	for root in NOTICE_ROOTS: collect_notices(root, notices)
	notices.sort()

	text := document(crates.get(), notices)

	if check:
		actual := read_text(INVENTORY).get_or("")
		if actual != text: return "dependency notices changed; run make licenses"

		return ""

	if _written := write_file(INVENTORY, text, replace: true).wait(): return ""

	return f"{INVENTORY}: cannot write"
