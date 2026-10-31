import read_lines from "@std/streams.ms"
import stdin, stdout from "@std/io.ms"

# Parsed START: year is -1 when invalid.
type Start:
    year: Int
    month: Int
    day: Int
    hour: Int
    minute: Int

# One comma-separated item of a cron field: values start, start+step, ... <= stop.
# start is -1 when the item is invalid.
type Span:
    start: Int
    stop: Int
    step: Int

# Allowed values per field. Each list is indexed by the value itself.
type Spec:
    minutes: List[Bool]
    hours: List[Bool]
    days: List[Bool]
    months: List[Bool]
    weekdays: List[Bool]

fn all_digits(s: String) Bool:
    if s.length() == 0: return false

    for i in 0..s.length():
        if not "0123456789".contains(s.get(i)): return false
    return true

# Exactly `width` ASCII digits; returns -1 otherwise.
fn fixed_num(s: String, width: Int) Int:
    if s.length() != width or not all_digits(s): return -1

    return s.parse_int().get(-1)

# 1 or 2 ASCII digits with lo <= value <= hi; returns -1 otherwise.
fn num_in(s: String, lo: Int, hi: Int) Int:
    if s.length() < 1 or s.length() > 2 or not all_digits(s): return -1

    let v = s.parse_int().get(-1)
    if v < lo or v > hi: return -1

    return v

fn is_leap(y: Int) Bool:
    return (y % 4 == 0 and y % 100 != 0) or y % 400 == 0

fn days_in_month(y: Int, m: Int) Int:
    if m == 2:
        if is_leap(y): return 29

        return 28

    if m == 4 or m == 6 or m == 9 or m == 11: return 30

    return 31

# Days from 1970-01-01 (a Thursday).
fn epoch_days(y: Int, m: Int, d: Int) Int:
    var days = 0

    for yy in 1970..y:
        if is_leap(yy): days += 366
        else: days += 365

    for mm in 1..m:
        days += days_in_month(y, mm)
    return days + d - 1

# 0 = Sunday .. 6 = Saturday.
fn weekday(y: Int, m: Int, d: Int) Int:
    return (epoch_days(y, m, d) + 4) % 7

fn parse_start(s: String) Start:
    let bad = Start(year: -1, month: 0, day: 0, hour: 0, minute: 0)
    let halves = s.split("T")
    if halves.length() != 2: return bad

    let dp = halves[0].split("-")
    let tp = halves[1].split(":")
    if dp.length() != 3 or tp.length() != 2: return bad

    let y = fixed_num(dp[0], 4)
    let mo = fixed_num(dp[1], 2)
    let d = fixed_num(dp[2], 2)
    let h = fixed_num(tp[0], 2)
    let mi = fixed_num(tp[1], 2)
    if y < 1970 or y > 2099: return bad
    if mo < 1 or mo > 12: return bad
    if d < 1 or d > days_in_month(y, mo): return bad
    if h < 0 or h > 23: return bad
    if mi < 0 or mi > 59: return bad

    return Start(year: y, month: mo, day: d, hour: h, minute: mi)

# Parses one item: `*`, `*/S`, `A`, `A-B`, `A-B/S`.
fn parse_span(item: String, lo: Int, hi: Int) Span:
    let bad = Span(start: -1, stop: -1, step: 1)
    let parts = item.split("/")
    if parts.length() > 2: return bad

    var step = 1

    if parts.length() == 2:
        step = num_in(parts[1], 1, 99)
        if step < 0: return bad

    var a = lo
    var b = hi

    if parts[0] != "*":
        let bounds = parts[0].split("-")

        if bounds.length() == 1:
            if parts.length() == 2: return bad

            a = num_in(bounds[0], lo, hi)
            b = a
        else if bounds.length() == 2:
            a = num_in(bounds[0], lo, hi)
            b = num_in(bounds[1], lo, hi)
        else:
            return bad

    if a < 0 or b < 0 or a > b: return bad

    return Span(start: a, stop: b, step: step)

# Returns the allowed-values list for a whole field, or an empty list when invalid.
fn parse_field(text: String, lo: Int, hi: Int) List[Bool]:
    var allowed = List[Bool]()
    for _i in 0..hi + 1:
        allowed.append(false)

    for item in text.split(","):
        var sp = parse_span(item, lo, hi)
        if sp.start < 0: return List[Bool]()

        var v = sp.start

        while v <= sp.stop:
            allowed[v] = true
            v += sp.step

    return allowed

fn pad(n: Int) String:
    if n < 10: return "0{n}"

    return "{n}"

# Up to `count` matches strictly after `st`, searching days st..st+3000.
fn search(st: Start, count: Int, spec: Spec) List[String]:
    var out = List[String]()
    let sy = st.year
    let sm = st.month
    let sd = st.day
    let sh = st.hour
    let smin = st.minute
    var y = sy
    var m = sm
    var d = sd
    var wd = weekday(y, m, d)
    var n = 0

    while n <= 3000 and out.length() < count:
        if spec.months[m] and spec.days[d] and spec.weekdays[wd]:
            for h in 0..24:
                if spec.hours[h]:
                    for mi in 0..60:
                        if spec.minutes[mi] and out.length() < count:
                            if n > 0 or h > sh or (h == sh and mi > smin):
                                out.append("{y}-{pad(m)}-{pad(d)} {pad(h)}:{pad(mi)}")
        n += 1
        d += 1

        if d > days_in_month(y, m):
            d = 1
            m += 1

            if m > 12:
                m = 1
                y += 1

        wd = (wd + 1) % 7

    return out

fn solve(no: Int, line: String) String:
    let toks = line.split(" ")
    if toks.length() != 7: return "line {no}: error: bad line\n"

    let st = parse_start(toks[0])
    if st.year < 0: return "line {no}: error: bad start\n"

    let count = num_in(toks[1], 1, 20)
    if count < 0: return "line {no}: error: bad count\n"

    let mins = parse_field(toks[2], 0, 59)
    if mins.length() == 0: return "line {no}: error: bad minute\n"

    let hrs = parse_field(toks[3], 0, 23)
    if hrs.length() == 0: return "line {no}: error: bad hour\n"

    let dom = parse_field(toks[4], 1, 31)
    if dom.length() == 0: return "line {no}: error: bad day-of-month\n"

    let mon = parse_field(toks[5], 1, 12)
    if mon.length() == 0: return "line {no}: error: bad month\n"

    let dow = parse_field(toks[6], 0, 6)
    if dow.length() == 0: return "line {no}: error: bad day-of-week\n"

    let spec = Spec(minutes: mins, hours: hrs, days: dom, months: mon, weekdays: dow)
    let runs = search(st, count, spec)
    if runs.length() == 0: return "line {no}: never\n"

    var block = "line {no}: {runs.length()} runs\n"
    for r in runs:
        block += "{r}\n"
    return block

fn is_blank(line: String) Bool:
    for i in 0..line.length():
        if line.get(i) != " ": return false
    return true

export fn main() Int:
    let lines = read_lines(stdin()).get()
    var no = 0

    for line in lines:
        no += 1
        if is_blank(line): continue

        stdout().write(solve(no, line)).get()

    return 0
