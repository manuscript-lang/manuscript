import (
	Bytes from "@std/bytes.ms",

	msstd_time_system_zone,
	msstd_time_system_zone_file,
	msstd_time_zone_data from "@std/internal/time.ms",
)

// Time zones for @std/time: UTC, fixed offsets such as `+05:30`, the host's local zone
// and IANA names. IANA zones come from the bundled database
// (src/runtime/std/tzdata.bin, one copy of the data on every platform), read as TZif
// version 2+ blocks: transitions, local time types, and the POSIX rule in the footer
// that governs the time after the last transition.

// The offset and abbreviation of a zone at one moment.
export type ZoneAt:
	// Seconds east of UTC.
	offset: Int
	// The abbreviation, such as `EST`, or the fixed offset's own text.
	abbreviation: String

// One yearly transition of a POSIX rule: `Mm.w.d` (kind 0), `Jn` (1) or `n` (2), at
// `time` local seconds.
type Rule:
	kind: Int
	month: Int
	week: Int
	day: Int
	time: Int

// A resolved zone. A table zone keeps the TZif block and the byte positions of its
// parts.
// `kind` 0 is UTC, 1 a fixed offset and 2 a table zone; a table zone with no transitions follows its rule.
export type Zone:
	kind: Int
	// The zone name: the IANA name, or `""` when the data came from a file.
	name: String
	// The fixed offset in seconds east of UTC.
	fixed: Int
	data: Bytes
	count: Int
	times: Int
	time_size: Int
	indexes: Int
	types: Int
	abbrevs: Int
	abbrev_size: Int
	has_footer: Bool
	std_name: String
	std_offset: Int
	dst_name: String
	dst_offset: Int
	has_dst: Bool
	start: Rule
	end: Rule

fn bad_zone() Error:
	return Error("time: invalid zone data", kind: "EBADMSG")

fn unknown_zone() Error:
	return Error("time: unknown zone", kind: "EINVAL")

// Division and remainder that round toward negative infinity.
fn floor_div(a: Int, b: Int) Int:
	q := a / b
	if a % b != 0 and (a < 0) != (b < 0): return q - 1

	return q

fn floor_mod(a: Int, b: Int) Int:
	return a - floor_div(a, b) * b

// Days since 1970-01-01 of a proleptic Gregorian date.
fn days_from_civil(year: Int, month: Int, day: Int) Int:
	y := if month <= 2: year - 1 else: year
	era := floor_div(y, 400)
	yoe := y - era * 400
	shifted := if month > 2: month - 3 else: month + 9
	doy := (153 * shifted + 2) / 5 + day - 1
	doe := yoe * 365 + yoe / 4 - yoe / 100 + doy
	return era * 146097 + doe - 719468

// The year of a day count since 1970-01-01.
fn year_of_days(days: Int) Int:
	z := days + 719468
	era := floor_div(z, 146097)
	doe := z - era * 146097
	yoe := (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
	doy := doe - (365 * yoe + yoe / 4 - yoe / 100)
	mp := (5 * doy + 2) / 153
	month := if mp < 10: mp + 3 else: mp - 9
	return yoe + era * 400 + (if month <= 2: 1 else: 0)

fn is_leap(year: Int) Bool:
	return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)

// An unsigned big-endian integer of `width` bytes.
fn be(data: Bytes, at: Int, width: Int) Int:
	var n = 0
	for i in 0..width:
		n = n * 256 + data.get(at + i).to_int()
	return n

fn be_i32(data: Bytes, at: Int) Int:
	n := be(data, at, 4)
	return if n >= 2147483648: n - 4294967296 else: n

// A signed big-endian integer of `width` bytes, 4 or 8.
fn be_signed(data: Bytes, at: Int, width: Int) Int:
	if width == 4: return be_i32(data, at)
	return be_i32(data, at) * 4294967296 + be(data, at + 4, 4)

fn is_alpha(c: Int) Bool:
	return (c >= 65 and c <= 90) or (c >= 97 and c <= 122)

fn is_digit(c: Int) Bool:
	return c >= 48 and c <= 57

// A reader over the text of a POSIX TZ rule. A malformed rule sets `bad`.
type Scan:
	text: Bytes
	pos: Int
	bad: Bool

// The byte at the cursor, or -1 at the end.
fn Scan.peek() Int:
	if self.pos >= self.text.length(): return -1
	return self.text.get(self.pos).to_int()

fn var Scan.fail() Int:
	self.bad = true
	return 0

// Consumes `c` when it is next.
fn var Scan.eat(c: Int) Bool:
	if self.peek() != c: return false

	self.pos += 1
	return true

// One to three decimal digits.
fn var Scan.number() Int:
	var n = 0
	var digits = 0

	while is_digit(self.peek()) and digits < 3:
		n = n * 10 + self.peek() - 48
		self.pos += 1
		digits += 1

	if digits == 0: return self.fail()

	return n

// A zone abbreviation: three or more letters, or text between `<` and `>`.
fn var Scan.name() String:
	var start = self.pos

	if self.eat(60):
		start = self.pos
		while self.peek() != 62 and self.peek() >= 0:
			self.pos += 1

		finish := self.pos
		if not self.eat(62): self.bad = true
		return self.text.decode_utf8_range(start, finish).get_or("")

	while is_alpha(self.peek()):
		self.pos += 1
	if self.pos - start < 3: self.bad = true
	return self.text.decode_utf8_range(start, self.pos).get_or("")

// `[+-]hh[:mm[:ss]]` in seconds, the sign as written.
fn var Scan.clock() Int:
	var sign = 1

	if self.eat(45):
		sign = -1
	else:
		self.eat(43)

	var seconds = self.number() * 3600

	if self.eat(58):
		seconds += self.number() * 60
		if self.eat(58):
			seconds += self.number()

	return sign * seconds

// `Mm.w.d`, `Jn` or `n`, then an optional `/time`.
fn var Scan.rule() Rule:
	var kind = 2
	var month = 0
	var week = 0
	var day = 0

	if self.eat(77):
		kind = 0
		month = self.number()
		if not self.eat(46): self.bad = true
		week = self.number()
		if not self.eat(46): self.bad = true
		day = self.number()
		if month < 1 or month > 12 or week < 1 or week > 5 or day > 6: self.bad = true
	else if self.eat(74):
		kind = 1
		day = self.number()
		if day < 1 or day > 365: self.bad = true
	else:
		day = self.number()
		if day > 365: self.bad = true

	var time = 7200
	if self.eat(47): time = self.clock()
	return Rule(kind: kind, month: month, week: week, day: day, time: time)

// The POSIX rule of a footer: `std offset [dst [offset] , start , end]`.
type Footer:
	ok: Bool
	std_name: String
	std_offset: Int
	dst_name: String
	dst_offset: Int
	has_dst: Bool
	start: Rule
	end: Rule

fn no_rule() Rule:
	return Rule(kind: 2, month: 0, week: 0, day: 0, time: 0)

fn bad_footer() Footer:
	return Footer(
		ok: false,
		std_name: "",
		std_offset: 0,
		dst_name: "",
		dst_offset: 0,
		has_dst: false,
		start: no_rule(),
		end: no_rule(),
	)

fn parse_rule(text: Bytes) Footer:
	var scan = Scan(text: text.clone(), pos: 0, bad: false)
	std_name := scan.name()
	std_offset := -scan.clock()
	if scan.bad: return bad_footer()
	if scan.peek() < 0:
		return Footer(
			ok: true,
			std_name: std_name,
			std_offset: std_offset,
			dst_name: "",
			dst_offset: 0,
			has_dst: false,
			start: no_rule(),
			end: no_rule(),
		)

	dst_name := scan.name()
	var dst_offset = std_offset + 3600
	if scan.peek() != 44: dst_offset = -scan.clock()
	if not scan.eat(44): scan.bad = true

	start := scan.rule()
	if not scan.eat(44): scan.bad = true

	end := scan.rule()
	if scan.peek() >= 0: scan.bad = true
	return Footer(
		ok: not scan.bad,
		std_name: std_name,
		std_offset: std_offset,
		dst_name: dst_name,
		dst_offset: dst_offset,
		has_dst: true,
		start: start,
		end: end,
	)

// A zone with no transition table.
fn plain_zone(kind: Int, move name: String, fixed: Int) Zone:
	empty := no_rule()
	return Zone(
		kind: kind,
		name: name,
		fixed: fixed,
		data: "".to_bytes(),
		count: 0,
		times: 0,
		time_size: 8,
		indexes: 0,
		types: 0,
		abbrevs: 0,
		abbrev_size: 0,
		has_footer: false,
		std_name: name,
		std_offset: fixed,
		dst_name: "",
		dst_offset: 0,
		has_dst: false,
		start: empty.clone(),
		end: empty.clone(),
	)

// A zone that is only a POSIX rule, such as `EST5EDT,M3.2.0,M11.1.0` from a TZ setting.
fn rule_zone(footer: Footer) Zone:
	return Zone(
		kind: 2,
		name: "",
		fixed: 0,
		data: "".to_bytes(),
		count: 0,
		times: 0,
		time_size: 8,
		indexes: 0,
		types: 0,
		abbrevs: 0,
		abbrev_size: 0,
		has_footer: true,
		std_name: footer.std_name.clone(),
		std_offset: footer.std_offset,
		dst_name: footer.dst_name.clone(),
		dst_offset: footer.dst_offset,
		has_dst: footer.has_dst,
		start: footer.start.clone(),
		end: footer.end.clone(),
	)

// The footer of a TZif block that ends at `size`, from the `\n` that follows the data
// at `at`.
fn read_footer(data: Bytes, at: Int) Footer!:
	size := data.length()
	if at >= size or data.get(at).to_int() != 10: return ok(bad_footer())

	var stop = at + 1
	while stop < size and data.get(stop).to_int() != 10:
		stop += 1
	if stop >= size or stop == at + 1: return ok(bad_footer())

	return ok(parse_rule(data.slice(at + 1, stop)?))

// Reads TZif data: the 64-bit block of the bundled database, or, when `whole` is set, a
// whole file with its 32-bit block first (the system's own zone file).
fn from_tzif(name: String, data: Bytes, whole: Bool) Zone!:
	size := data.length()
	if size < 44 or be(data, 0, 4) != 1415211366: return error(bad_zone())

	var base = 0
	var width = 8

	if whole and data.get(4).to_int() >= 50:
		base = (
			44
			+ be(data, 32, 4) * 5
			+ be(data, 36, 4) * 6
			+ be(data, 40, 4)
			+ be(data, 28, 4) * 8
			+ be(data, 24, 4)
			+ be(data, 20, 4)
		)
		if size < base + 44 or be(data, base, 4) != 1415211366: return error(bad_zone())
	else if whole:
		width = 4

	utc_flags := be(data, base + 20, 4)
	std_flags := be(data, base + 24, 4)
	leaps := be(data, base + 28, 4)
	count := be(data, base + 32, 4)
	types := be(data, base + 36, 4)
	chars := be(data, base + 40, 4)
	times := base + 44
	indexes := times + count * width
	type_at := indexes + count
	abbrevs := type_at + types * 6
	finish := abbrevs + chars
	if types < 1 or types > 256 or finish > size: return error(bad_zone())

	for i in 0..count:
		if data.get(indexes + i).to_int() >= types: return error(bad_zone())
	for t in 0..types:
		if data.get(type_at + t * 6 + 5).to_int() >= chars: return error(bad_zone())

	var footer = bad_footer()
	if width == 8:
		footer = read_footer(data, finish + leaps * 12 + std_flags + utc_flags)?
	return ok(
		Zone(
			kind: 2,
			name: name,
			fixed: 0,
			data: data.clone(),
			count: count,
			times: times,
			time_size: width,
			indexes: indexes,
			types: type_at,
			abbrevs: abbrevs,
			abbrev_size: chars,
			has_footer: footer.ok,
			std_name: footer.std_name.clone(),
			std_offset: footer.std_offset,
			dst_name: footer.dst_name.clone(),
			dst_offset: footer.dst_offset,
			has_dst: footer.has_dst,
			start: footer.start.clone(),
			end: footer.end.clone(),
		)
	)

// Seconds since the epoch of a rule's transition in `year`, in the local time the rule
// is written in.
fn rule_seconds(rule: Rule, year: Int) Int:
	var day = 0

	if rule.kind == 0:
		first := days_from_civil(year, rule.month, 1)
		weekday := floor_mod(first + 4, 7)
		day = first + floor_mod(rule.day - weekday, 7) + (rule.week - 1) * 7

		next := if rule.month == 12: days_from_civil(year + 1, 1, 1) else: days_from_civil(
			year,
			rule.month + 1,
			1,
		)
		while day >= next:
			day -= 7
	else if rule.kind == 1:
		day = days_from_civil(year, 1, 1) + rule.day - 1
		if is_leap(year) and rule.day >= 60: day += 1
	else:
		day = days_from_civil(year, 1, 1) + rule.day

	return day * 86400 + rule.time

// The transition time of entry `i`.
fn Zone.time(i: Int) Int:
	return be_signed(self.data, self.times + i * self.time_size, self.time_size)

// The offset and abbreviation of local time type `t`.
fn Zone.type_at(t: Int) ZoneAt:
	at := self.types + t * 6
	start := self.abbrevs + self.data.get(at + 5).to_int()
	limit := self.abbrevs + self.abbrev_size
	var stop = start
	while stop < limit and self.data.get(stop).to_int() != 0:
		stop += 1
	return ZoneAt(
		offset: be_i32(self.data, at),
		abbreviation: self.data.decode_utf8_range(start, stop).get_or(""),
	)

// The footer rule's offset and abbreviation at `unix`.
fn Zone.rule_at(unix: Int) ZoneAt:
	if not self.has_dst: return ZoneAt(
		offset: self.std_offset,
		abbreviation: self.std_name.clone(),
	)

	year := year_of_days(floor_div(unix + self.std_offset, 86400))
	begin := rule_seconds(self.start, year) - self.std_offset
	finish := rule_seconds(self.end, year) - self.dst_offset
	var summer = false

	if begin < finish:
		summer = unix >= begin and unix < finish
	else:
		summer = not (unix >= finish and unix < begin)

	if summer: return ZoneAt(
		offset: self.dst_offset,
		abbreviation: self.dst_name.clone(),
	)

	return ZoneAt(offset: self.std_offset, abbreviation: self.std_name.clone())

// The offset (seconds east of UTC) and abbreviation of this zone at a Unix time.
fn Zone.at(unix: Int) ZoneAt:
	if self.kind == 0: return ZoneAt(offset: 0, abbreviation: "UTC")
	if self.kind == 1: return ZoneAt(
		offset: self.fixed,
		abbreviation: self.name.clone(),
	)

	if self.count == 0:
		if self.has_footer: return self.rule_at(unix)
		return self.type_at(0)

	if unix < self.time(0): return self.type_at(0)
	if unix >= self.time(self.count - 1) and self.has_footer: return self.rule_at(unix)

	// The last transition at or before `unix`.
	var low = 0
	var high = self.count

	while high - low > 1:
		mid := (low + high) / 2

		if self.time(mid) <= unix:
			low = mid
		else:
			high = mid

	return self.type_at(self.data.get(self.indexes + low).to_int())

// The offset that local seconds `local` (the fields read as UTC) belong to; a time
// skipped or repeated by a transition takes the offset before it.
fn Zone.offset_for_local(local: Int) Int:
	if self.kind != 2: return self.at(local).offset

	before := self.at(local - 86400).offset
	after := self.at(local + 86400).offset
	if before == after: return before
	if self.at(local - before).offset == before: return before
	if self.at(local - after).offset == after: return after

	return before

// `[+-]hh:mm` as seconds east of UTC, or none.
fn fixed_offset(text: String) Int?:
	data := text.view_bytes()
	if data.length() != 6 or data.get(3).to_int() != 58: return none

	sign := data.get(0).to_int()
	if sign != 43 and sign != 45: return none

	for i in [1, 2, 4, 5]:
		if not is_digit(data.get(i).to_int()): return none

	hours := (data.get(1).to_int() - 48) * 10 + data.get(2).to_int() - 48
	minutes := (data.get(4).to_int() - 48) * 10 + data.get(5).to_int() - 48
	if hours > 23 or minutes > 59: return none

	seconds := hours * 3600 + minutes * 60
	return if sign == 45: -seconds else: seconds

// An IANA zone from the bundled database; `windows/` entries are not zones.
fn named(name: String) Zone!:
	if name.is_empty() or name.starts_with("windows/"): return error(unknown_zone())

	data := msstd_time_zone_data(name)
	if data.is_empty(): return error(unknown_zone())

	return from_tzif(name, data, false)

// The host's zone from the system's setting; UTC when it cannot be told.
fn host_zone() Zone:
	spec := msstd_time_system_zone()

	if spec.starts_with("windows:"):
		iana := (
			msstd_time_zone_data(f"windows/{spec.view(8, spec.length())}")
			.decode_utf8()
			.get_or("")
		)
		if zone := named(iana): return zone

		return plain_zone(0, "UTC", 0)

	if spec.starts_with("tz:"):
		var text = spec.view(3, spec.length())
		if text.starts_with(":"): text = text.view(1, text.length())
		if zone := named(text): return zone

		// A POSIX rule such as `EST5EDT,M3.2.0,M11.1.0`.
		footer := parse_rule(text.to_bytes())
		if footer.ok: return rule_zone(footer)

		return plain_zone(0, "UTC", 0)

	if spec.starts_with("link:"):
		if zone := named(spec.view(5, spec.length())): return zone

	file := msstd_time_system_zone_file().get_or("".to_bytes())
	if not file.is_empty():
		if zone := from_tzif("", file, true): return zone
	return plain_zone(0, "UTC", 0)

// Resolves `UTC`, the empty string, `Local`, a fixed offset such as `+05:30` or an IANA
// name; any other name returns `EINVAL`.
export fn load(name: String) Zone!:
	if name == "UTC" or name.is_empty(): return ok(plain_zone(0, "UTC", 0))
	if name == "Local": return ok(host_zone())
	if offset := fixed_offset(name): return ok(plain_zone(1, name, offset))

	return named(name)

// The IANA name of the host's zone, `UTC` when it has none.
export fn local_name() String:
	name := host_zone().name
	if name.is_empty(): return "UTC"

	return name
