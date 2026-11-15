import stdin from "@std/io/io.ms"
import lines from "@std/io/streams.ms"

fn is_leap(y: Int) Bool:
	return (y % 4 == 0 and y % 100 != 0) or y % 400 == 0

fn dim(y: Int, m: Int) Int:
	if m == 2:
		if is_leap(y): return 29
		return 28
	if m == 4 or m == 6 or m == 9 or m == 11: return 30
	return 31

fn num(s: String) Int:
	n := s.length()
	if n < 1 or n > 2: return -1
	for c in s.chars():
		if not "0123456789".contains(c): return -1
	return s.parse_int().get(-1)

fn parse_field(text: String, lo: Int, hi: Int) List[Bool]:
	var vals = List[Bool]()
	for _i in 0..(hi + 1):
		vals.append(false)
	for item in text.split(","):
		parts := item.split("/")
		if parts.length() > 2: return List[Bool]()
		base := parts.get(0, "")
		var a = lo
		var b = hi
		if base == "*":
			a = lo
			b = hi
		else if base.contains("-"):
			ends := base.split("-")
			if ends.length() != 2: return List[Bool]()
			x := num(ends.get(0, ""))
			if x < 0: return List[Bool]()
			y := num(ends.get(1, ""))
			if y < 0: return List[Bool]()
			if x > y or x < lo or y > hi: return List[Bool]()
			a = x
			b = y
		else:
			if parts.length() != 1: return List[Bool]()
			x := num(base)
			if x < 0: return List[Bool]()
			if x < lo or x > hi: return List[Bool]()
			a = x
			b = x
		var step = 1
		if parts.length() == 2:
			s := num(parts.get(1, ""))
			if s < 0: return List[Bool]()
			if s < 1: return List[Bool]()
			step = s
		var v = a
		while v <= b:
			vals[v] = true
			v += step
	return vals

fn digits(s: String) Bool:
	if s.length() == 0: return false
	for c in s.chars():
		if not "0123456789".contains(c): return false
	return true

fn days_from_civil(y0: Int, m: Int, d: Int) Int:
	y := if m <= 2: y0 - 1 else: y0
	era := y / 400
	yoe := y - era * 400
	mp := (m + 9) % 12
	doy := (153 * mp + 2) / 5 + d - 1
	doe := yoe * 365 + yoe / 4 - yoe / 100 + doy
	return era * 146097 + doe - 719468

fn pad(n: Int, w: Int) String:
	return "{n}".pad_start(w, "0")

fn process(line: String, no: Int) String:
	toks := line.split(" ")
	hdr := "line {no}: "
	if toks.length() != 7: return hdr + "error: bad line\n"
	st := toks.get(0, "")
	if st.length() != 16: return hdr + "error: bad start\n"
	if not (digits(st.view(0, 4)) and digits(st.view(5, 7)) and digits(st.view(8, 10)) and digits(st.view(11, 13)) and digits(st.view(14, 16))):
		return hdr + "error: bad start\n"
	if st.view(4, 5) != "-" or st.view(7, 8) != "-" or st.view(10, 11) != "T" or st.view(13, 14) != ":":
		return hdr + "error: bad start\n"
	var y = st.view(0, 4).parse_int().get(0)
	var mo = st.view(5, 7).parse_int().get(0)
	var d = st.view(8, 10).parse_int().get(0)
	hh := st.view(11, 13).parse_int().get(0)
	mi := st.view(14, 16).parse_int().get(0)
	if y < 1970 or y > 2099 or mo < 1 or mo > 12 or d < 1 or d > dim(y, mo) or hh > 23 or mi > 59:
		return hdr + "error: bad start\n"
	cs := toks.get(1, "")
	if not digits(cs) or cs.length() > 2: return hdr + "error: bad count\n"
	count := cs.parse_int().get(0)
	if count < 1 or count > 20: return hdr + "error: bad count\n"
	fm := parse_field(toks.get(2, ""), 0, 59)
	if fm.length() == 0: return hdr + "error: bad minute\n"
	fh := parse_field(toks.get(3, ""), 0, 23)
	if fh.length() == 0: return hdr + "error: bad hour\n"
	fd := parse_field(toks.get(4, ""), 1, 31)
	if fd.length() == 0: return hdr + "error: bad day-of-month\n"
	fo := parse_field(toks.get(5, ""), 1, 12)
	if fo.length() == 0: return hdr + "error: bad month\n"
	fw := parse_field(toks.get(6, ""), 0, 6)
	if fw.length() == 0: return hdr + "error: bad day-of-week\n"
	base := days_from_civil(y, mo, d)
	var found = List[String]()
	for i in 0..3001:
		if found.length() >= count: break
		wd := (base + i + 4) % 7
		if fd[d] and fo[mo] and fw[wd]:
			for h in 0..24:
				if not fh[h]: continue
				for m in 0..60:
					if not fm[m]: continue
					if i == 0 and (h < hh or (h == hh and m <= mi)): continue
					if found.length() < count:
						found.append("{pad(y, 4)}-{pad(mo, 2)}-{pad(d, 2)} {pad(h, 2)}:{pad(m, 2)}")
		d += 1
		if d > dim(y, mo):
			d = 1
			mo += 1
			if mo > 12:
				mo = 1
				y += 1
	if found.length() == 0: return hdr + "never\n"
	var out = hdr + "{found.length()} runs\n"
	for f in found:
		out = out + f + "\n"
	return out

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	var no = 0
	var out = ""
	for line in lines(stdin(), none):
		no += 1
		if line.trim() == "": continue
		out = out + process(line, no)
	print(out.trim_end())
