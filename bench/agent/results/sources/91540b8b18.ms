from "@std/io.ms" import stdin, stdout
from "@std/streams.ms" import read_lines
from "@std/collections.ms" import range

type Stamp:
    year: Int
    month: Int
    day: Int
    hour: Int
    minute: Int

def is_leap(y: Int) -> Bool: (y % 4 == 0 and y % 100 != 0) or y % 400 == 0

def days_in_year(y: Int) -> Int:
    if is_leap(y): return 366

    return 365

def days_in_month(y: Int, m: Int) -> Int:
    if m == 2:
        if is_leap(y): return 29

        return 28

    if m == 4 or m == 6 or m == 9 or m == 11: return 30

    return 31

def all_digits(s: String) -> Bool:
    for c in s.chars():
        if not "0123456789".contains(c): return False
    return True

# One or two ASCII digits.
def parse_num(s: String) -> Optional[Int]:
    if s.length() < 1 or s.length() > 2 or not all_digits(s): return none

    return s.parse_int()

def parse_fixed(s: String, width: Int) -> Optional[Int]:
    if s.length() != width or not all_digits(s): return none

    return s.parse_int()

def pad2(n: Int) -> String:
    if n < 10: return f"0{n}"

    return f"{n}"

def weekday(st: Stamp) -> Int:
    var days = 0
    var y = 1970

    while y < st.year:
        days += days_in_year(y)
        y += 1

    var m = 1

    while m < st.month:
        days += days_in_month(st.year, m)
        m += 1

    # 1970-01-01 was a Thursday, which is 4 with Sunday as 0.
    return (days + st.day - 1 + 4) % 7

def parse_start(s: String) -> Optional[Stamp]:
    let halves = s.split("T")
    if halves.length() != 2: return none

    let date = halves[0].split("-")
    let time = halves[1].split(":")
    if date.length() != 3 or time.length() != 2: return none

    let year = parse_fixed(date[0], 4)
    let month = parse_fixed(date[1], 2)
    let day = parse_fixed(date[2], 2)
    let hour = parse_fixed(time[0], 2)
    let minute = parse_fixed(time[1], 2)
    if (
        year.is_none()
        or month.is_none()
        or day.is_none()
        or hour.is_none()
        or minute.is_none()
    ): return none

    let y = year.get()
    let mo = month.get()
    let d = day.get()
    if y < 1970 or y > 2099: return none
    if mo < 1 or mo > 12: return none
    if d < 1 or d > days_in_month(y, mo): return none
    if hour.get() > 23 or minute.get() > 59: return none

    return some(
        Stamp(
            year: y, month: mo, day: d, hour: hour.get(), minute: minute.get()
        )
    )

# Values selected by one cron item: `*`, `*/S`, `A`, `A-B`, or `A-B/S`.
def item_values(item: String, lo: Int, hi: Int) -> Optional[List[Int]]:
    let parts = item.split("/")
    if parts.length() > 2: return none

    var step = 1

    if parts.length() == 2:
        let s = parse_num(parts[1])
        if s.is_none(): return none

        step = s.get()
        if step < 1: return none

    var first = lo
    var last = hi

    if parts[0] != "*":
        let bounds = parts[0].split("-")
        if bounds.length() > 2: return none

        let a = parse_num(bounds[0])
        if a.is_none(): return none

        first = a.get()

        if bounds.length() == 2:
            let b = parse_num(bounds[1])
            if b.is_none(): return none

            last = b.get()
        else:
            if parts.length() == 2: return none

            last = first

    if first < lo or last > hi or first > last: return none

    var values = List[Int]()
    var v = first

    while v <= last:
        values.append(v)
        v += step

    return some(values)

def parse_field(text: String, lo: Int, hi: Int) -> Optional[Set[Int]]:
    var values = Set[Int]()

    for item in text.split(","):
        let items = item_values(item, lo, hi)
        if items.is_none(): return none

        for v in items.get():
            values.add(v)

    return some(values)

def pad_stamp(st: Stamp) -> String:
    return f"{st.year}-{pad2(st.month)}-{pad2(st.day)} {pad2(st.hour)}:{pad2(st.minute)}"

# Finds up to `count` matching minutes strictly after `st`, searching 3000 days past its date.
def next_runs(
    st: Stamp,
    count: Int,
    minutes: Set[Int],
    hours: Set[Int],
    doms: Set[Int],
    months: Set[Int],
    dows: Set[Int]
) -> List[Stamp]:
    var found = List[Stamp]()
    var y = st.year + 0
    var mo = st.month + 0
    var d = st.day + 0
    var wd = weekday(st)
    var k = 0

    while k <= 3000 and found.length() < count:
        if months.contains(mo) and doms.contains(d) and dows.contains(wd):
            for h in range(0, 24):
                if not hours.contains(h): continue

                for m in range(0, 60):
                    if found.length() >= count: break
                    if not minutes.contains(m): continue
                    if k == 0 and (h < st.hour or (h == st.hour and m <= st.minute)): continue

                    found.append(Stamp(year: y, month: mo, day: d, hour: h, minute: m))

        k += 1
        d += 1

        if d > days_in_month(y, mo):
            d = 1
            mo += 1

            if mo > 12:
                mo = 1
                y += 1

        wd = (wd + 1) % 7

    return found

def is_blank(line: String) -> Bool:
    for c in line.chars():
        if c != " ": return False
    return True

def solve(line: String, n: Int) -> List[String]:
    let head = f"line {n}:"
    let tokens = line.split(" ")
    if tokens.length() != 7: return [f"{head} error: bad line"]

    let start = parse_start(tokens[0])
    if start.is_none(): return [f"{head} error: bad start"]

    let count = parse_num(tokens[1])
    if count.is_none() or count.get() < 1 or count.get() > 20: return [
        f"{head} error: bad count"
    ]

    let minutes = parse_field(tokens[2], 0, 59)
    if minutes.is_none(): return [f"{head} error: bad minute"]

    let hours = parse_field(tokens[3], 0, 23)
    if hours.is_none(): return [f"{head} error: bad hour"]

    let doms = parse_field(tokens[4], 1, 31)
    if doms.is_none(): return [f"{head} error: bad day-of-month"]

    let months = parse_field(tokens[5], 1, 12)
    if months.is_none(): return [f"{head} error: bad month"]

    let dows = parse_field(tokens[6], 0, 6)
    if dows.is_none(): return [f"{head} error: bad day-of-week"]

    let runs = next_runs(
        start.get(), count.get(), minutes.get(), hours.get(), doms.get(), months.get(),
        dows.get()
    )
    if runs.length() == 0: return [f"{head} never"]

    var out = [f"{head} {runs.length()} runs"]
    for run in runs:
        out.append(pad_stamp(run))
    return out

export def main() -> Int:
    let lines = read_lines(stdin()).get()
    var out = List[String]()
    var n = 0

    for line in lines:
        n += 1
        if is_blank(line): continue

        for s in solve(line, n):
            out.append(s)

    if out.length() > 0:
        stdout().write(out.join("\n") + "\n").get()
    return 0
