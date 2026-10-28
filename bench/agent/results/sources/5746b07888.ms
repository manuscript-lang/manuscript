import {stdin, stdout} from "@std/io.ms"
import read_lines from "@std/streams.ms"

type Bad:
    text: String

impl Error for Bad:
    fn message() String: self.text.clone()

type Stamp:
    year: Int
    month: Int
    day: Int
    hour: Int
    minute: Int

type Cron:
    minutes: List[Bool]
    hours: List[Bool]
    days: List[Bool]
    months: List[Bool]
    weekdays: List[Bool]

type Job:
    start: Stamp
    count: Int
    cron: Cron

fn is_leap(year: Int) Bool:
    return (year % 4 == 0 and year % 100 != 0) or year % 400 == 0

fn days_in_month(year: Int, month: Int) Int:
    if month == 2: return if is_leap(year): 29 else: 28
    if month == 4 or month == 6 or month == 9 or month == 11: return 30

    return 31

fn all_digits(text: String) Bool:
    let codes = text.scalar_values()
    if codes.length() == 0: return false

    for c in codes:
        if c < 48 or c > 57: return false
    return true

# A one- or two-digit number inside `low` through `high`.
fn small_number(text: String, low: Int, high: Int) Optional[Int]:
    if not all_digits(text) or text.length() > 2: return none

    let value = text.parse_int().get(0)
    if value < low or value > high: return none

    return value

fn valid_start_shape(text: String) Bool:
    let cs = text.chars()
    if cs.length() != 16: return false

    for i in 0..16:
        let c = cs[i]

        if i == 4 or i == 7:
            if c != "-": return false
        else if i == 10:
            if c != "T": return false
        else if i == 13:
            if c != ":": return false
        else if not all_digits(c):
            return false

    return true

fn parse_start(text: String) Result[Stamp, Bad]:
    if not valid_start_shape(text): return error(Bad(text: "bad start"))

    let year = text.take(4).parse_int().get(0)
    let month = text.drop(5).take(2).parse_int().get(0)
    let day = text.drop(8).take(2).parse_int().get(0)
    let hour = text.drop(11).take(2).parse_int().get(0)
    let minute = text.drop(14).take(2).parse_int().get(0)
    if year < 1970 or year > 2099 or month < 1 or month > 12: return error(
        Bad(text: "bad start")
    )
    if day < 1 or day > days_in_month(year, month) or hour > 23 or minute > 59: return error(
        Bad(text: "bad start")
    )

    return ok(Stamp(year: year, month: month, day: day, hour: hour, minute: minute))

fn parse_count(text: String) Result[Int, Bad]:
    if let count = small_number(text, 1, 20):
        return ok(count)

    return error(Bad(text: "bad count"))

# The values one cron item selects, or none when the item is malformed.
fn item_values(item: String, low: Int, high: Int) Optional[List[Int]]:
    let parts = item.split("/")
    if parts.length() == 0 or parts.length() > 2: return none

    let stepped = parts.length() == 2
    var step = 1

    if stepped:
        if let s = small_number(parts[1], 1, 99):
            step = s
        else:
            return none

    var first = low
    var last = high

    if parts[0] != "*":
        let bounds = parts[0].split("-")
        if bounds.length() == 0 or bounds.length() > 2: return none

        if let a = small_number(bounds[0], low, high):
            first = a
        else:
            return none

        if bounds.length() == 2:
            if let b = small_number(bounds[1], low, high):
                last = b
            else:
                return none

            if first > last: return none
        else if stepped:
            return none
        else:
            last = first

    var values = List[Int]()
    var v = first

    while v <= last:
        values.append(v)
        v += step

    return values

fn parse_field(text: String, low: Int, high: Int, label: String) Result[List[Bool], Bad]:
    var allowed = List[Bool]()
    for i in 0..high + 1:
        allowed.append(false)

    for item in text.split(","):
        if let values = item_values(item, low, high):
            for v in values:
                allowed[v] = true
        else:
            return error(Bad(text: label))

    return ok(allowed)

fn parse_cron(tokens: List[String]) Result[Cron, Bad]:
    let minutes = try parse_field(tokens[2], 0, 59, "bad minute")
    let hours = try parse_field(tokens[3], 0, 23, "bad hour")
    let days = try parse_field(tokens[4], 1, 31, "bad day-of-month")
    let months = try parse_field(tokens[5], 1, 12, "bad month")
    let weekdays = try parse_field(tokens[6], 0, 6, "bad day-of-week")
    return ok(
        Cron(
            minutes: minutes, hours: hours, days: days, months: months,
            weekdays: weekdays
        )
    )

fn parse_job(tokens: List[String]) Result[Job, Bad]:
    if tokens.length() != 7: return error(Bad(text: "bad line"))

    let start = try parse_start(tokens[0])
    let count = try parse_count(tokens[1])
    let cron = try parse_cron(tokens)
    return ok(Job(start: start, count: count, cron: cron))

# Day of week of a date, with 0 meaning Sunday; 1970-01-01 was a Thursday.
fn weekday(s: Stamp) Int:
    var days = 0
    for y in 1970..s.year:
        days += 365 + (if is_leap(y): 1 else: 0)
    for m in 1..s.month:
        days += days_in_month(s.year, m)
    days += s.day - 1
    return (days + 4) % 7

fn two(n: Int) String:
    return "{n}".pad_start(2, "0")

fn find_runs(job: Job) List[String]:
    var runs = List[String]()
    let start = job.start
    var year = 0
    var month = 0
    var day = 0
    year = start.year
    month = start.month
    day = start.day

    var dow = weekday(start)
    let after_start = start.hour * 60 + start.minute
    var offset = 0

    while offset <= 3000 and runs.length() < job.count:
        if job.cron.months[month] and job.cron.days[day] and job.cron.weekdays[dow]:
            for hour in 0..24:
                for minute in 0..60:
                    let minute_of_day = hour * 60 + minute
                    let later = offset > 0 or minute_of_day > after_start
                    if (
                        later
                        and runs.length() < job.count
                        and job.cron.hours[hour]
                        and job.cron.minutes[minute]
                    ):
                        runs.append(
                            "{year}-{two(month)}-{two(day)} {two(hour)}:{two(minute)}"
                        )

        day += 1

        if day > days_in_month(year, month):
            day = 1
            month += 1

            if month > 12:
                month = 1
                year += 1

        dow = (dow + 1) % 7
        offset += 1

    return runs

fn solve(line_no: Int, line: String) List[String]:
    let head = "line {line_no}"
    let job = parse_job(line.split(" "))
    if job.is_error(): return ["{head}: error: {job.err().message()}"]

    let runs = find_runs(job.get())
    if runs.length() == 0: return ["{head}: never"]

    var out = ["{head}: {runs.length()} runs"]
    for run in runs:
        out.append(run)
    return out

export fn main() Int:
    var out = List[String]()
    var line_no = 0

    for line in read_lines(stdin()).get():
        line_no += 1
        if line.replace(" ", "").is_empty():
            continue

        for row in solve(line_no, line):
            out.append(row)

    if out.length() > 0:
        stdout().write(out.join("\n") + "\n").get()
    return 0
