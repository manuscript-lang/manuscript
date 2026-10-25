from "@std/time.ms" import Timestamp, TimeError, wall_clock, from_calendar

# Formats an HTTP IMF-fixdate in GMT with whole-second precision.
export def http_date(value: Timestamp) -> Result[String, TimeError]:
    let date = try value.calendar("UTC")
    let weekday = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][date.weekday]
    let month = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov",
        "Dec"
    ][date.month - 1]
    let time = try value.format("HH:mm:ss", "UTC")

    let day = f"0{date.day}" if date.day < 10 else f"{date.day}"

    let year = try value.format("YYYY", "UTC")
    return ok(f"{weekday}, {day} {month} {year} {time} GMT")

def number(value: String) -> Optional[Int]:
    if value == "": return none

    for digit in value.scalar_values():
        if digit < 48 or digit > 57: return none
    return value.parse_int()

# Parses HTTP dates, including RFC850 and asctime forms; invalid calendar dates return none.
# RFC850 two-digit years more than fifty years after now are interpreted in the previous century.
export def parse_http_date(
    text: String,
    now: Timestamp = wall_clock().now()
) -> Optional[Timestamp]:
    if text.byte_length() > 64: return none

    let words = text.split(" ").filter(lambda part: part != "")
    var day = ""
    var month = ""
    var year = ""
    var time = ""
    var weekday = ""
    var old_year = False

    if words.length() == 6 and words[0].ends_with(",") and words[5] == "GMT":
        weekday = words[0].slice(0, words[0].scalar_length() - 1).get()
        day = words[1].clone()
        month = words[2].clone()
        year = words[3].clone()
        time = words[4].clone()
        if day.byte_length() != 2 or year.byte_length() != 4: return none
    elif words.length() == 4 and words[0].ends_with(",") and words[3] == "GMT":
        let dates = words[1].split("-")
        if (
            dates.length() != 3
            or dates[0].byte_length() != 2
            or dates[2].byte_length() != 2
        ): return none

        let long_days = [
            "Sunday,", "Monday,", "Tuesday,", "Wednesday,", "Thursday,", "Friday,",
            "Saturday,"
        ]
        if not long_days.contains(words[0]): return none

        weekday = words[0].take(3)
        day = dates[0].clone()
        month = dates[1].clone()
        year = dates[2].clone()
        time = words[2].clone()
        old_year = True
    elif words.length() == 5:
        weekday = words[0].clone()
        month = words[1].clone()
        day = words[2].clone()
        time = words[3].clone()
        year = words[4].clone()
        if year.byte_length() != 4 or day.byte_length() > 2: return none
    else:
        return none

    let months = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov",
        "Dec"
    ]
    var month_number = 0

    for item in months:
        month_number += 1
        if item == month: break

    if not months.contains(month): return none

    let times = time.split(":")
    if times.length() != 3: return none

    for item in times:
        if item.byte_length() != 2: return none

    let y = number(year)
    let d = number(day)
    let h = number(times[0])
    let m = number(times[1])
    let s = number(times[2])
    if y.is_none() or d.is_none() or h.is_none() or m.is_none() or s.is_none(): return none

    var full_year = y.get()

    if old_year:
        let current = now.calendar("UTC").get()
        full_year += current.year / 100 * 100
        if full_year > current.year + 50: full_year -= 100

        if full_year == current.year + 50:
            let current_suffix = now.format("MM-DDTHH:mm:ss", "UTC").get()
            let candidate = from_calendar(
                full_year, month_number, d.get(), h.get(), m.get(), s.get(), 0, "UTC"
            )
            if candidate.is_error(): return none

            if candidate.get().format("MM-DDTHH:mm:ss", "UTC").get() > current_suffix: full_year -= 100

    let parsed = from_calendar(
        full_year, month_number, d.get(), h.get(), m.get(), s.get(), 0, "UTC"
    )
    if parsed.is_error(): return none

    let date = parsed.get().calendar("UTC").get()
    if ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][date.weekday] != weekday: return none

    match parsed:
        case ok(value): return some(value)
        case error(cause): return none
