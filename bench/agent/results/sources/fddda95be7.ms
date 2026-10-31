import stdin, stdout from "@std/io.ms"
import read_lines from "@std/streams.ms"

# Runs are searched over this many days after START, inclusive of START's own day.
let SEARCH_DAYS = 3000

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

# A line that cannot be scheduled; the text is the message after `error: `.
type LineError:
    case Bad(text: String)

impl Error for LineError:
    fn message() String:
        match self:
            Bad(text):
                return text.clone()

fn is_digit(c: String) Bool:
    return c.length() == 1 and "0123456789".contains(c)

# One or two ASCII digits, no sign.
fn number(text: String) Optional[Int]:
    if text.length() < 1 or text.length() > 2: return none

    for c in text.chars():
        if not is_digit(c): return none
    return text.parse_int()

fn bounded(text: String, lo: Int, hi: Int) Optional[Int]:
    if let n = number(text):
        if n >= lo and n <= hi: return n
    return none

fn is_leap(year: Int) Bool:
    return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)

fn days_in_month(year: Int, month: Int) Int:
    let lengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    if month == 2 and is_leap(year): return 29

    return lengths[month - 1]

# Sunday is 0. Sakamoto's method.
fn weekday(year: Int, month: Int, day: Int) Int:
    let offsets = [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4]

    let y = if month < 3: year - 1 else: year

    return (y + y / 4 - y / 100 + y / 400 + offsets[month - 1] + day) % 7

fn valid_start(text: String) Optional[Moment]:
    if text.length() != 16: return none

    let c = text.chars()
    for i in [0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15]:
        if not is_digit(c[i]): return none
    if c[4] != "-" or c[7] != "-" or c[10] != "T" or c[13] != ":": return none

    let year = text.take(4).parse_int().get(0)
    let month = text.drop(5).take(2).parse_int().get(0)
    let day = text.drop(8).take(2).parse_int().get(0)
    let hour = text.drop(11).take(2).parse_int().get(0)
    let minute = text.drop(14).take(2).parse_int().get(0)
    if year < 1970 or year > 2099: return none
    if month < 1 or month > 12: return none
    if day < 1 or day > days_in_month(year, month): return none
    if hour > 23 or minute > 59: return none

    return Moment(year: year, month: month, day: day, hour: hour, minute: minute)

# The values picked out by one comma-separated item, or none if the item is malformed.
fn item_values(item: String, lo: Int, hi: Int) Optional[List[Int]]:
    let parts = item.split("/")
    if parts.length() > 2: return none

    var step = 1

    if parts.length() == 2:
        if let s = number(parts[1]):
            if s < 1: return none

            step = s
        else:
            return none

    var first = lo
    var last = hi

    if parts[0] != "*":
        let ends = parts[0].split("-")
        if ends.length() > 2: return none
        if ends.length() == 1 and parts.length() == 2: return none

        if let a = bounded(ends[0], lo, hi):
            first = a
        else:
            return none

        last = first

        if ends.length() == 2:
            if let b = bounded(ends[1], lo, hi):
                last = b
            else:
                return none

            if first > last: return none

    var values = List[Int]()
    var v = first

    while v <= last:
        values.append(v)
        v += step

    return values

# Index i is True when value i is allowed; the list covers 0 through hi.
fn parse_field(text: String, lo: Int, hi: Int) Optional[List[Bool]]:
    var allowed = List[Bool](reserve: hi + 1)
    for i in 0..hi + 1:
        allowed.append(false)

    for item in text.split(","):
        if let values = item_values(item, lo, hi):
            for v in values:
                allowed[v] = true
        else:
            return none

    return allowed

fn two(n: Int) String:
    return "{n}".pad_start(2, "0")

fn search(start: Moment, count: Int, plan: Schedule) List[String]:
    var runs = List[String]()
    let start_hour = start.hour
    let start_minute = start.minute
    let start_year = start.year
    let start_month = start.month
    let start_day = start.day
    var year = start_year
    var month = start_month
    var day = start_day
    var wd = weekday(year, month, day)

    for offset in 0..SEARCH_DAYS + 1:
        if runs.length() == count: break

        if plan.months[month] and plan.days[day] and plan.weekdays[wd]:
            for hour in 0..24:
                if not plan.hours[hour]: continue

                for minute in 0..60:
                    if (
                        offset == 0
                        and hour * 60 + minute <= start_hour * 60 + start_minute
                    ): continue

                    if plan.minutes[minute] and runs.length() < count:
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

        wd = (wd + 1) % 7

    return runs

fn describe(line_number: Int, line: String) Result[String, LineError]:
    let tokens = line.split(" ")
    if tokens.length() != 7: return error(Bad("bad line"))

    let start = try valid_start(tokens[0]).ok_or(Bad("bad start"))
    let count = try bounded(tokens[1], 1, 20).ok_or(Bad("bad count"))
    let minutes = try parse_field(tokens[2], 0, 59).ok_or(Bad("bad minute"))
    let hours = try parse_field(tokens[3], 0, 23).ok_or(Bad("bad hour"))
    let days = try parse_field(tokens[4], 1, 31).ok_or(Bad("bad day-of-month"))
    let months = try parse_field(tokens[5], 1, 12).ok_or(Bad("bad month"))
    let weekdays = try parse_field(tokens[6], 0, 6).ok_or(Bad("bad day-of-week"))
    let plan = Schedule(
        minutes: minutes, hours: hours, days: days, months: months, weekdays: weekdays
    )
    let runs = search(start, count, plan)
    if runs.length() == 0: return ok("line {line_number}: never")

    return ok("line {line_number}: {runs.length()} runs\n" + runs.join("\n"))

export fn main() Int:
    var line_number = 0

    for line in read_lines(stdin()).get():
        line_number += 1
        if line.replace(" ", "").is_empty(): continue

        let text = describe(line_number, line).get_or_else(
            fn e: "line {line_number}: error: {e.message()}"
        )
        stdout().write(text + "\n").get()

    return 0
