import {stdin, stdout} from "@std/io.ms"
import read_lines from "@std/streams.ms"

# A calendar time to the minute; `year` is 0 when a parsed START was invalid.
type Stamp:
    year: Int
    month: Int
    day: Int
    hour: Int
    minute: Int

# Each field holds one flag per value, indexed by the value itself.
type Cron:
    minutes: List[Bool]
    hours: List[Bool]
    days: List[Bool]
    months: List[Bool]
    weekdays: List[Bool]

fn is_leap(year: Int) Bool:
    return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)

fn days_in_month(year: Int, month: Int) Int:
    if month == 2:
        return if is_leap(year): 29 else: 28
    if month == 4 or month == 6 or month == 9 or month == 11:
        return 30

    return 31

# Day of the week of a date, 0 for Sunday; 1970-01-01 was a Thursday.
fn weekday_of(year: Int, month: Int, day: Int) Int:
    var days = 0
    for y in 1970..year:
        days += if is_leap(y): 366 else: 365
    for m in 1..month:
        days += days_in_month(year, m)
    days += day - 1
    return (days + 4) % 7

# Returns the value of unsigned ASCII digits, or -1 for empty text or any other character.
fn digits_value(text: String) Int:
    if text.length() == 0: return -1

    for i in 0..text.length():
        if not "0123456789".contains(text.get(i)): return -1
    return text.parse_int().get(-1)

# Returns the value of a 1 or 2 digit number, or -1 otherwise.
fn parse_num(text: String) Int:
    if text.length() > 2: return -1

    return digits_value(text)

fn part(text: String, start: Int, end: Int) String:
    return text.slice(start, end).get("")

# Parses YYYY-MM-DDTHH:MM; the result has year 0 when the time is not valid.
fn parse_start(text: String) Stamp:
    let bad = Stamp(year: 0, month: 0, day: 0, hour: 0, minute: 0)
    if text.length() != 16: return bad
    if (
        text.get(4) != "-"
        or text.get(7) != "-"
        or text.get(10) != "T"
        or text.get(13) != ":"
    ):
        return bad

    let year = digits_value(part(text, 0, 4))
    let month = digits_value(part(text, 5, 7))
    let day = digits_value(part(text, 8, 10))
    let hour = digits_value(part(text, 11, 13))
    let minute = digits_value(part(text, 14, 16))
    if year < 1970 or year > 2099 or month < 1 or month > 12: return bad
    if day < 1 or day > days_in_month(year, month): return bad
    if hour < 0 or hour > 23 or minute < 0 or minute > 59: return bad

    return Stamp(year: year, month: month, day: day, hour: hour, minute: minute)

# Returns the COUNT value, or 0 when it is not in 1 through 20.
fn parse_count(text: String) Int:
    let n = parse_num(text)
    if n < 1 or n > 20: return 0

    return n

# Returns the values one cron item selects, or an empty list when the item is invalid.
fn parse_item(item: String, lo: Int, hi: Int) List[Int]:
    let parts = item.split("/")
    if parts.length() > 2: return List[Int]()

    var step = 1

    if parts.length() == 2:
        step = parse_num(parts[1])
        if step < 1: return List[Int]()

    var first = lo
    var last = hi

    if parts[0] != "*":
        let ends = parts[0].split("-")

        if ends.length() == 2:
            first = parse_num(ends[0])
            last = parse_num(ends[1])
        else if ends.length() == 1 and parts.length() == 1:
            first = parse_num(ends[0])
            last = first
        else:
            return List[Int]()

        if first < lo or last > hi or first > last: return List[Int]()

    var values = List[Int]()
    for v in first..(last + 1):
        if (v - first) % step == 0: values.append(v)
    return values

# Returns the flags a cron field selects, or an empty list when the field is invalid.
fn parse_field(text: String, lo: Int, hi: Int) List[Bool]:
    var chosen = List[Bool]()
    for v in 0..(hi + 1):
        chosen.append(false)

    for item in text.split(","):
        let values = parse_item(item, lo, hi)
        if values.length() == 0: return List[Bool]()

        for v in values:
            chosen[v] = true

    return chosen

impl Cron:
    # The first `count` matching minutes strictly after `start`, searching 3000 days past its date.
    fn runs(start: Stamp, count: Int) List[Stamp]:
        var found = List[Stamp]()
        var at = start.clone()
        var weekday = weekday_of(at.year, at.month, at.day)

        for offset in 0..3001:
            if self.months[at.month] and self.days[at.day] and self.weekdays[weekday]:
                for hour in 0..24:
                    if not self.hours[hour]: continue

                    for minute in 0..60:
                        if not self.minutes[minute]: continue
                        if (
                            offset == 0
                            and (
                                hour < start.hour
                                or (
                                    hour == start.hour
                                    and minute <= start.minute
                                )
                            )
                        ):
                            continue

                        found.append(
                            Stamp(
                                year: at.year, month: at.month, day: at.day, hour: hour,
                                minute: minute
                            )
                        )
                        if found.length() == count: return found

            at.day += 1

            if at.day > days_in_month(at.year, at.month):
                at.day = 1
                at.month += 1

                if at.month > 12:
                    at.month = 1
                    at.year += 1

            weekday = (weekday + 1) % 7

        return found

fn pad(n: Int) String:
    if n < 10: return "0{n}"

    return "{n}"

fn stamp_text(s: Stamp) String:
    return "{s.year}-{pad(s.month)}-{pad(s.day)} {pad(s.hour)}:{pad(s.minute)}"

fn is_blank(line: String) Bool:
    for i in 0..line.length():
        if line.get(i) != " ": return false
    return true

# The output for one non-blank input line, without its final newline.
fn solve(n: Int, raw: String) String:
    let head = "line {n}: "
    let tok = raw.split(" ")
    if tok.length() != 7: return head + "error: bad line"

    let start = parse_start(tok[0])
    if start.year == 0: return head + "error: bad start"

    let count = parse_count(tok[1])
    if count == 0: return head + "error: bad count"

    let minutes = parse_field(tok[2], 0, 59)
    if minutes.length() == 0: return head + "error: bad minute"

    let hours = parse_field(tok[3], 0, 23)
    if hours.length() == 0: return head + "error: bad hour"

    let days = parse_field(tok[4], 1, 31)
    if days.length() == 0: return head + "error: bad day-of-month"

    let months = parse_field(tok[5], 1, 12)
    if months.length() == 0: return head + "error: bad month"

    let weekdays = parse_field(tok[6], 0, 6)
    if weekdays.length() == 0: return head + "error: bad day-of-week"

    let cron = Cron(
        minutes: minutes, hours: hours, days: days, months: months, weekdays: weekdays
    )
    let runs = cron.runs(start, count)
    if runs.length() == 0: return head + "never"

    var text = head + "{runs.length()} runs"
    for r in runs:
        text += "\n" + stamp_text(r)
    return text

export fn main() Int:
    let lines = read_lines(stdin()).get()
    var n = 0

    for raw in lines:
        n += 1
        if is_blank(raw): continue

        stdout().write(solve(n, raw) + "\n").get()

    return 0
