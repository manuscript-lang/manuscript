import stdin, stdout from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"

type Stamp:
    year: Int
    month: Int
    day: Int
    hour: Int
    minute: Int

type Spec:
    minutes: List[Int]
    hours: List[Int]
    doms: List[Bool]
    months: List[Bool]
    dows: List[Bool]

fn is_digit(c: String) Bool:
    return c.length() == 1 and "0123456789".contains(c)

// Value of ASCII digits in s[a, b), or -1 when any character is not a digit.
fn digits_value(s: String, a: Int, b: Int) Int:
    var v = 0
    for i in a..b:
        let c = s.get(i)
        if not is_digit(c):
            return -1
        v = v * 10 + c.parse_int().get(0)
    return v

// A 1-2 digit number in [lo, hi], or -1.
fn num_in(s: String, lo: Int, hi: Int) Int:
    let n = s.length()
    if n < 1 or n > 2:
        return -1
    let v = digits_value(s, 0, n)
    if v < lo or v > hi:
        return -1
    return v

fn in_range(v: Int, lo: Int, hi: Int) Bool:
    return v >= lo and v <= hi

fn is_leap(y: Int) Bool:
    return (y % 4 == 0 and y % 100 != 0) or y % 400 == 0

fn days_in(y: Int, m: Int) Int:
    if m == 2:
        if is_leap(y):
            return 29
        return 28
    if m == 4 or m == 6 or m == 9 or m == 11:
        return 30
    return 31

// Day of week for a date, 0 = Sunday. 1970-01-01 was a Thursday.
fn weekday(y: Int, m: Int, d: Int) Int:
    var n = 0
    for yy in 1970..y:
        if is_leap(yy):
            n += 366
        else:
            n += 365
    for mm in 1..m:
        n += days_in(y, mm)
    n += d - 1
    return (4 + n) % 7

fn parse_start(s: String) Stamp:
    let bad = Stamp(year: -1, month: 0, day: 0, hour: 0, minute: 0)
    if s.length() != 16:
        return bad
    if s.get(4) != "-" or s.get(7) != "-" or s.get(10) != "T" or s.get(13) != ":":
        return bad
    let y = digits_value(s, 0, 4)
    let mo = digits_value(s, 5, 7)
    let d = digits_value(s, 8, 10)
    let h = digits_value(s, 11, 13)
    let mi = digits_value(s, 14, 16)
    if not in_range(y, 1970, 2099) or not in_range(mo, 1, 12):
        return bad
    if not in_range(d, 1, days_in(y, mo)) or not in_range(h, 0, 23) or not in_range(mi, 0, 59):
        return bad
    return Stamp(year: y, month: mo, day: d, hour: h, minute: mi)

fn blank_bits(n: Int) List[Bool]:
    var out = List[Bool]()
    for _k in 0..n:
        out.append(false)
    return out

// Adds one cron item (`*`, `*/S`, `A`, `A-B`, `A-B/S`) to bits. False when invalid.
fn add_item(item: String, lo: Int, hi: Int, var bits: List[Bool]) Bool:
    let parts = item.split("/")
    if parts.length() > 2:
        return false
    var step = 1
    if parts.length() == 2:
        step = num_in(parts[1], 1, 99)
        if step < 1:
            return false
    var a = lo
    var b = hi
    let range = parts[0]
    if range != "*":
        let dash = range.split("-")
        if dash.length() == 1:
            if parts.length() == 2:
                return false
            a = num_in(range, lo, hi)
            if a < 0:
                return false
            b = a
        else if dash.length() == 2:
            a = num_in(dash[0], lo, hi)
            b = num_in(dash[1], lo, hi)
            if a < 0 or b < 0 or a > b:
                return false
        else:
            return false
    var v = a
    while v <= b:
        bits[v] = true
        v += step
    return true

// Parses a whole cron field into bits indexed by value.
fn load_field(text: String, lo: Int, hi: Int, var bits: List[Bool]) Bool:
    for item in text.split(","):
        if not add_item(item, lo, hi, var bits):
            return false
    return true

fn to_values(bits: List[Bool]) List[Int]:
    var out = List[Int]()
    for v in 0..bits.length():
        if bits[v]:
            out.append(v)
    return out

fn pad(v: Int, w: Int) String:
    var s = "{v}"
    while s.length() < w:
        s = "0" + s
    return s

fn format_stamp(y: Int, mo: Int, d: Int, h: Int, mi: Int) String:
    return pad(y, 4) + "-" + pad(mo, 2) + "-" + pad(d, 2) + " " + pad(h, 2) + ":" + pad(mi, 2)

fn find_runs(sp: Spec, st: Stamp, count: Int) List[String]:
    var out = List[String]()
    var y = st.year
    var mo = st.month
    var d = st.day
    var wd = weekday(y, mo, d)
    let start_min = st.hour * 60 + st.minute
    var i = 0
    while i <= 3000 and out.length() < count:
        if sp.months[mo] and sp.doms[d] and sp.dows[wd]:
            for h in sp.hours:
                for mi in sp.minutes:
                    if out.length() < count and (i > 0 or h * 60 + mi > start_min):
                        out.append(format_stamp(y, mo, d, h, mi))
        i += 1
        d += 1
        if d > days_in(y, mo):
            d = 1
            mo += 1
            if mo > 12:
                mo = 1
                y += 1
        wd = (wd + 1) % 7
    return out

fn error_line(n: Int, msg: String) String:
    return "line {n}: error: {msg}\n"

fn process_line(line: String, n: Int) String:
    let toks = line.split(" ")
    if toks.length() != 7:
        return error_line(n, "bad line")
    let st = parse_start(toks[0])
    if st.year < 0:
        return error_line(n, "bad start")
    let cnt = num_in(toks[1], 1, 20)
    if cnt < 0:
        return error_line(n, "bad count")
    var mins = blank_bits(60)
    if not load_field(toks[2], 0, 59, var mins):
        return error_line(n, "bad minute")
    var hrs = blank_bits(24)
    if not load_field(toks[3], 0, 23, var hrs):
        return error_line(n, "bad hour")
    var doms = blank_bits(32)
    if not load_field(toks[4], 1, 31, var doms):
        return error_line(n, "bad day-of-month")
    var mons = blank_bits(13)
    if not load_field(toks[5], 1, 12, var mons):
        return error_line(n, "bad month")
    var dows = blank_bits(7)
    if not load_field(toks[6], 0, 6, var dows):
        return error_line(n, "bad day-of-week")
    let sp = Spec(minutes: to_values(mins), hours: to_values(hrs), doms: doms, months: mons, dows: dows)
    let runs = find_runs(sp, st, cnt)
    if runs.length() == 0:
        return "line {n}: never\n"
    var out = "line {n}: {runs.length()} runs\n"
    for r in runs:
        out += r + "\n"
    return out

fn is_blank(line: String) Bool:
    for i in 0..line.length():
        if line.get(i) != " ":
            return false
    return true

export fn main() Int:
    let text = read_all(stdin()).get().decode_utf8().get("")
    var buf = ""
    var n = 0
    for line in text.lines():
        n += 1
        if not is_blank(line):
            buf += process_line(line, n)
    stdout().write(buf).get()
    return 0
