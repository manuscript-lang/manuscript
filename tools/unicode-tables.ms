// Writes the Unicode tables the C runtime reads (src/runtime/core/unicode_tables.c and
// .h):
//   ms run tools/unicode-tables.ms -- <ucd-directory> c > src/runtime/core/unicode_tables.c
//   ms run tools/unicode-tables.ms -- <ucd-directory> h > src/runtime/core/unicode_tables.h
// The directory holds the pinned Unicode Character Database files UnicodeData.txt,
// SpecialCasing.txt, DerivedNormalizationProps.txt and DerivedCoreProperties.txt of one
// release (https://www.unicode.org/Public/<version>/ucd/); the release number is read
// from the header line of DerivedNormalizationProps.txt and written into the output.
// `make repo-check` does not run it; run it when the release changes and commit both
// files. src/runtime/tests/core_unicode.c fails when a table entry is wrong.
//
// Layout: every scalar value maps through a three-level trie to a record. Normalization
// records say the combining class, the quick-check bits and where the full canonical
// and compatibility decompositions sit in a pool of UTF-16 units (Hangul is algorithmic
// and has no entry). Case records give the lowercase and uppercase mapping as a delta,
// or a pool offset for the full mappings of SpecialCasing, and the Cased and
// Case_Ignorable bits.
import (
	arguments from "@std/os/env.ms",
	read_file from "@std/os/fs.ms",
)

TOTAL := 1114112
MID_BITS := 9
LEAF_BITS := 4
// The flag bits of a normalization record above the combining class (bits 8 and up).
FLAG_NFD := 1
FLAG_NFKD := 2
FLAG_NFC := 4
FLAG_NFKC := 8
FLAG_COMP_FIRST := 16
FLAG_COMP_SECOND := 32
CASE_SPECIAL := 1073741824

// `flags` with `bit` (a power of two) set.
fn with_bit(flags: Int, bit: Int) Int:
	if flags / bit % 2 == 1: return flags
	return flags + bit

fn pow2(n: Int) Int:
	var out = 1
	for _i in 0..n: out *= 2
	return out

fn hex(text: String) Int:
	var value = 0

	for c in text.trim().scalar_values():
		var digit = c - 48

		if c >= 97: digit = c - 87
		else if c >= 65: digit = c - 55

		value = value * 16 + digit

	return value

fn hex_list(text: String) List[Int]:
	return text.fields() | .map(hex)

fn load(directory: String, name: String) String!:
	bytes := read_file(f"{directory}/{name}").wait()?
	return ok(bytes.decode_utf8().ok_or(Error(f"{name} is not UTF-8"))?)

// The range "0041..005A" or the single scalar "00C0" as a first and a last scalar.
fn range_of(text: String) List[Int]:
	parts := text.trim().split("..")
	first := hex(parts[0])
	if parts.length() == 1: return [first, first]

	return [first, hex(parts[1])]

// The data lines of a UCD file split into trimmed ";" fields, comments removed.
fn data_lines(text: String) List[List[String]]:
	var out = List[List[String]]()

	for line in text.lines():
		body := line.split("#")[0].trim()
		if body.is_empty(): continue

		out.append(body.split(";") | .map(fn f: f.trim()))

	return out

// The UTF-16 code units of the scalars.
fn utf16(scalars: List[Int]) List[Int]:
	var out = List[Int]()

	for c in scalars:
		if c >= 65536:
			rest := c - 65536
			out.append(55296 + rest / 1024)
			out.append(56320 + rest % 1024)
		else:
			out.append(c)

	return out

fn join_ints(values: List[Int]) String:
	return values.map(fn v: f"{v}").join(",")

type Pool:
	units: List[Int]
	seen: Map[String, Int]

// The offset of the units in the pool, added when no earlier entry has them.
fn pool_add(var pool: Pool, units: List[Int]) Int:
	key := join_ints(units)
	if at := pool.seen.get(key): return at

	at := pool.units.length()
	pool.units.extend(units)
	pool.seen.add(key, at)
	return at

type Trie:
	top: List[Int]
	mid: List[Int]
	leaf: List[Int]

// The three-level trie of `values`, one per scalar: `top` by scalar >> MID_BITS holds
// the index of a mid block, `mid` blocks by (scalar >> LEAF_BITS) & mask the index of a
// leaf block and `leaf` blocks by scalar & mask the value. Equal blocks are stored
// once.
fn build_trie(values: List[Int]) Trie:
	leaf_size := pow2(LEAF_BITS)
	mid_size := pow2(MID_BITS - LEAF_BITS)
	var leaves = List[Int]()
	var leaf_seen = Map[String, Int]()
	var leaf_of_block = List[Int]()

	for block in 0..TOTAL / leaf_size:
		key := join_ints(
			values.slice(block * leaf_size, (block + 1) * leaf_size).get_or(
				[]
			)
		)

		if at := leaf_seen.get(key):
			leaf_of_block.append(at)
		else:
			at := leaves.length() / leaf_size
			leaves.extend(
				values.slice(
					block * leaf_size,
					(block + 1) * leaf_size,
				).get_or([])
			)
			leaf_seen.add(key, at)
			leaf_of_block.append(at)

	var mids = List[Int]()
	var mid_seen = Map[String, Int]()
	var top = List[Int]()

	for group in 0..leaf_of_block.length() / mid_size:
		part := leaf_of_block.slice(group * mid_size, (group + 1) * mid_size).get_or([])
		key := join_ints(part)

		if at := mid_seen.get(key):
			top.append(at)
		else:
			at := mids.length() / mid_size
			mids.extend(part)
			mid_seen.add(key, at)
			top.append(at)

	return Trie(top, mids, leaves)

fn c_type(values: List[Int]) String:
	top := values.max().get_or(0)
	least := values.min().get_or(0)
	if least < 0: return "int32_t"
	if top < 256: return "uint8_t"
	if top < 65536: return "uint16_t"

	return "uint32_t"

fn type_size(ctype: String) Int:
	if ctype == "uint8_t": return 1
	if ctype == "uint16_t": return 2

	return 4

// A C array definition (`define`) or declaration of `values`, sixteen to a line.
fn print_array(name: String, ctype: String, values: List[Int], define: Bool) Void:
	count := values.length()

	if not define:
		print(f"extern const {ctype} {name}[{count}];")
		return

	print(f"const {ctype} {name}[{count}] = \{")

	var at = 0

	while at < count:
		end := (at + 16).min(count)
		print(
			f"    {values.slice(at, end).get_or([]) | .map(fn v: f"{v}") | .join(", ")},"
		)
		at = end

	print("};")

type Tables:
	norm: Trie
	records: List[List[Int]]
	pool: List[Int]
	comp_key: List[Int]
	comp_value: List[Int]
	case_trie: Trie
	case_records: List[List[Int]]
	case_pool: List[Int]

// Fully expanded canonical (or, with `compat`, compatibility) decomposition of `cp`.
fn expand(
	cp: Int,
	compat: Bool,
	canon: Map[Int, List[Int]],
	tagged: Map[Int, List[Int]],
) List[Int]:
	var out = List[Int]()

	if parts := canon.get(cp):
		for part in parts: out.extend(expand(part, compat, canon, tagged))
		return out

	if compat:
		if parts := tagged.get(cp):
			for part in parts: out.extend(expand(part, compat, canon, tagged))
			return out

	return [cp]

fn units_len(scalars: List[Int]) Int:
	return utf16(scalars).length()

fn build(directory: String) Tables!:
	data := load(directory, "UnicodeData.txt")?
	var ccc = [0].repeated(TOTAL)
	var canon = Map[Int, List[Int]]()
	var tagged = Map[Int, List[Int]]()
	var lower = Map[Int, Int]()
	var upper = Map[Int, Int]()

	for line in data.lines():
		if line.is_empty(): continue

		fields := line.split(";")
		cp := hex(fields[0])
		ccc[cp] = fields[3].parse_int().get_or(0)

		decomposition := fields[5]

		if decomposition.starts_with("<"):
			tagged.add(cp, hex_list(decomposition.split("> ")[1]))
		else if not decomposition.is_empty():
			canon.add(cp, hex_list(decomposition))

		if not fields[12].is_empty(): upper.add(cp, hex(fields[12]))
		if not fields[13].is_empty(): lower.add(cp, hex(fields[13]))

	// Quick-check bits and composition exclusions.
	var flags = [0].repeated(TOTAL)
	var excluded = Set[Int]()
	props := load(directory, "DerivedNormalizationProps.txt")?

	for fields in data_lines(props):
		name := fields[1]
		span := range_of(fields[0])
		var bit = 0

		if name == "NFD_QC": bit = FLAG_NFD
		else if name == "NFKD_QC": bit = FLAG_NFKD
		else if name == "NFC_QC": bit = FLAG_NFC
		else if name == "NFKC_QC": bit = FLAG_NFKC

		if bit > 0:
			for cp in span[0]..span[1] + 1: flags[cp] += bit
		if name == "Full_Composition_Exclusion":
			for cp in span[0]..span[1] + 1: excluded.add(cp)

	// Composition pairs: the two-scalar canonical decompositions that are not excluded.
	var pairs = List[List[Int]]()
	for entry in canon.entries():
		if entry.value.length() == 2 and not excluded.contains(entry.key):
			pairs.append([entry.value[0] * 2097152 + entry.value[1], entry.key])
	pairs.sort(fn a, b: a[0].compare(b[0]))

	var comp_key = List[Int]()
	var comp_value = List[Int]()

	for pair in pairs:
		comp_key.append(pair[0])
		comp_value.append(pair[1])

		first := pair[0] / 2097152
		second := pair[0] % 2097152
		flags[first] = with_bit(flags[first], FLAG_COMP_FIRST)
		flags[second] = with_bit(flags[second], FLAG_COMP_SECOND)

	// Hangul composes by arithmetic: leading consonants and LV syllables start a pair,
	// vowels and trailing consonants end one (a vowel also starts the LV pair).
	for cp in 4352..4371: flags[cp] = with_bit(flags[cp], FLAG_COMP_FIRST)

	for cp in 4449..4470:
		flags[cp] = with_bit(flags[cp], FLAG_COMP_FIRST)
		flags[cp] = with_bit(flags[cp], FLAG_COMP_SECOND)

	for cp in 4520..4547: flags[cp] = with_bit(flags[cp], FLAG_COMP_SECOND)

	for index in 0..11172:
		if index % 28 == 0:
			cp := 44032 + index
			flags[cp] = with_bit(flags[cp], FLAG_COMP_FIRST)

	// Normalization records: combining class and flags in `info`, the decomposition
	// pool offset, and the unit counts of the canonical and (when it differs)
	// compatibility one.
	var pool = Pool([], Map[String, Int]())
	var records = [[0, 0, 0]]
	var record_seen = Map[String, Int]()
	var record_of = [0].repeated(TOTAL)

	for cp in 0..TOTAL:
		info := ccc[cp] + flags[cp] * 256
		var decomposable = canon.contains(cp) or tagged.contains(cp)
		if info == 0 and not decomposable: continue

		var offset = 0
		var lens = 0

		if decomposable:
			full_canon := if canon.contains(cp): expand(cp, false, canon, tagged) else: [
				cp
			]
			full_compat := expand(cp, true, canon, tagged)
			canon_units := utf16(full_canon)
			compat_units := utf16(full_compat)

			if not canon.contains(cp):
				offset = pool_add(pool, compat_units)
				lens = compat_units.length() * 16
			else if full_canon == full_compat:
				offset = pool_add(pool, canon_units)
				lens = canon_units.length()
			else:
				joined := canon_units.concat(compat_units)
				offset = pool_add(pool, joined)
				lens = canon_units.length() + compat_units.length() * 16

		key := f"{info}:{offset}:{lens}"

		if at := record_seen.get(key):
			record_of[cp] = at
		else:
			at := records.length()
			records.append([info, offset, lens])
			record_seen.add(key, at)
			record_of[cp] = at

	// Case mapping: simple mappings from UnicodeData, the unconditional full mappings
	// of SpecialCasing over them, and the Cased and Case_Ignorable bits.
	var special_lower = Map[Int, List[Int]]()
	var special_upper = Map[Int, List[Int]]()
	special := load(directory, "SpecialCasing.txt")?

	for fields in data_lines(special):
		if fields.length() > 4 and not fields[4].is_empty(): continue

		cp := hex(fields[0])
		special_lower.add(cp, hex_list(fields[1]))
		special_upper.add(cp, hex_list(fields[3]))

	var case_flags = [0].repeated(TOTAL)
	core := load(directory, "DerivedCoreProperties.txt")?

	for fields in data_lines(core):
		var bit = 0

		if fields[1] == "Cased": bit = 1
		else if fields[1] == "Case_Ignorable": bit = 2

		if bit > 0:
			span := range_of(fields[0])
			for cp in span[0]..span[1] + 1: case_flags[cp] += bit

	var case_pool = Pool([], Map[String, Int]())
	var case_records = [[0, 0, 0]]
	var case_seen = Map[String, Int]()
	var case_of = [0].repeated(TOTAL)

	for cp in 0..TOTAL:
		lower_to := special_lower.get(cp)
		upper_to := special_upper.get(cp)
		has_simple := lower.contains(cp) or upper.contains(cp)
		if case_flags[cp] == 0 and not has_simple and lower_to.is_none(): continue

		lower_field := case_field(cp, lower.get_or(cp, cp), case_pool, lower_to)?
		upper_field := case_field(cp, upper.get_or(cp, cp), case_pool, upper_to)?
		key := f"{lower_field}:{upper_field}:{case_flags[cp]}"

		if at := case_seen.get(key):
			case_of[cp] = at
		else:
			at := case_records.length()
			case_records.append([lower_field, upper_field, case_flags[cp]])
			case_seen.add(key, at)
			case_of[cp] = at

	return ok(
		Tables(
			build_trie(record_of),
			records,
			pool.units.clone(),
			comp_key,
			comp_value,
			build_trie(case_of),
			case_records,
			case_pool.units.clone(),
		)
	)

// The case field of one mapping: the delta from `cp` of a one-scalar result, or a pool
// reference (CASE_SPECIAL, the unit count in bits 16 and up, the offset below) of a
// full one.
fn case_field(cp: Int, simple: Int, var pool: Pool, full: List[Int]?) Int!:
	var scalars = [simple]
	if mapped := full: scalars = mapped.clone()
	if scalars.length() == 1: return ok(scalars[0] - cp)

	units := utf16(scalars)
	for unit in units:
		if unit >= 55296 and unit < 57344:
			return error(Error(f"the full case mapping of {cp} leaves the BMP"))
	return ok(CASE_SPECIAL + units.length() * 65536 + pool_add(pool, units))

fn print_header(tables: Tables, version: String) Void:
	print(
		f"/* Generated by tools/unicode-tables.ms from the Unicode {version} Character Database; do not edit."
	)
	print(
		" * Regenerate with `ms run tools/unicode-tables.ms -- <ucd-directory> h`. The reader is src/runtime/core/ucd.h. */"
	)
	print("#ifndef MS_RT_UNICODE_TABLES_H")
	print("#define MS_RT_UNICODE_TABLES_H")
	print("")
	print("#include <stdint.h>")
	print("")
	print(f"#define MS_UCD_VERSION \"{version}\"")
	print(f"#define MS_UCD_MID_BITS {MID_BITS}")
	print(f"#define MS_UCD_LEAF_BITS {LEAF_BITS}")
	print(f"#define MS_UCD_COMP_COUNT {tables.comp_key.length()}")
	print("")
	print_trie("ms_ucd_norm", tables.norm, false)
	print_array(
		"ms_ucd_norm_record",
		"uint16_t",
		tables.records.flat_map(fn r: r),
		false,
	)
	print_array("ms_ucd_pool", "uint16_t", tables.pool, false)
	print_array("ms_ucd_comp_key", "uint64_t", tables.comp_key, false)
	print_array("ms_ucd_comp_value", "uint32_t", tables.comp_value, false)
	print_trie("ms_ucd_case", tables.case_trie, false)
	print_array(
		"ms_ucd_case_record",
		"int32_t",
		tables.case_records.flat_map(fn r: r),
		false,
	)
	print_array("ms_ucd_case_pool", "uint16_t", tables.case_pool, false)
	print("")
	print("#endif")

fn print_trie(name: String, trie: Trie, define: Bool) Void:
	print_array(f"{name}_top", c_type(trie.top), trie.top, define)
	print_array(f"{name}_mid", c_type(trie.mid), trie.mid, define)
	print_array(f"{name}_leaf", c_type(trie.leaf), trie.leaf, define)

fn print_source(tables: Tables, version: String) Void:
	print(
		f"/* Generated by tools/unicode-tables.ms from the Unicode {version} Character Database; do not edit."
	)
	print(
		" * Regenerate with `ms run tools/unicode-tables.ms -- <ucd-directory> c`. */"
	)
	print("#include \"unicode_tables.h\"")
	print("")
	print_trie("ms_ucd_norm", tables.norm, true)
	print_array(
		"ms_ucd_norm_record",
		"uint16_t",
		tables.records.flat_map(fn r: r),
		true,
	)
	print_array("ms_ucd_pool", "uint16_t", tables.pool, true)
	print_array("ms_ucd_comp_key", "uint64_t", tables.comp_key, true)
	print_array("ms_ucd_comp_value", "uint32_t", tables.comp_value, true)
	print_trie("ms_ucd_case", tables.case_trie, true)
	print_array(
		"ms_ucd_case_record",
		"int32_t",
		tables.case_records.flat_map(fn r: r),
		true,
	)
	print_array("ms_ucd_case_pool", "uint16_t", tables.case_pool, true)

// The release number from the first line of DerivedNormalizationProps.txt.
fn version_of(directory: String) String!:
	text := load(directory, "DerivedNormalizationProps.txt")?
	name := text.lines()[0].split("-")[1]
	return ok(name.split(".txt")[0].clone())

fn main() Void!:
	args := arguments()

	if args.length() != 2:
		print("usage: ms run tools/unicode-tables.ms -- <ucd-directory> c|h")
		return ok(void)

	tables := build(args[0].clone())?
	version := version_of(args[0].clone())?

	if args[1] == "h": print_header(tables, version)
	else: print_source(tables, version)

	return ok(void)
