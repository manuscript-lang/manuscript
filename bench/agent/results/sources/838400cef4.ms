import stdin from "@std/io/io.ms"
import lines from "@std/io/streams.ms"

fn digits(s: String, lo: Int, hi: Int) Int?:
	n := s.length()
	if n < lo or n > hi: return none
	for c in s.chars():
		if c < "0" or c > "9": return none
	return s.parse_int()

fn num(s: String, lo: Int, hi: Int) Int?:
	if v := digits(s, 1, 2):
		if v >= lo and v <= hi: return v
	return none

fn parse_field(text: String, lo: Int, hi: Int) List[Bool]?:
	var set = List[Bool]()
	for _i in 0..hi + 1:
		set.append(false)
	for item in text.split(","):
		parts := item.split("/")
		if parts.length() > 2: return none
		var step = 1
		has_step := parts.length() == 2
		if has_step:
			if s := digits(parts.get(1, ""), 1, 2):
				if s < 1: return none
				step = s
			else: return none
		base := parts.get(0, "")
		var a = lo
		var b = hi
		if base == "*":
			a = lo
		else:
			bp := base.split("-")
			if bp.length() > 2: return none
			if x := num(bp.get(0, ""), lo, hi):
				a = x
			else: return none
			if bp.length() == 2:
				if y := num(bp.get(1, ""), lo, hi):
					b = y
				else: return none
				if a > b: return none
			else:
				if has_step: return none
				b = a
		var v = a
		while v <= b:
			set[v] = true
			v += step
	return set

fn leap(y: Int) Bool:
	return (y % 4 == 0 and y % 100 != 0) or y % 400 == 0

fn mdays(y: Int, m: Int) Int:
	if m == 2:
		return if leap(y): 29 else: 28
	if m == 4 or m == 6 or m == 9 or m == 11: return 30
	return 31

fn p2(n: Int) String:
	if n < 10: return "0{n}"
	return "{n}"

fn p4(n: Int) String:
	if n < 10: return "000{n}"
	if n < 100: return "00{n}"
	if n < 1000: return "0{n}"
	return "{n}"

fn days_from(y: Int, m: Int, d: Int) Int:
	var total = 0
	for yy in 1970..y:
		total += if leap(yy): 366 else: 365
	for mm in 1..m:
		total += mdays(y, mm)
	return total + d - 1

fn sub(cs: List[String], a: Int, b: Int) String:
	var r = ""
	for i in a..b:
		r += cs.get(i, "")
	return r

fn process(line: String) String:
	toks := line.split(" ")
	if toks.length() != 7: return "error: bad line"
	st := toks.get(0, "")
	if st.length() != 16: return "error: bad start"
	cs := st.chars()
	if cs.get(4, "") != "-" or cs.get(7, "") != "-" or cs.get(10, "") != "T" or cs.get(13, "") != ":":
		return "error: bad start"
	yo := digits(sub(cs, 0, 4), 4, 4)
	mo := digits(sub(cs, 5, 7), 2, 2)
	dyo := digits(sub(cs, 8, 10), 2, 2)
	ho := digits(sub(cs, 11, 13), 2, 2)
	no := digits(sub(cs, 14, 16), 2, 2)
	if yo.is_none() or mo.is_none() or dyo.is_none() or ho.is_none() or no.is_none(): return "error: bad start"
	y0 := yo.get(0)
	m0 := mo.get(0)
	d0 := dyo.get(0)
	h0 := ho.get(0)
	n0 := no.get(0)
	if y0 < 1970 or y0 > 2099 or m0 < 1 or m0 > 12 or d0 < 1 or d0 > mdays(y0, m0) or h0 > 23 or n0 > 59:
		return "error: bad start"
	count := digits(toks.get(1, ""), 1, 2).get(0)
	if count < 1 or count > 20: return "error: bad count"
	mi := parse_field(toks.get(2, ""), 0, 59)
	if mi.is_none(): return "error: bad minute"
	hr := parse_field(toks.get(3, ""), 0, 23)
	if hr.is_none(): return "error: bad hour"
	dm := parse_field(toks.get(4, ""), 1, 31)
	if dm.is_none(): return "error: bad day-of-month"
	mo2 := parse_field(toks.get(5, ""), 1, 12)
	if mo2.is_none(): return "error: bad month"
	dw := parse_field(toks.get(6, ""), 0, 6)
	if dw.is_none(): return "error: bad day-of-week"
	minf := mi.get(List[Bool]())
	hrf := hr.get(List[Bool]())
	dmf := dm.get(List[Bool]())
	mof := mo2.get(List[Bool]())
	dwf := dw.get(List[Bool]())
	var out = List[String]()
	var y = y0
	var m = m0
	var d = d0
	var wd = (days_from(y0, m0, d0) + 4) % 7
	for i in 0..3001:
		if out.length() >= count: break
		if dmf[d] and mof[m] and dwf[wd]:
			for h in 0..24:
				if not hrf[h]: continue
				for mn in 0..60:
					if not minf[mn]: continue
					if i == 0 and (h < h0 or (h == h0 and mn <= n0)): continue
					if out.length() < count:
						out.append("{p4(y)}-{p2(m)}-{p2(d)} {p2(h)}:{p2(mn)}")
		d += 1
		if d > mdays(y, m):
			d = 1
			m += 1
			if m > 12:
				m = 1
				y += 1
		wd = (wd + 1) % 7
	if out.length() == 0: return "never"
	return "{out.length()} runs\n" + out.join("\n")

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	var n = 0
	for line in lines(stdin()):
		n += 1
		if line.trim() == "": continue
		print("line {n}: {process(line)}")
