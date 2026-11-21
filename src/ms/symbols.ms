// The runtime signature table: `crates/ms-lower/rt_symbols.txt` and the C lowering's
// `src/compiler/src/rt_ops_data.inc`, generated from the `/* ms-sig: ... */` comments above the
// prototypes in `src/runtime/include/ms_rt/*.h`, and the check that
// `src/runtime/symbols/<module>.txt`, the headers and those comments agree. Run from the
// repository root:
//
//   ms run src/ms/symbols.ms             write both files
//   ms run src/ms/symbols.ms -- --check  fail when either is stale
import (
	Command, Flag, FlagKind, Matches from "@std/cli/command.ms",
	stdout from "@std/io/io.ms",
	exists, list, read_file, write_file from "@std/os/fs.ms",
	expect_equal from "@std/test/test.ms",

	run_tool from "./cli.ms",
)

TABLE_PATH := "crates/ms-lower/rt_symbols.txt"
OPS_PATH := "src/compiler/src/rt_ops_data.inc"
STATUS_PATH := "src/compiler/src/status_rows_data.inc"
STDLIB_DIR := "src/stdlib"
HEADER_DIR := "src/runtime/include/ms_rt"
SYMBOLS_DIR := "src/runtime/symbols"

// One `ms-sig` comment: the function, its signature text, and the flags after `@`.
type Signature:
	name: String
	line: String
	flags: List[String]

fn read_text(path: String) String!:
	data := read_file(path).wait()?
	return ok(data.decode_utf8().get_or(""))

// Names in `dir` ending in `extension`, sorted.
fn names_with(dir: String, extension: String) List[String]!:
	var found = List[String]()
	for entry in list(dir)?:
		if entry.name.ends_with(extension): found.append(entry.name.clone())
	return ok(found.sorted())

fn before(text: String, separator: String) String:
	if parts := text.split_once(separator): return parts.before.clone()
	return text.clone()

fn after(text: String, separator: String) String:
	if parts := text.split_once(separator): return parts.after.clone()
	return ""

// ---- Headers ----

fn domain_of(text: String) String?:
	for line in text.split("\n"):
		trimmed := line.trim()
		rest := trimmed.cut_prefix("/* ms: domain ")
		if rest.is_none(): continue

		body := rest.get().cut_suffix("*/")
		if body.is_some(): return body.get().trim()

	return none

// The `ms-sig` lines of one header, with the file's domain on those that name none.
fn parse_header(text: String) List[Signature]:
	domain := domain_of(text)
	var found = List[Signature]()

	for line in text.split("\n"):
		rest := line.trim().cut_prefix("/* ms-sig: ")
		if rest.is_none(): continue

		body := rest.get().cut_suffix("*/")
		if body.is_none(): continue

		parts := body.get().trim().split(" @")
		base := parts[0].trim()
		var flags = List[String]()
		for flag in parts.drop(1): flags.append(flag.trim())
		if domain.is_some() and not flags.any(fn flag: flag.starts_with("domain=")):
			flags.append(f"domain={domain.get()}")
		found.append(Signature(name: before(base, "("), line: base, flags: flags))

	return found

// ---- Kinds of ABI types ----

// True when `word` is one of the identifier-like tokens of `text`.
fn has_word(text: String, word: String) Bool:
	var token = ""

	for c in text.chars():
		if is_word_char(c):
			token = token.concat(c)
			continue

		if token == word: return true

		token = ""

	return token == word

fn is_word_char(c: String) Bool:
	return (
		(c >= "a" and c <= "z")
		or (c >= "A" and c <= "Z")
		or (c >= "0" and c <= "9")
		or c == "_"
	)

ROLE_ALIASES := [
	"ElemDesc", "KeyDesc", "ValDesc", "ValueDesc", "CmpFn", "MsCompareFn", "RunDrop",
	"MsDropRun", "RunCopy", "MsSlotCopyRun", "JsonCtorFn", "JsonViewFn", "ErrSlot",
	"CleanupFn", "MsCleanupFn", "Entry", "MsAbiEntry", "MainFn", "MsMainFn",
	"MsGuardFn", "MsExitHook", "ExitHook", "MsGrowFn"
]
SCALARS := [
	["i64", "int64_t"],
	["u64", "uint64_t"],
	["i32", "int32_t"],
	["i32", "int"],
	["u32", "uint32_t"],
	["u8", "uint8_t"],
	["usize", "size_t"],
	["f64", "double"],
	["bool", "bool"],
]

// The scalar kind of a Rust parameter type or a C declaration (`ptr` for any pointer),
// so the two spellings compare.
fn abi_kind(input: String) String:
	text := input.trim()
	if text.contains("*") or text.contains("fn("): return "ptr"

	var last = text.clone()
	if parts := text.rsplit_once(":"): last = parts.after.trim()
	if last == "ErrSlot": return "ptr"
	if last == "HasRaw": return "u8"

	for alias in ROLE_ALIASES:
		if has_word(text, alias): return "ptr"
	if has_word(text, "HasRaw"): return "u8"

	for pair in SCALARS:
		if has_word(text, pair[0]) or has_word(text, pair[1]): return pair[0].clone()
	return text.clone()

// Splits at the commas outside angle brackets and parentheses; the `>` of `->` closes
// nothing.
fn split_top_level(params: String) List[String]:
	var parts = List[String]()
	var depth = 0
	var current = ""
	var previous = ""

	for c in params.chars():
		if c == "<" or c == "(": depth += 1
		else if c == ")" or (c == ">" and previous != "-"):
			if depth > 0: depth -= 1

		if c == "," and depth == 0:
			parts.append(current.clone())
			current = ""
		else: current = current.concat(c)

		previous = c.clone()

	parts.append(current)
	return parts

type Prototype:
	params: List[String]
	result: String

// The `msrt_*`/`msstd_*` prototypes of a module header, by name.
fn c_prototypes(header: String) Map[String, Prototype]:
	var declared = Map[String, Prototype]()

	for line in header.split("\n"):
		opened := line.split_once("(")
		if opened.is_none(): continue

		closed := opened.get().after.split_once(")")
		if closed.is_none(): continue

		head := opened.get().before.trim()
		var split_at = -1
		var at = 0

		for c in head.chars():
			if c == " " or c == "\t" or c == "*": split_at = at
			at += c.length()

		if split_at < 0: continue

		ret := head.slice(0, split_at)
		name := head.slice(split_at + 1, head.length())
		if closed.get().after.trim() != ";": continue
		if not name.starts_with("msrt_") and not name.starts_with("msstd_"): continue

		clean := ret.replace("MS_NORETURN", "").replace("MS_NODISCARD", "")
		result := (if head.contains("*"): "ptr" else: abi_kind(clean))
		var params = List[String]()

		for p in closed.get().before.split(","):
			trimmed := p.trim()
			if trimmed.is_empty() or trimmed == "void": continue

			params.append(abi_kind(trimmed))

		declared.add(name, Prototype(params: params, result: result))

	return declared

// ---- The table ----

HEADER_COMMENT := "# Generated by `ms run src/ms/symbols.ms`; do not edit. One line per exported runtime function:\n# `name(param: type, ..) -> ret`, the C signature lowering marshals runtime calls from, then the\n# flags the source declares with a `// ms: leaf pure fresh` comment above the function:\n# `@leaf` never reaches a cancellation point, `@pure` only reads memory and cannot fault,\n# `@fresh` returns a value that borrows none of its arguments, `@keeps:<param>` stores that\n# function value, `@takes:<param>` takes ownership of that value, `@spawns` starts a task\n# running program code, `@takes_self` has a `<name>_take` twin that reuses its first\n# argument when it dies at the call, `@inline` has no C body and is lowered as MIR, `@fallback` returns the receiver's payload or its argument when it has none, `@op=<mnemonic>` is exactly that MIR instruction on\n# its arguments, `@seq=<steps>` is the short MIR instruction sequence the steps list, `@domain=<words>` names its failures' domain, and `@view_of=<sym>`,\n# `@shared_view_of=<sym>`, `@first_of=<sym>`, `@iter_of=<sym>` declare the function as the\n# borrowing twin of `<sym>` (a lent result, the first element, a one-at-a-time walk).\n"

type Table:
	lines: Map[String, String]
	flags: Map[String, List[String]]

fn header_table() Table!:
	var table = Table(lines: Map[String, String](), flags: Map[String, List[String]]())

	for name in names_with(HEADER_DIR, ".h")?:
		text := read_text(f"{HEADER_DIR}/{name}")?

		for sig in parse_header(text):
			if old := table.lines.get(sig.name):
				if old != sig.line: return error(
					Error(
						f"{sig.name} has two signatures: `{old}` and `{sig.line}` (src/runtime/include/ms_rt headers)"
					)
				)
			table.lines.add(sig.name.clone(), sig.line.clone())

			var flags = table.flags.get(sig.name).get_or([])
			flags.extend(sig.flags)
			table.flags.add(sig.name.clone(), flags)

	return ok(table)

fn rt_symbols_text(table: Table) String!:
	for name in table.flags.keys().sorted():
		if not table.lines.contains(name): return error(
			Error(
				f"`// ms:` flags on {name}, which is not a runtime function"
			)
		)

	var out = HEADER_COMMENT.clone()

	for name in table.lines.keys().sorted():
		out = out.concat(table.lines.get_or(name, ""))

		found := table.flags.get(name).get_or([])
		for flag in found.sorted().distinct():
			out = out.concat(f" @{flag}")
		out = out.concat("\n")

	return ok(out)

// ---- The C lowering's table ----

TWIN_KEYS := ["view_of=", "shared_view_of=", "first_of=", "iter_of="]

// The value of a `@key=value` flag of `text`, trimmed up to the next ` @`, none when
// absent.
fn flag_value(text: String, key: String) String?:
	for flag in text.split(" @").drop(1):
		if value := flag.cut_prefix(key): return value.trim()
	return none

// The runtime's value records: a user type whose fields the runtime reads or fills in
// as a C struct.
fn is_value_record(name: String) Bool:
	return name == "Instant" or name == "Timestamp" or name == "DecType"

fn param_kind(at: Int, p: String) String:
	parts := p.split_once(":")
	pname := (if parts.is_some(): parts.get().before.trim() else: "")
	ty := (if parts.is_some(): parts.get().after.trim() else: "")
	if ty == "*const VecVal": return "MS_RT_LIST"
	if ty == "*mut VecVal" and pname == "out": return "MS_RT_OUT_LIST"
	if ty == "*mut VecVal" and at == 0: return "MS_RT_LIST_VAR"
	if ty == "*const AltVal": return "MS_RT_ALT"
	if ty == "*const StrVal": return "MS_RT_STR"
	if ty == "*mut StrVal" and pname == "out": return "MS_RT_OUT_STR"
	if (
		(
			ty == "*mut i64"
			or ty == "*mut f64"
			or ty == "*mut u8"
			or ty == "*mut u64"
		)
		and pname == "out"
	): return "MS_RT_OUT_SCALAR"
	if ty == "ElemDesc": return "MS_RT_DESC"
	if ty == "*const MapVal": return "MS_RT_MAP"
	if ty == "KeyDesc": return "MS_RT_KEY_DESC"
	if ty == "ValDesc": return "MS_RT_VAL_DESC"
	if ty == "HasRaw": return "MS_RT_HAS"
	if ty == "ErrSlot": return "MS_RT_ERR"
	if (
		ty.starts_with("*mut ")
		and (ty.ends_with("Out") or is_value_record(ty.replace("*mut ", "")))
		and ty != "*mut InfoOut"
		and pname == "out"
	): return "MS_RT_OUT_RECORD"
	if ty.starts_with("*const ") and is_value_record(ty.replace("*const ", "")): return "MS_RT_RECORD"
	if ty.starts_with("*mut *mut ObjCell<") and pname == "out": return "MS_RT_OUT_HANDLE"
	if (
		(ty.starts_with("*const ObjCell<") or ty.starts_with("*mut ObjCell<"))
		and pname.starts_with("handle ")
	): return "MS_RT_HANDLE"
	if ty == "*const u8" and pname == "key": return "MS_RT_KEY_REF"
	if ty == "*const u8": return "MS_RT_ELEMENT"
	if ty == "i64": return "MS_RT_INT"
	if ty == "f64": return "MS_RT_FLOAT"
	if ty == "u64": return "MS_RT_UINT64"
	if ty == "u8" or ty == "bool": return "MS_RT_BOOL"

	return "MS_RT_OTHER"

fn result_kind(text: String) String:
	if text == "-> i64": return "MS_RT_RET_INT"
	if text == "-> f64": return "MS_RT_RET_FLOAT"
	if text == "-> u8": return "MS_RT_RET_BOOL"
	if text.starts_with("-> *mut ObjCell<"): return "MS_RT_RET_HANDLE"
	if text.is_empty(): return "MS_RT_RET_VOID"

	return "MS_RT_RET_OTHER"

// The name of the first line one of whose flags is `key=<name>`.
fn twin_of(lines: List[String], key: String, name: String) String:
	for line in lines:
		for flag in line.split(" @"):
			value := flag.cut_prefix(key)
			if value.is_some() and value.get().trim() == name: return before(line, "(")

	return ""

fn rt_ops_text(symbols: String) String:
	lines := symbols.split("\n")
	var out = "/* Generated by `ms run src/ms/symbols.ms` from crates/ms-lower/rt_symbols.txt; do not edit. */\nstatic const MsRtFn rt_fns[] = {\n"

	// A function with a borrowing twin can lend or reuse; lowering must pick the twin
	// there.
	var twinned = Set[String]()

	// The `@view_of=` twin of each function that has one: the call whose result borrows
	// its receiver.
	var views = Map[String, String]()

	// A function declared the implementation of a method whose own name another
	// function has (`@method=List.drop`: `msrt_list_drop` releases a list).
	var methods = ""

	for line in lines:
		for flag in line.split(" @").drop(1):
			for key in TWIN_KEYS:
				if value := flag.cut_prefix(key):
					twinned.add(value.trim())
					break

			if base := flag.cut_prefix("view_of="):
				views.add(base.trim(), line.split("(").get(0).trim())

	for line in lines:
		if line.starts_with("#"): continue

		opened := line.split_once("(")
		if opened.is_none(): continue

		closed := opened.get().after.split_once(")")
		if closed.is_none(): continue

		name := opened.get().before.clone()
		params := closed.get().before.clone()
		rest := closed.get().after.clone()
		var op = ""
		if value := flag_value(rest, "op="): op = before(value, " ")

		ret := result_kind(before(rest, " @").trim())
		var kinds = List[String]()
		var at = 0

		for p in params.split(","):
			if p.trim().is_empty(): continue

			kinds.append(param_kind(at, p))
			at += 1

		if kinds.length() > 8: continue

		var imm: Int? = none
		if value := flag_value(rest, "imm="): imm = before(value, " ").parse_int()

		var seq = ""
		if value := flag_value(rest, "seq="): seq = before(value, " ")

		word_key := twin_of(lines, "word_key_of=", name)
		text_key := twin_of(lines, "text_key_of=", name)
		leaf := rest.contains(" @leaf")
		pure := rest.contains(" @pure")
		fresh := rest.contains(" @fresh")
		borrows := rest.contains(" @borrows")
		has_imm := imm.is_some()
		imm_value := imm.get_or(0)
		domain := flag_value(rest, "domain=").get_or("")
		if value := flag_value(rest, "method="):
			methods = methods.concat(f"    \{\"{before(value, " ")}\", \"{name}\"\},\n")

		fallback := rest.contains(" @fallback")
		out = out.concat(
			f"    \{\"{name}\", \"{op}\", \"{word_key}\", \"{text_key}\", \"{seq}\", {imm_value}, {kinds.length()}, {ret}, \{{kinds.join(", ")}\}, {leaf}, {twinned.contains(name)}, {pure}, {fresh}, {borrows}, {has_imm}, {fallback}, \"{domain}\", \"{views.get_or(name, "")}\"\},\n"
		)

	return (
		out
		.concat("};\nstatic const MsRtMethod rt_methods[] = {\n")
		.concat(methods)
		.concat("};\n")
	)

// ---- The status rows ----

// Every `.ms` file under `dir`, sorted.
fn stdlib_files(dir: String) List[String]!:
	var found = List[String]()

	for entry in list(dir)?:
		path := f"{dir}/{entry.name}"

		if entry.directory: found.extend(stdlib_files(path)?)
		else if entry.name.ends_with(".ms"): found.append(path)

	return ok(found.sorted())

// The error kind and words of each runtime status (`// ms: status <n> <kind> <words>`
// in the standard library) and the per-extern wording of a status
// (`// ms: words <n> <words>` covering the externs a file declares or lists with
// `// ms: native`), the tables `ms_rt_status_rows` merges for the C lowering.
fn status_rows_text() String!:
	var rows = Map[Int, String]()
	var words = List[String]()

	for path in stdlib_files(STDLIB_DIR)?:
		var local = List[List[String]]()
		var externs = List[String]()

		for raw in read_text(path)?.split("\n"):
			if rest := raw.cut_prefix("// ms: status "):
				parts := rest.split(" ")
				if parts.length() < 3: return error(
					Error(f"{path}: malformed status row: {raw}")
				)

				text := parts.drop(2).join(" ")
				number := parts[0].parse_int()
				if number.is_none(): return error(
					Error(f"{path}: malformed status row: {raw}")
				)

				rows.add(
					number.get(),
					f"    \{{parts[0]}, \"{parts[1]}\", \"{text}\"\},\n",
				)
			else if rest := raw.cut_prefix("// ms: words "):
				if split := rest.split_once(" "): local.append(
					[split.before.clone(), split.after.clone()]
				)
				else: return error(Error(f"{path}: malformed words row: {raw}"))
			else if rest := raw.cut_prefix("// ms: native "):
				externs.extend(rest.split(" "))
			else if rest := raw.cut_prefix("export extern fn "): externs.append(
				before(rest, "(")
			)
			else if rest := raw.cut_prefix("extern fn "): externs.append(
				before(rest, "(")
			)

		for sym in externs:
			for row in local:
				words.append(f"    \{\"{sym}\", {row[0]}, \"{row[1]}\"\},\n")

	var out = "/* Generated by `ms run src/ms/symbols.ms` from the `// ms: status` and `// ms: words` rows of src/stdlib/; do not edit. */\nstatic const MsStatusRow status_rows[] = {\n"
	for number in rows.keys().sorted(): out = out.concat(rows.get_or(number, ""))
	out = out.concat("};\nstatic const MsStatusWords status_words[] = {\n")
	out = out.concat(words.sorted().join(""))
	return ok(out.concat("};\n"))

// ---- The check that the headers and the symbol lists agree ----

// The parameter kinds and result kind of a recorded signature line.
fn recorded(name: String, line: String) Prototype!:
	opened := line.split_once("(")
	if opened.is_none(): return error(Error(f"{name}: unreadable signature `{line}`"))

	closed := opened.get().after.rsplit_once(")")
	if closed.is_none(): return error(Error(f"{name}: unreadable signature `{line}`"))

	var ret = "()"
	if arrow := closed.get().after.trim().cut_prefix("->"): ret = arrow.trim()

	var params = List[String]()

	for p in split_top_level(closed.get().before):
		if p.trim().is_empty(): continue

		if typed := p.split_once(":"): params.append(abi_kind(typed.after))
		else: params.append(abi_kind(p))

	result := (if ret == "()" or ret == "!": "void" else: abi_kind(ret))
	return ok(Prototype(params: params, result: result))

fn symbols_listed(text: String) Set[String]:
	var listed = Set[String]()

	for raw in text.split("\n"):
		line := raw.trim()
		if line.is_empty() or line.starts_with("#"): continue

		listed.add(line)

	return listed

fn check_c_abi(table: Table) Void!:
	var seen = Set[String]()

	for file in names_with(SYMBOLS_DIR, ".txt")?:
		module := file.slice(0, file.length() - 4)
		listed := symbols_listed(read_text(f"{SYMBOLS_DIR}/{file}")?)
		declared := c_prototypes(read_text(f"{HEADER_DIR}/{module}.h")?)

		for name in listed.values().sorted():
			if seen.contains(name): return error(
				Error(
					f"{name} is listed in two src/runtime/symbols files"
				)
			)

			seen.add(name.clone())

			// `ms_sys_*` is the runtime's own door to the OS and `ms_*_v1` the versioned ABI of
			// user extern shims: neither is a native, so neither has a recorded
			// signature.
			if name.starts_with("ms_sys_") or name.ends_with("_v1"): continue

			proto := declared.get(name)
			if proto.is_none(): return error(
				Error(
					f"{name} is in src/runtime/symbols/{module}.txt but not declared in ms_rt/{module}.h"
				)
			)

			line := table.lines.get(name)
			if line.is_none(): return error(
				Error(
					f"{name} is in src/runtime/symbols/{module}.txt but not a runtime function"
				)
			)

			want := recorded(name, line.get())?
			have := proto.get()
			if want.params != have.params or want.result != have.result: return error(
				Error(
					f"{name}: ms_rt/{module}.h says ({have.params.join(", ")}) -> {have.result}, the runtime signature is ({want.params.join(", ")}) -> {want.result}"
				)
			)

		for name in declared.keys().sorted():
			// `@inline` has no C body: the lowering writes it out as MIR, for a value whose layout the runtime does not know.
			bodyless := table.flags.get(name).get_or([]).contains("inline")
			if not listed.contains(name) and not bodyless: return error(
				Error(
					f"{name} is declared in ms_rt/{module}.h but not in src/runtime/symbols/{module}.txt"
				)
			)

	for header in names_with(HEADER_DIR, ".h")?:
		module := header.slice(0, header.length() - 2)
		if ["base", "runtime", "safe", "chars", "array"].contains(module): continue
		if not exists(f"{SYMBOLS_DIR}/{module}.txt")?: return error(
			Error(
				f"ms_rt/{module}.h has no src/runtime/symbols/{module}.txt"
			)
		)

	return ok()

// ---- Entry ----

// Writes or checks both generated files; the message names what happened.
// ms: allow_effect std.fs.read
// ms: allow_effect std.fs.write
fn generate(check: Bool) String!:
	header := header_table()?
	text := rt_symbols_text(header)?
	check_c_abi(header)?

	ops := rt_ops_text(text)
	status := status_rows_text()?
	count := header.lines.length()

	if check:
		for pair in [[TABLE_PATH, text], [OPS_PATH, ops], [STATUS_PATH, status]]:
			have := read_text(pair[0]).get_or("")
			if have != pair[1]: return error(
				Error(
					f"{pair[0]} is stale; run ms run src/ms/symbols.ms"
				)
			)

		return ok(f"{TABLE_PATH} is current ({count} symbols)")

	write_file(OPS_PATH, ops, replace: true).wait()?
	write_file(STATUS_PATH, status, replace: true).wait()?
	write_file(TABLE_PATH, text, replace: true).wait()?
	return ok(f"wrote {TABLE_PATH} ({count} symbols)")

fn symbols_tool() Command:
	return Command(
		name: "symbols.ms",
		about: "Write or check the runtime signature tables",
		flags: [
			Flag(
				"check",
				FlagKind.Bool,
				help: "Fail when a generated file is stale instead of writing it",
			)
		],
	)

fn print_result(m: Matches) Void!:
	done := generate(m.bool("check"))?
	stdout().write(done + "\n")?
	return ok()

// ms: allow_effect std.env.read
// ms: allow_effect std.fs.read
// ms: allow_effect std.fs.write
// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Int:
	return run_tool(symbols_tool(), print_result)

test "a header signature carries its flags and the file's domain":
	header := "/* ms: domain demo */\n/* ms-sig: msstd_demo_one(handle h: *const ObjCell<X>, err: ErrSlot) -> u8 @leaf */\nuint8_t msstd_demo_one(void *h, void *err);\n/* ms-sig: msstd_demo_two() -> i64 @domain=other */\n"
	found := parse_header(header)
	expect_equal(found.length(), 2)?
	expect_equal(found[0].name, "msstd_demo_one")?
	expect_equal(
		found[0].line,
		"msstd_demo_one(handle h: *const ObjCell<X>, err: ErrSlot) -> u8",
	)?
	expect_equal(found[0].flags, ["leaf", "domain=demo"])?
	expect_equal(found[1].flags, ["domain=other"])?

test "wrapper types compare with their C kinds":
	expect_equal(abi_kind("err: ErrSlot"), abi_kind("void *err"))?
	expect_equal(abi_kind("raw: HasRaw"), abi_kind("uint8_t raw"))?

test "a generic parameter is one parameter":
	parts := split_top_level("a: FrameBuf<StrVal, 8>, b: i64")
	expect_equal(parts.length(), 2)?
