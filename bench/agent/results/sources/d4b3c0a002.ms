import {stdin, stdout} from "@std/io.ms"
import {read_lines} from "@std/streams.ms"
import {range} from "@std/collections.ms"

type Moment:
    year: Int
    month: Int
    day: Int
    hour: Int
    minute: Int

type Schedule:
    minutes: List[Bool]
    hours: List[Bool]
    days: List[Bool]
    months: List[Bool]
    weekdays: List[Bool]

fn is_blank(line: String) Bool:
    for ch in line.chars():
        if ch != " ":
            return false
    return true

# Returns the value of an unsigned ASCII number of min_width to max_width digits, or -1.
fn number(text: String, min_width: Int, max_width: Int) Int:
    if text.length() < min_width or text.length() > max_width:
        return -1

    for ch in text.chars():
        let code = ch.scalar_at(0)
        if code < 48 or code > 57:
            return -1

    return text.parse_int().get(-1)

fn is_leap(year: Int) Bool:
    return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)

fn days_in_month(year: Int, month: Int) Int:
    if month == 2:
        if is_leap(year):
            return 29

        return 28

    if month == 4 or month == 6 or month == 9 or month == 11:
        return 30

    return 31

# Day of the week for a date, where 0 is Sunday. 1970-01-01 was a Thursday.
fn weekday_of(year: Int, month: Int, day: Int) Int:
    var days = 0

    for y in range(1970, year):
        if is_leap(y):
            days += 366
        else:
            days += 365

    for m in range(1, month):
        days += days_in_month(year, m)
    days += day - 1
    return (days + 4) % 7

fn parse_start(text: String) Optional[Moment]:
    let halves = text.split("T")
    if halves.length() != 2:
        return none

    let date = halves[0].split("-")
    let clock = halves[1].split(":")
    if date.length() != 3 or clock.length() != 2:
        return none

    let year = number(date[0], 4, 4)
    let month = number(date[1], 2, 2)
    let day = number(date[2], 2, 2)
    let hour = number(clock[0], 2, 2)
    let minute = number(clock[1], 2, 2)
    if year < 1970 or year > 2099 or month < 1 or month > 12:
        return none
    if day < 1 or day > days_in_month(year, month):
        return none
    if hour < 0 or hour > 23 or minute < 0 or minute > 59:
        return none

    return some(Moment(year: year, month: month, day: day, hour: hour, minute: minute))

# The [first, last] span named by a base item, or an empty list when it is invalid.
fn bounds(base: String, low: Int, high: Int, stepped: Bool) List[Int]:
    if base == "*":
        return [low, high]

    let ends = base.split("-")

    if ends.length() == 1 and not stepped:
        let value = number(base, 1, 2)
        if value < low or value > high:
            return []

        return [value, value]

    if ends.length() == 2:
        let first = number(ends[0], 1, 2)
        let last = number(ends[1], 1, 2)
        if first < low or last > high or first > last:
            return []

        return [first, last]

    return []

fn item_values(item: String, low: Int, high: Int) List[Int]:
    let parts = item.split("/")
    if parts.length() == 0 or parts.length() > 2:
        return []

    let stepped = parts.length() == 2
    var step = 1

    if stepped:
        step = number(parts[1], 1, 2)
        if step < 1:
            return []

    let span = bounds(parts[0], low, high, stepped)
    if span.length() == 0:
        return []

    var values: List[Int] = []

    for value in range(span[0], span[1] + 1):
        if (value - span[0]) % step == 0:
            values.append(value)
    return values

# Marks the allowed values of one cron field, or returns an empty list when the field is invalid.
fn parse_field(text: String, low: Int, high: Int) List[Bool]:
    var allowed: List[Bool] = []

    for value in range(0, high + 1):
        allowed.append(false)

    for item in text.split(","):
        let values = item_values(item, low, high)
        if values.length() == 0:
            return []

        for value in values:
            allowed[value] = true

    return allowed

fn two(n: Int) String:
    if n < 10:
        return "0{n}"

    return "{n}"

fn stamp(year: Int, month: Int, day: Int, hour: Int, minute: Int) String:
    return "{year}-{two(month)}-{two(day)} {two(hour)}:{two(minute)}"

fn runs(schedule: Schedule, start: Moment, count: Int) List[String]:
    var found: List[String] = []
    let start_year = start.year
    let start_month = start.month
    let start_day = start.day
    let start_minute = start.hour * 60 + start.minute
    var year = start_year
    var month = start_month
    var day = start_day
    var weekday = weekday_of(year, month, day)

    for offset in range(0, 3001):
        if schedule.days[day] and schedule.months[month] and schedule.weekdays[weekday]:
            for hour in range(0, 24):
                for minute in range(0, 60):
                    if not schedule.hours[hour] or not schedule.minutes[minute]:
                        continue
                    if offset == 0 and hour * 60 + minute <= start_minute:
                        continue

                    found.append(stamp(year, month, day, hour, minute))
                    if found.length() == count:
                        return found

        day += 1

        if day > days_in_month(year, month):
            day = 1
            month += 1

            if month > 12:
                month = 1
                year += 1

        weekday = (weekday + 1) % 7

    return found

fn describe(line_no: Int, text: String) List[String]:
    let head = "line {line_no}"
    let fields = text.split(" ")
    if fields.length() != 7:
        return ["{head}: error: bad line"]

    let start = parse_start(fields[0])
    if not start.is_some():
        return ["{head}: error: bad start"]

    let count = number(fields[1], 1, 2)
    if count < 1 or count > 20:
        return ["{head}: error: bad count"]

    let minutes = parse_field(fields[2], 0, 59)
    if minutes.length() == 0:
        return ["{head}: error: bad minute"]

    let hours = parse_field(fields[3], 0, 23)
    if hours.length() == 0:
        return ["{head}: error: bad hour"]

    let days = parse_field(fields[4], 1, 31)
    if days.length() == 0:
        return ["{head}: error: bad day-of-month"]

    let months = parse_field(fields[5], 1, 12)
    if months.length() == 0:
        return ["{head}: error: bad month"]

    let weekdays = parse_field(fields[6], 0, 6)
    if weekdays.length() == 0:
        return ["{head}: error: bad day-of-week"]

    let schedule = Schedule(
        minutes: minutes, hours: hours, days: days, months: months, weekdays: weekdays
    )
    let found = runs(schedule, start.get(), count)
    if found.length() == 0:
        return ["{head}: never"]

    let total = found.length()
    var out = ["{head}: {total} runs"]

    for run in found:
        out.append(run)
    return out

export fn main() Int:
    var out: List[String] = []
    var line_no = 0

    for line in read_lines(stdin()).get():
        line_no += 1
        if is_blank(line):
            continue

        for row in describe(line_no, line):
            out.append(row)

    if out.length() > 0:
        stdout().write(out.join("\n") + "\n").get()
    return 0
