# Generator for c18-cron-next-runs. Deterministic; run: ms run bench/agent/gen.ms -- c18
import GenCase, make_case, write_cases from "../../lib/gen.ms"
import seeded from "../../lib/pyrandom.ms"
import Random from "../../lib/pyrandom.ms"
import full_match from "../../lib/text.ms"

let NUM2 = "[0-9]\{1,2\}"

type Range:
    name: String
    low: Int
    high: Int

fn ranges() List[Range]:
    return [
        Range("minute", 0, 59), Range("hour", 0, 23), Range("day-of-month", 1, 31),
        Range("month", 1, 12), Range("day-of-week", 0, 6)
    ]

# Days since 1970-01-01 of a proleptic Gregorian date.
fn days_from_civil(year: Int, month: Int, day: Int) Int:
    let y = if month <= 2: year - 1 else: year
    let era = (if y >= 0: y else: y - 399) / 400
    let yoe = y - era * 400
    let doy = (153 * (if month > 2: month - 3 else: month + 9) + 2) / 5 + day - 1
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
    return era * 146097 + doe - 719468

# The year, month and day of a count of days since 1970-01-01.
fn civil_from_days(days: Int) List[Int]:
    let z = days + 719468
    let era = (if z >= 0: z else: z - 146096) / 146097
    let doe = z - era * 146097
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
    let mp = (5 * doy + 2) / 153
    let day = doy - (153 * mp + 2) / 5 + 1
    let month = if mp < 10: mp + 3 else: mp - 9
    let year = yoe + era * 400 + (if month <= 2: 1 else: 0)
    return [year, month, day]

fn days_in_month(year: Int, month: Int) Int:
    if month == 2: return if (year % 4 == 0 and year % 100 != 0) or year % 400 == 0: 29 else: 28

    return if month == 4 or month == 6 or month == 9 or month == 11: 30 else: 31

fn pad(n: Int, width: Int) String: "{n}".pad_start(width, "0")

# `YYYY-MM-DD HH:MM` for a count of minutes since the epoch, with `sep` between date and time.
fn stamp(minutes: Int, sep: String) String:
    let days = minutes / 1440
    let c = civil_from_days(days)
    let rest = minutes - days * 1440
    return "{pad(c[0], 4)}-{pad(c[1], 2)}-{pad(c[2], 2)}{sep}{pad(rest / 60, 2)}:{pad(rest % 60, 2)}"

# The values a field selects, or none when it is malformed or out of range.
fn parse_field(text: String, lo: Int, hi: Int) List[Int]?:
    var vals = Set[Int]()

    for item in text.split(","):
        var step = 1
        var body = item.clone()
        var stepped = false
        let slash = item.last_index_of("/")

        if (
            slash.is_some()
            and full_match(
                NUM2, item.slice(slash.get(0) + 1, item.length()).get("")
            )
        ):
            body = item.slice(0, slash.get(0)).get("")
            step = item.slice(
                slash.get(0) + 1, item.length()
            ).get("").parse_int().get(0)
            stepped = true
            if step < 1: return none
            if not (body == "*" or full_match("[0-9]\{1,2\}-[0-9]\{1,2\}", body)): return none

        var a = 0
        var b = 0

        if body == "*":
            a = lo
            b = hi
        else if full_match(NUM2, body):
            if stepped: return none

            a = body.parse_int().get(0)
            b = a
        else:
            if not full_match("[0-9]\{1,2\}-[0-9]\{1,2\}", body): return none

            let ends = body.split("-")
            a = ends[0].parse_int().get(0)
            b = ends[1].parse_int().get(0)
            if a > b: return none

        if a < lo or b > hi: return none

        var v = a

        while v <= b:
            vals.add(v)
            v += step

    let out: List[Int] = vals.values()
    return out

fn solve(s: String) String:
    var lines = s.split("\n")
    if not lines.is_empty() and lines[lines.length() - 1] == "": lines.pop()

    var out = List[String]()

    for n in 1..lines.length() + 1:
        let l = lines[n - 1].clone()
        if l.replace(" ", "") == "": continue

        let t = l.split(" ")
        let pre = "line {n}:"

        if t.length() != 7:
            out.append("{pre} error: bad line")
            continue

        var start = -1

        if full_match("[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}T[0-9]\{2\}:[0-9]\{2\}", t[0]):
            let y = t[0].slice(0, 4).get("").parse_int().get(0)
            let mo = t[0].slice(5, 7).get("").parse_int().get(0)
            let d = t[0].slice(8, 10).get("").parse_int().get(0)
            let h = t[0].slice(11, 13).get("").parse_int().get(0)
            let mi = t[0].slice(14, 16).get("").parse_int().get(0)
            let valid = (
                mo >= 1
                and mo <= 12
                and d >= 1
                and d <= days_in_month(y, mo)
                and h <= 23
                and mi <= 59
            )
            if valid and y >= 1970 and y <= 2099: start = (
                days_from_civil(y, mo, d) * 1440
                + h * 60
                + mi
            )

        if start < 0:
            out.append("{pre} error: bad start")
            continue

        if (
            not full_match(NUM2, t[1])
            or t[1].parse_int().get(0) < 1
            or t[1].parse_int().get(0) > 20
        ):
            out.append("{pre} error: bad count")
            continue

        let count = t[1].parse_int().get(0)
        var sets = List[List[Int]]()
        var bad = ""
        var k = 0

        for r in ranges():
            if let v = parse_field(t[2 + k], r.low, r.high):
                sets.append(v)
            else:
                bad = r.name.clone()
                break

            k += 1

        if bad != "":
            out.append("{pre} error: bad {bad}")
            continue

        let minutes = sets[0].sorted()
        let hours = sets[1].sorted()
        var runs = List[Int]()
        let day0 = start / 1440

        for dk in 0..3001:
            let day = day0 + dk
            let c = civil_from_days(day)
            let weekday = ((day + 4) % 7 + 7) % 7
            if (
                not sets[3].contains(c[1])
                or not sets[2].contains(c[2])
                or not sets[4].contains(weekday)
            ): continue

            for h in hours:
                for mn in minutes:
                    let t2 = day * 1440 + h * 60 + mn

                    if t2 > start:
                        runs.append(t2)
                        if runs.length() == count: break

                if runs.length() == count: break

            if runs.length() == count: break

        if runs.is_empty():
            out.append("{pre} never")
            continue

        out.append("{pre} {runs.length()} runs")
        for r in runs: out.append(stamp(r, " "))

    return out.map(fn x: x + "\n").join("")

fn mk(name: String, s: String) GenCase: make_case(name, s, solve(s))

fn rand_field(var rnd: Random, lo: Int, hi: Int) String:
    let a = "*/{rnd.randint(1, 7)}"
    let b = "{rnd.randint(lo, hi)}"
    let c = "{lo}-{rnd.randint(lo, hi)}".replace("{lo}-{lo}", "{lo}")
    let d1 = rnd.randint(lo, hi)
    let d2 = rnd.randint(lo, hi)
    return rnd.choice(["*", a, b, c, "{d1},{d2}"])

fn rand_line(var rnd: Random) String:
    var fields = List[String]()
    let rs = ranges()
    fields.append(rand_field(var rnd, 0, 59))
    fields.append(rand_field(var rnd, 0, 23))
    fields.append(rand_field(var rnd, 1, 31))
    fields.append(rand_field(var rnd, 1, 12))
    fields.append(rand_field(var rnd, 0, 6))

    var checked = List[String]()
    for i in 0..5: checked.append(
        if parse_field(fields[i], rs[i].low, rs[i].high).is_some(): fields[
            i
        ].clone() else: "*"
    )

    let when = stamp(rnd.randint(0, 60 * 24 * 365 * 129), "T")
    return "{when} {rnd.randint(1, 20)} {checked.join(" ")}"

export fn gen_c18() Unit:
    var rnd = seeded(18)
    let examples = [
        mk(
            "basic",
            "2024-02-28T23:59 3 0 0 * * *\n2024-01-31T12:00 2 30 8 29 2 *\n2024-03-01T00:00 2 0 12 * * 1-5/2\n"
        ),
        mk("weekdays", "2024-02-28T23:59 3 */15 9-17 * * 1-5\n")
    ]
    var random_lines = List[String]()
    for _i in 0..40: random_lines.append(rand_line(var rnd))

    let hidden = examples.concat(
        [
            mk(
                "start-excluded",
                "2024-05-05T10:30 3 30 10 * * *\n2024-05-05T10:29 1 30 10 * * *\n"
            ),
            mk("every-minute-rollover", "2023-12-31T23:58 4 * * * * *\n"),
            mk("leap-day", "2023-03-01T00:00 5 0 0 29 2 *\n"),
            mk(
                "never",
                "2024-01-01T00:00 3 0 0 31 2 *\n2024-01-01T00:00 3 0 0 31 4,6,9,11 *\n"
            ),
            mk("window-limit", "2024-01-01T00:00 10 0 0 29 2 *\n"),
            mk(
                "lists-and-steps",
                "2024-01-01T00:00 8 0,30 8-10,14 * * *\n2024-01-01T00:00 6 5-25/10 */6 1,15 * *\n"
            ),
            mk("dow-and-dom-both", "2024-01-01T00:00 4 0 0 13 * 5\n"),
            mk("sunday-saturday", "2024-02-24T00:00 4 0 12 * * 0,6\n"),
            mk(
                "month-names-rejected-and-fields",
                "2024-01-01T00:00 1 0 0 * JAN *\n2024-01-01T00:00 1 60 0 * * *\n2024-01-01T00:00 1 0 24 * * *\n2024-01-01T00:00 1 0 0 0 * *\n2024-01-01T00:00 1 0 0 32 * *\n2024-01-01T00:00 1 0 0 * 13 *\n2024-01-01T00:00 1 0 0 * * 7\n"
            ),
            mk(
                "bad-syntax",
                "2024-01-01T00:00 1 */0 * * * *\n2024-01-01T00:00 1 5/2 * * * *\n2024-01-01T00:00 1 5-3 * * * *\n2024-01-01T00:00 1 1,,2 * * * *\n2024-01-01T00:00 1 1, * * * * *\n2024-01-01T00:00 1 -1 * * * *\n2024-01-01T00:00 1 *-5 * * * *\n2024-01-01T00:00 1 1-2-3 * * * *\n2024-01-01T00:00 1 */1/2 * * * *\n2024-01-01T00:00 1 001 * * * *\n2024-01-01T00:00 1 * 1 - * * *\n"
            ),
            mk(
                "bad-start-count-tokens",
                "2024-02-30T00:00 1 * * * * *\n2024-01-01 00:00 1 * * * * *\n1969-12-31T23:59 1 * * * * *\n2100-01-01T00:00 1 * * * * *\n2024-01-01T24:00 1 * * * * *\n2024-1-1T00:00 1 * * * * *\n2024-01-01T00:00 0 * * * * *\n2024-01-01T00:00 21 * * * * *\n2024-01-01T00:00 x * * * * *\n2024-01-01T00:00 001 * * * * *\n2024-01-01T00:00 1 * * * *\n2024-01-01T00:00 1 * * * * * *\n2024-01-01T00:00  1 * * * * *\n"
            ),
            mk(
                "check-order",
                "x y z\nx 99 bad bad bad bad bad\n2024-01-01T00:00 99 bad bad bad bad bad\n2024-01-01T00:00 1 bad bad bad bad bad\n2024-01-01T00:00 1 0 bad bad bad bad\n"
            ),
            mk(
                "blank-lines-numbering",
                "\n  \n2024-01-01T00:00 1 0 12 * * *\n\n2024-01-01T00:00 1 bad\n"
            ),
            mk(
                "year-edges",
                "1970-01-01T00:00 2 0 0 * * 4\n2099-12-31T23:59 3 * * * * *\n2099-12-31T23:58 2 59 23 31 12 *\n"
            ),
            mk("random", random_lines.join("\n") + "\n")
        ]
    )
    write_cases("c18-cron-next-runs", examples, hidden)
