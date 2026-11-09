import read_all from "@std/io/streams.ms"
import stdin, stdout from "@std/io/io.ms"

type Day:
    y: Int
    m: Int
    d: Int

// True when s is one or more ASCII digits.
fn is_digits(s: String) Bool:
    if s.length() == 0: return false

    for i in 0..s.length():
        if not ("0123456789".contains(s.get(i))): return false
    return true

// Value of a string already known to be digits.
fn digits_value(s: String) Int:
    return s.parse_int().get(0)

// True for 1 or 2 ASCII digits.
fn small_num(s: String) Bool:
    return is_digits(s) and s.length() <= 2

fn days_in(y: Int, m: Int) Int:
    if m == 2:
        if (y % 4 == 0 and y % 100 != 0) or y % 400 == 0: return 29

        return 28

    if m == 4 or m == 6 or m == 9 or m == 11: return 30

    return 31

// Days since 1970-01-01 (proleptic Gregorian).
fn days_from_civil(y0: Int, m: Int, d: Int) Int:
    let y = if m <= 2: y0 - 1 else: y0
    let era = y / 400
    let yoe = y - era * 400
    let mp = if m > 2: m - 3 else: m + 9
    let doy = (153 * mp + 2) / 5 + d - 1
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
    return era * 146097 + doe - 719468

// Inverse of days_from_civil for non-negative day numbers.
fn civil_from_days(z0: Int) Day:
    let z = z0 + 719468
    let era = z / 146097
    let doe = z - era * 146097
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
    let mp = (5 * doy + 2) / 153
    let d = doy - (153 * mp + 2) / 5 + 1
    let m = if mp < 10: mp + 3 else: mp - 9
    var y = yoe + era * 400
    if m <= 2: y += 1
    return Day(y: y, m: m, d: d)

fn pad(n: Int, w: Int) String:
    var s = "{n}"
    while s.length() < w:
        s = "0" + s
    return s

// Sets the values selected by one cron item; false when the item is invalid.
fn apply_item(var out: List[Bool], item: String, lo: Int, hi: Int) Bool:
    if item == "*":
        for v in lo..(hi + 1):
            out[v] = true
        return true

    let parts = item.split("/")
    if parts.length() > 2: return false

    var step = 1

    if parts.length() == 2:
        if not small_num(parts[1]): return false

        step = digits_value(parts[1])
        if step < 1: return false

    let base = parts[0]
    var a = lo
    var b = hi

    if base == "*":
        a = lo
        b = hi
    else:
        let rng = base.split("-")

        if rng.length() == 1:
            if parts.length() == 2: return false
            if not small_num(base): return false

            a = digits_value(base)
            if a < lo or a > hi: return false

            b = a
        else if rng.length() == 2:
            if not small_num(rng[0]) or not small_num(rng[1]): return false

            a = digits_value(rng[0])
            b = digits_value(rng[1])
            if a < lo or b > hi or a > b: return false
        else:
            return false

    var v = a

    while v <= b:
        out[v] = true
        v += step

    return true

// Parses a cron field into a membership list indexed by value; empty when invalid.
fn parse_field(text: String, lo: Int, hi: Int) List[Bool]:
    var out = List[Bool]()
    for i in 0..(hi + 1):
        out.append(false)
    for item in text.split(","):
        if not apply_item(var out, item, lo, hi):
            return List[Bool]()
    return out

// START as minutes since epoch; -1 when invalid.
fn parse_start(s: String) Int:
    let halves = s.split("T")
    if halves.length() != 2: return -1

    let dp = halves[0].split("-")
    let tp = halves[1].split(":")
    if dp.length() != 3 or tp.length() != 2: return -1
    if dp[0].length() != 4 or dp[1].length() != 2 or dp[2].length() != 2: return -1
    if tp[0].length() != 2 or tp[1].length() != 2: return -1
    if not is_digits(dp[0]) or not is_digits(dp[1]) or not is_digits(dp[2]): return -1
    if not is_digits(tp[0]) or not is_digits(tp[1]): return -1

    let y = digits_value(dp[0])
    let mo = digits_value(dp[1])
    let d = digits_value(dp[2])
    let h = digits_value(tp[0])
    let mi = digits_value(tp[1])
    if y < 1970 or y > 2099: return -1
    if mo < 1 or mo > 12: return -1
    if d < 1 or d > days_in(y, mo): return -1
    if h > 23 or mi > 59: return -1

    return days_from_civil(y, mo, d) * 1440 + h * 60 + mi

fn pad_time(t: Int) String:
    let dt = civil_from_days(t / 1440)
    let tod = t % 1440
    let ds = pad(dt.y, 4) + "-" + pad(dt.m, 2) + "-" + pad(dt.d, 2)
    let ts = pad(tod / 60, 2) + ":" + pad(tod % 60, 2)
    return ds + " " + ts

fn solve(line: String, n: Int) String:
    let head = "line {n}: "
    let tokens = line.split(" ")
    if tokens.length() != 7: return head + "error: bad line"

    let start = parse_start(tokens[0])
    if start < 0: return head + "error: bad start"

    let count_tok = tokens[1]
    if not small_num(count_tok): return head + "error: bad count"

    let want = digits_value(count_tok)
    if want < 1 or want > 20: return head + "error: bad count"

    let mins = parse_field(tokens[2], 0, 59)
    if mins.length() == 0: return head + "error: bad minute"

    let hours = parse_field(tokens[3], 0, 23)
    if hours.length() == 0: return head + "error: bad hour"

    let doms = parse_field(tokens[4], 1, 31)
    if doms.length() == 0: return head + "error: bad day-of-month"

    let mons = parse_field(tokens[5], 1, 12)
    if mons.length() == 0: return head + "error: bad month"

    let dows = parse_field(tokens[6], 0, 6)
    if dows.length() == 0: return head + "error: bad day-of-week"

    // Time-of-day values (minutes since midnight) that match, ascending.
    var tods = List[Int]()
    for h in 0..24:
        if hours[h]:
            for mi in 0..60:
                if mins[mi]: tods.append(h * 60 + mi)

    let start_day = start / 1440
    let start_tod = start % 1440
    var found = List[Int]()
    var k = 0

    while k <= 3000 and found.length() < want:
        let day = start_day + k
        let dt = civil_from_days(day)
        let dow = (day + 4) % 7

        if mons[dt.m] and doms[dt.d] and dows[dow]:
            var j = 0

            while j < tods.length() and found.length() < want:
                let t = tods[j]
                if not (k == 0 and t <= start_tod):
                    found.append(day * 1440 + t)
                j += 1

        k += 1

    if found.length() == 0: return head + "never"

    var block = List[String]()
    block.append(head + "{found.length()} runs")
    for t in found:
        block.append(pad_time(t))
    return block.join("\n")

export fn main() Int:
    let text = read_all(stdin()).get().decode_utf8().get("")
    let pieces = text.split("\n")
    var out = List[String]()

    for i in 0..pieces.length():
        let line = pieces[i]

        // A final newline leaves an empty last piece that is not a line.
        if i == pieces.length() - 1 and line == "": continue
        if line.trim_chars(" ") == "": continue

        out.append(solve(line, i + 1))

    if out.length() > 0:
        stdout().write(out.join("\n") + "\n").get()
    return 0
