import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"

fn is_digits(s: String) Bool:
	if s.length() == 0:
		return false
	for c in s.chars():
		if c < "0" or c > "9":
			return false
	return true

fn sub(cs: List[String], a: Int, b: Int) String:
	var r = ""
	for i in a..b:
		r += cs[i]
	return r

fn num(s: String, maxlen: Int) Int:
	if s.length() < 1 or s.length() > maxlen or not is_digits(s):
		return -1
	return s.parse_int().get(-1)

fn is_leap(y: Int) Bool:
	return (y % 4 == 0 and y % 100 != 0) or y % 400 == 0

fn mdays(y: Int, m: Int) Int:
	if m == 2:
		return if is_leap(y): 29 else: 28
	if m == 4 or m == 6 or m == 9 or m == 11:
		return 30
	return 31

fn parse_field(s: String, lo: Int, hi: Int) List[Bool]?:
	var set = List[Bool]()
	for i in 0..(hi + 1):
		set.append(false)
	for item in s.split(","):
		parts := item.split("/")
		if parts.length() > 2:
			return none
		var step = 1
		if parts.length() == 2:
			st := num(parts[1], 2)
			if st < 1:
				return none
			step = st
		base := parts[0]
		var a = lo
		var b = hi
		if base == "*":
			a = lo
		else:
			rp := base.split("-")
			if rp.length() == 1:
				if parts.length() == 2:
					return none
				v := num(rp[0], 2)
				if v < lo or v > hi:
					return none
				a = v
				b = v
			else if rp.length() == 2:
				x := num(rp[0], 2)
				y := num(rp[1], 2)
				if x < lo or y > hi or x > y:
					return none
				a = x
				b = y
			else:
				return none
		var v = a
		while v <= b:
			set[v] = true
			v += step
	return set

fn pad(n: Int) String:
	return if n < 10: "0{n}" else: "{n}"

fn process(line: String, no: Int) Unit:
	toks := line.split(" ")
	if toks.length() != 7:
		print("line {no}: error: bad line")
		return
	st := toks[0]
	cs := st.chars()
	var ok = cs.length() == 16
	if ok:
		ok = cs[4] == "-" and cs[7] == "-" and cs[10] == "T" and cs[13] == ":"
	var y = 0
	var mo = 0
	var d = 0
	var h = 0
	var mi = 0
	if ok:
		y = num(sub(cs, 0, 4), 4)
		mo = num(sub(cs, 5, 7), 2)
		d = num(sub(cs, 8, 10), 2)
		h = num(sub(cs, 11, 13), 2)
		mi = num(sub(cs, 14, 16), 2)
		if y < 1970 or y > 2099 or mo < 1 or mo > 12 or h < 0 or h > 23 or mi < 0 or mi > 59 or d < 1:
			ok = false
		else if d > mdays(y, mo):
			ok = false
	if not ok:
		print("line {no}: error: bad start")
		return
	cnt := num(toks[1], 2)
	if cnt < 1 or cnt > 20:
		print("line {no}: error: bad count")
		return
	fm := parse_field(toks[2], 0, 59)
	if fm.is_none():
		print("line {no}: error: bad minute")
		return
	fh := parse_field(toks[3], 0, 23)
	if fh.is_none():
		print("line {no}: error: bad hour")
		return
	fd := parse_field(toks[4], 1, 31)
	if fd.is_none():
		print("line {no}: error: bad day-of-month")
		return
	fo := parse_field(toks[5], 1, 12)
	if fo.is_none():
		print("line {no}: error: bad month")
		return
	fw := parse_field(toks[6], 0, 6)
	if fw.is_none():
		print("line {no}: error: bad day-of-week")
		return
	sm := fm.get([])
	sh := fh.get([])
	sd := fd.get([])
	so := fo.get([])
	sw := fw.get([])
	// day of week of start
	var days = 0
	for yy in 1970..y:
		days += if is_leap(yy): 366 else: 365
	for mm in 1..mo:
		days += mdays(y, mm)
	days += d - 1
	var dow = (days + 4) % 7
	var res = List[String]()
	var first = true
	var di = 0
	while di <= 3000 and res.length() < cnt:
		if so[mo] and sd[d] and sw[dow]:
			for hh in 0..24:
				if sh[hh]:
					for mm in 0..60:
						if sm[mm] and res.length() < cnt:
							if not first or hh * 60 + mm > h * 60 + mi:
								res.append("{y}-{pad(mo)}-{pad(d)} {pad(hh)}:{pad(mm)}")
		first = false
		di += 1
		dow = (dow + 1) % 7
		d += 1
		if d > mdays(y, mo):
			d = 1
			mo += 1
			if mo > 12:
				mo = 1
				y += 1
	if res.length() == 0:
		print("line {no}: never")
		return
	print("line {no}: {res.length()} runs")
	for r in res:
		print(r)

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	data := read_all(stdin())?
	text := data.decode_utf8().get("")
	var no = 0
	for line in text.lines():
		no += 1
		if line.trim_chars(" ").length() == 0:
			continue
		process(line, no)
