import stdin from "@std/io/io.ms"
import lines from "@std/io/streams.ms"

fn is_num(s: String) Bool:
	n := s.length()
	if n < 1 or n > 2: return false
	for c in s.chars():
		if not "0123456789".contains(c): return false
	return true

fn num(s: String) Int:
	return s.parse_int().get(0)

fn is_digits(s: String, n: Int) Bool:
	if s.length() != n: return false
	for c in s.chars():
		if not "0123456789".contains(c): return false
	return true

fn leap(y: Int) Bool:
	return (y % 4 == 0 and y % 100 != 0) or y % 400 == 0

fn mdays(y: Int, m: Int) Int:
	if m == 2: return if leap(y): 29 else: 28
	if m == 4 or m == 6 or m == 9 or m == 11: return 30
	return 31

// returns allowed flags indexed 0..hi, or empty list when invalid
fn parse_field(text: String, lo: Int, hi: Int) List[Bool]:
	var flags = List[Bool]()
	for i in 0..(hi + 1):
		flags.append(false)
	bad := List[Bool]()
	for item in text.split(","):
		if item.length() == 0: return bad
		sp := item.split("/")
		if sp.length() > 2: return bad
		var step = 1
		if sp.length() == 2:
			if not is_num(sp.get(1, "")): return bad
			step = num(sp.get(1, ""))
			if step < 1: return bad
		base := sp.get(0, "")
		var a = lo
		var b = hi
		if base != "*":
			rp := base.split("-")
			if rp.length() > 2: return bad
			if not is_num(rp.get(0, "")): return bad
			a = num(rp.get(0, ""))
			if rp.length() == 2:
				if not is_num(rp.get(1, "")): return bad
				b = num(rp.get(1, ""))
			else:
				if sp.length() == 2: return bad
				b = a
			if a < lo or a > hi or b < lo or b > hi or a > b: return bad
		var v = a
		while v <= b:
			flags[v] = true
			v += step
	return flags

fn ok_at(f: List[Bool], i: Int) Bool:
	return f.get(i, false)

fn process(line: String, n: Int) Unit:
	toks := line.split(" ")
	if toks.length() != 7:
		print("line {n}: error: bad line")
		return
	st := toks.get(0, "")
	cs := st.chars()
	if st.length() != 16 or not is_digits(st.slice(0, 4).get(""), 4):
		print("line {n}: error: bad start")
		return
	var sy = 0
	var sm = 0
	var sd = 0
	var sh = 0
	var smi = 0
	valid := is_digits(st.slice(5, 7).get(""), 2) and is_digits(st.slice(8, 10).get(""), 2) and is_digits(st.slice(11, 13).get(""), 2) and is_digits(st.slice(14, 16).get(""), 2) and cs.get(4, "") == "-" and cs.get(7, "") == "-" and cs.get(10, "") == "T" and cs.get(13, "") == ":"
	if not valid:
		print("line {n}: error: bad start")
		return
	sy = num(st.slice(0, 4).get(""))
	sm = num(st.slice(5, 7).get(""))
	sd = num(st.slice(8, 10).get(""))
	sh = num(st.slice(11, 13).get(""))
	smi = num(st.slice(14, 16).get(""))
	if sy < 1970 or sy > 2099 or sm < 1 or sm > 12 or sd < 1 or sd > mdays(sy, sm) or sh > 23 or smi > 59:
		print("line {n}: error: bad start")
		return
	cstr := toks.get(1, "")
	if not is_num(cstr) or num(cstr) < 1 or num(cstr) > 20:
		print("line {n}: error: bad count")
		return
	count := num(cstr)
	fmin := parse_field(toks.get(2, ""), 0, 59)
	if fmin.length() == 0:
		print("line {n}: error: bad minute")
		return
	fhr := parse_field(toks.get(3, ""), 0, 23)
	if fhr.length() == 0:
		print("line {n}: error: bad hour")
		return
	fdom := parse_field(toks.get(4, ""), 1, 31)
	if fdom.length() == 0:
		print("line {n}: error: bad day-of-month")
		return
	fmon := parse_field(toks.get(5, ""), 1, 12)
	if fmon.length() == 0:
		print("line {n}: error: bad month")
		return
	fdow := parse_field(toks.get(6, ""), 0, 6)
	if fdow.length() == 0:
		print("line {n}: error: bad day-of-week")
		return
	// day of week of start date
	var days = 0
	for y in 1970..sy:
		days += if leap(y): 366 else: 365
	for m in 1..sm:
		days += mdays(sy, m)
	days += sd - 1
	var dow = (days + 4) % 7
	var y = sy
	var m = sm
	var d = sd
	var found = List[String]()
	for k in 0..3001:
		if found.length() >= count: break
		if ok_at(fdom, d) and ok_at(fmon, m) and ok_at(fdow, dow):
			for h in 0..24:
				if not ok_at(fhr, h): continue
				for mi in 0..60:
					if not ok_at(fmin, mi): continue
					if k == 0 and (h < sh or (h == sh and mi <= smi)): continue
					if found.length() >= count: continue
					hs := if h < 10: "0{h}" else: "{h}"
					ms := if mi < 10: "0{mi}" else: "{mi}"
					mos := if m < 10: "0{m}" else: "{m}"
					ds := if d < 10: "0{d}" else: "{d}"
					found.append("{y}-{mos}-{ds} {hs}:{ms}")
		d += 1
		if d > mdays(y, m):
			d = 1
			m += 1
			if m > 12:
				m = 1
				y += 1
		dow = (dow + 1) % 7
	if found.length() == 0:
		print("line {n}: never")
		return
	print("line {n}: {found.length()} runs")
	for f in found:
		print(f)

// ms: allow_effect std.console.write
// ms: allow_effect std.console.read
fn main() Unit!:
	var n = 0
	for line in lines(stdin()):
		n += 1
		if line.trim().length() == 0: continue
		process(line, n)
