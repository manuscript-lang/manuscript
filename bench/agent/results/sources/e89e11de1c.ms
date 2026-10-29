import {read_lines} from "@std/streams.ms"
import {stdin, stdout} from "@std/io.ms"

# Calendar days searched after START's date, inclusive.
let WINDOW_DAYS = 3000

type Start:
    year: Int  # -1 when START is invalid
    month: Int
    day: Int
    minute_of_day: Int

type Schedule:
    minutes: List[Bool]
    hours: List[Bool]
    days: List[Bool]
    months: List[Bool]
    weekdays: List[Bool]

# Value of an unsigned ASCII digit string; -1 when empty or with any other character.
fn number(text: String) Int:
    if text.length() == 0: return -1

    var value = 0

    for c in text.chars():
        let digit = c.parse_int().get(-1)
        if digit < 0: return -1

        value = value * 10 + digit

    return value

# A 1-2 digit number within low..high; -1 otherwise.
fn small(text: String, low: Int, high: Int) Int:
    if text.length() == 0 or text.length() > 2: return -1

    let value = number(text)
    if value < low or value > high: return -1

    return value

fn in_range(value: Int, low: Int, high: Int) Bool:
    return value >= low and value <= high

fn is_leap(year: Int) Bool:
    return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)

fn days_in_month(year: Int, month: Int) Int:
    if month == 2:
        if is_leap(year): return 29

        return 28

    if month == 4 or month == 6 or month == 9 or month == 11: return 30

    return 31

# Whole days from 1970-01-01 to the given date.
fn days_since_epoch(year: Int, month: Int, day: Int) Int:
    var days = 0

    for y in 1970..year:
        days += 365
        if is_leap(y): days += 1

    for m in 1..month:
        days += days_in_month(year, m)
    return days + day - 1

fn parse_start(text: String) Start:
    let invalid = Start(year: -1, month: 0, day: 0, minute_of_day: 0)
    let halves = text.split("T")
    if halves.length() != 2: return invalid

    let date = halves[0].split("-")
    let time = halves[1].split(":")
    if date.length() != 3 or time.length() != 2: return invalid
    if date[0].length() != 4 or date[1].length() != 2 or date[2].length() != 2: return invalid
    if time[0].length() != 2 or time[1].length() != 2: return invalid

    let year = number(date[0])
    let month = number(date[1])
    let day = number(date[2])
    let hour = number(time[0])
    let minute = number(time[1])
    if not in_range(year, 1970, 2099) or not in_range(month, 1, 12): return invalid
    if not in_range(day, 1, days_in_month(year, month)): return invalid
    if not in_range(hour, 0, 23) or not in_range(minute, 0, 59): return invalid

    return Start(year: year, month: month, day: day, minute_of_day: hour * 60 + minute)

# Allowed values as a list indexed by value (size high + 1); empty when the field is invalid.
fn parse_field(text: String, low: Int, high: Int) List[Bool]:
    var allowed = List[Bool]()
    for ignored in 0..high + 1:
        allowed.append(false)
    if text.length() == 0: return List[Bool]()

    for item in text.split(","):
        let parts = item.split("/")
        if item.length() == 0 or parts.length() > 2: return List[Bool]()

        var first = low
        var last = high
        var step = 1

        if parts.length() == 2:
            step = small(parts[1], 1, 99)
            if step < 0: return List[Bool]()

        if parts[0] != "*":
            let range = parts[0].split("-")

            if range.length() == 2:
                first = small(range[0], low, high)
                last = small(range[1], low, high)
                if first < 0 or last < 0 or first > last: return List[Bool]()
            else if parts.length() == 1:
                first = small(parts[0], low, high)
                last = first
                if first < 0: return List[Bool]()
            else:
                return List[Bool]()

        var v = first

        while v <= last:
            allowed[v] = true
            v += step

    return allowed

# Formats a run as YYYY-MM-DD HH:MM.
fn two(n: Int) String:
    return "{n}".pad_start(2, "0")

fn format_run(year: Int, month: Int, day: Int, minute_of_day: Int) String:
    let hour = minute_of_day / 60
    let minute = minute_of_day % 60
    return "{year}-{two(month)}-{two(day)} {two(hour)}:{two(minute)}"

fn find_runs(
    start_year: Int,
    start_month: Int,
    start_day: Int,
    start_minute: Int,
    count: Int,
    schedule: Schedule
) List[String]:
    var runs = List[String]()
    var year = start_year
    var month = start_month
    var day = start_day
    var weekday = (4 + days_since_epoch(year, month, day)) % 7  # 1970-01-01 was a Thursday
    var offset = 0

    while offset <= WINDOW_DAYS and runs.length() < count:
        if schedule.months[month] and schedule.days[day] and schedule.weekdays[weekday]:
            for t in 0..1440:
                if runs.length() < count and (offset > 0 or t > start_minute):
                    if schedule.hours[t / 60] and schedule.minutes[t % 60]:
                        runs.append(format_run(year, month, day, t))
        day += 1

        if day > days_in_month(year, month):
            day = 1
            month += 1

            if month > 12:
                month = 1
                year += 1

        weekday = (weekday + 1) % 7
        offset += 1

    return runs

fn describe(line: String, line_no: Int) String:
    let prefix = "line {line_no}: "
    let tokens = line.split(" ")
    if tokens.length() != 7: return prefix + "error: bad line\n"

    let start = parse_start(tokens[0])
    if start.year < 0: return prefix + "error: bad start\n"

    let count = small(tokens[1], 1, 20)
    if count < 0: return prefix + "error: bad count\n"

    let minutes = parse_field(tokens[2], 0, 59)
    if minutes.length() == 0: return prefix + "error: bad minute\n"

    let hours = parse_field(tokens[3], 0, 23)
    if hours.length() == 0: return prefix + "error: bad hour\n"

    let days = parse_field(tokens[4], 1, 31)
    if days.length() == 0: return prefix + "error: bad day-of-month\n"

    let months = parse_field(tokens[5], 1, 12)
    if months.length() == 0: return prefix + "error: bad month\n"

    let weekdays = parse_field(tokens[6], 0, 6)
    if weekdays.length() == 0: return prefix + "error: bad day-of-week\n"

    let schedule = Schedule(
        minutes: minutes, hours: hours, days: days, months: months, weekdays: weekdays
    )
    let runs = find_runs(
        start.year, start.month, start.day, start.minute_of_day, count, schedule
    )
    if runs.length() == 0: return prefix + "never\n"

    var out = prefix + "{runs.length()} runs\n"
    for run in runs:
        out += run + "\n"
    return out

fn is_blank(line: String) Bool:
    for c in line.chars():
        if c != " ": return false
    return true

export fn main() Int:
    let lines = read_lines(stdin()).get()
    var out = ""
    var line_no = 0

    for line in lines:
        line_no += 1
        if not is_blank(line):
            out += describe(line, line_no)

    stdout().write(out).get()
    return 0
