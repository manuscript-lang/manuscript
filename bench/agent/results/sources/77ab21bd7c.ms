import IoError, read_line, stdin, stdout from "@std/io.ms"
import range from "@std/collections.ms"

type Span:
    lo: Int
    hi: Int
    step: Int

type Moment:
    year: Int
    month: Int
    day: Int
    hour: Int
    minute: Int

fn all_digits(text: String) Bool:
    if text.is_empty():
        return false

    for c in text.chars():
        if not "0123456789".contains(c):
            return false
    return true

fn is_blank(text: String) Bool:
    for c in text.chars():
        if c != " ":
            return false
    return true

fn parse_number(text: String) Optional[Int]:
    if text.length() > 2 or not all_digits(text):
        return none

    return text.parse_int()

fn fixed_digits(text: String, width: Int) Optional[Int]:
    if text.length() != width or not all_digits(text):
        return none

    return text.parse_int()

fn is_leap(year: Int) Bool:
    return (year % 4 == 0 and year % 100 != 0) or year % 400 == 0

fn days_in_year(year: Int) Int:
    if is_leap(year):
        return 366

    return 365

fn days_in_month(year: Int, month: Int) Int:
    if month == 2:
        if is_leap(year):
            return 29

        return 28

    if month == 4 or month == 6 or month == 9 or month == 11:
        return 30

    return 31

# 1970-01-01 was a Thursday, so day 0 maps to 4; Sunday is 0.
fn weekday_of(year: Int, month: Int, day: Int) Int:
    var elapsed = 0
    for y in range(1970, year):
        elapsed += days_in_year(y)
    for m in range(1, month):
        elapsed += days_in_month(year, m)
    elapsed += day - 1
    return (elapsed + 4) % 7

fn parse_start(text: String) Optional[Moment]:
    let halves = text.split("T")
    if halves.length() != 2:
        return none

    let date = halves.get(0).split("-")
    let clock = halves.get(1).split(":")
    if date.length() != 3 or clock.length() != 2:
        return none

    let year = fixed_digits(date.get(0), 4)
    let month = fixed_digits(date.get(1), 2)
    let day = fixed_digits(date.get(2), 2)
    let hour = fixed_digits(clock.get(0), 2)
    let minute = fixed_digits(clock.get(1), 2)
    if (
        year.is_none()
        or month.is_none()
        or day.is_none()
        or hour.is_none()
        or minute.is_none()
    ):
        return none
    if year.get() < 1970 or year.get() > 2099:
        return none
    if month.get() < 1 or month.get() > 12:
        return none
    if day.get() < 1 or day.get() > days_in_month(year.get(), month.get()):
        return none
    if hour.get() > 23 or minute.get() > 59:
        return none

    return some(
        Moment(
            year: year.get(), month: month.get(), day: day.get(), hour: hour.get(),
            minute: minute.get()
        )
    )

fn parse_count(text: String) Optional[Int]:
    let value = parse_number(text)
    if value.is_none():
        return none
    if value.get() < 1 or value.get() > 20:
        return none

    return value

# One cron item: `*`, `*/S`, `A`, `A-B`, or `A-B/S`.
fn parse_item(item: String, lo: Int, hi: Int) Optional[Span]:
    if item.is_empty():
        return none

    let parts = item.split("/")
    if parts.length() > 2:
        return none

    var step = 1

    if parts.length() == 2:
        let parsed = parse_number(parts.get(1))
        if parsed.is_none() or parsed.get() < 1:
            return none

        step = parsed.get()

    let range_text = parts.get(0)
    var first = lo
    var last = hi

    if range_text != "*":
        let bounds = range_text.split("-")

        if bounds.length() == 1:
            if parts.length() == 2:
                return none

            let single = parse_number(bounds.get(0))
            if single.is_none():
                return none

            first = single.get()
            last = first
        else:
            if bounds.length() != 2:
                return none

            let low = parse_number(bounds.get(0))
            let high = parse_number(bounds.get(1))
            if low.is_none() or high.is_none() or low.get() > high.get():
                return none

            first = low.get()
            last = high.get()

    if first < lo or last > hi:
        return none

    return some(Span(lo: first, hi: last, step: step))

fn parse_field(text: String, lo: Int, hi: Int) Optional[List[Bool]]:
    if text.is_empty():
        return none

    var allowed = List[Bool]()
    for value in range(0, hi + 1):
        allowed.append(false)

    for item in text.split(","):
        let span = parse_item(item, lo, hi)
        if span.is_none():
            return none

        let found = span.get()
        for value in range(found.lo, found.hi + 1):
            if (value - found.lo) % found.step == 0:
                allowed.set(value, true)

    return some(allowed)

fn find_runs(
    start: Moment,
    count: Int,
    minutes: List[Bool],
    hours: List[Bool],
    days: List[Bool],
    months: List[Bool],
    weekdays: List[Bool]
) List[Moment]:
    var runs = List[Moment]()
    var year = start.year
    var month = start.month
    var day = start.day
    var weekday = weekday_of(year, month, day)
    let start_key = start.hour * 60 + start.minute

    for offset in range(0, 3001):
        if runs.length() == count:
            break

        if (months.get(month) and days.get(day) and weekdays.get(weekday)):
            for hour in range(0, 24):
                if runs.length() == count:
                    break
                if not hours.get(hour):
                    continue

                for minute in range(0, 60):
                    if runs.length() == count:
                        break
                    if offset == 0 and hour * 60 + minute <= start_key:
                        continue

                    if minutes.get(minute):
                        runs.append(
                            Moment(
                                year: year, month: month, day: day, hour: hour,
                                minute: minute
                            )
                        )

        day += 1
        weekday = (weekday + 1) % 7

        if day > days_in_month(year, month):
            day = 1
            month += 1

            if month > 12:
                month = 1
                year += 1

    return runs

fn pad2(value: Int) String:
    if value < 10:
        return "0{value}"

    return "{value}"

fn format_moment(moment: Moment) String:
    return "{moment.year}-{pad2(moment.month)}-{pad2(moment.day)} {pad2(moment.hour)}:{pad2(moment.minute)}"

fn report(number: Int, text: String) String:
    let tokens = text.split(" ")
    if tokens.length() != 7:
        return "line {number}: error: bad line\n"

    let start = parse_start(tokens.get(0))
    if start.is_none():
        return "line {number}: error: bad start\n"

    let count = parse_count(tokens.get(1))
    if count.is_none():
        return "line {number}: error: bad count\n"

    let minutes = parse_field(tokens.get(2), 0, 59)
    if minutes.is_none():
        return "line {number}: error: bad minute\n"

    let hours = parse_field(tokens.get(3), 0, 23)
    if hours.is_none():
        return "line {number}: error: bad hour\n"

    let days = parse_field(tokens.get(4), 1, 31)
    if days.is_none():
        return "line {number}: error: bad day-of-month\n"

    let months = parse_field(tokens.get(5), 1, 12)
    if months.is_none():
        return "line {number}: error: bad month\n"

    let weekdays = parse_field(tokens.get(6), 0, 6)
    if weekdays.is_none():
        return "line {number}: error: bad day-of-week\n"

    let runs = find_runs(
        start.get(), count.get(), minutes.get().clone(), hours.get().clone(),
        days.get().clone(), months.get().clone(), weekdays.get().clone()
    )
    if runs.is_empty():
        return "line {number}: never\n"

    var out = "line {number}: {runs.length()} runs\n"

    for run in runs:
        out = out.concat(format_moment(run))
        out = out.concat("\n")

    return out

fn read_lines() Result[List[String], IoError]:
    var lines = List[String]()
    let input = stdin()

    while true:
        let line = try read_line(input)
        if line.is_none():
            return ok(lines)

        lines.append(line.get())

export fn main() Int:
    let lines = read_lines().get()
    var out = ""
    var number = 0

    for text in lines:
        number += 1
        if is_blank(text):
            continue

        out = out.concat(report(number, text))

    stdout().write(out).get()
    stdout().flush().get()
    return 0
