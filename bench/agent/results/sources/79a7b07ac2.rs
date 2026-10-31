use std::io::{self, Read, Write};

const WINDOW_DAYS: i64 = 3000;

/// Days since 1970-01-01 for a proleptic Gregorian date.
fn days_from_civil(y: i64, m: i64, d: i64) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let mp = if m > 2 { m - 3 } else { m + 9 };
    let doy = (153 * mp + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146097 + doe - 719468
}

/// (year, month, day) for days since 1970-01-01.
fn civil_from_days(z: i64) -> (i64, i64, i64) {
    let z = z + 719468;
    let era = z.div_euclid(146097);
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = if m <= 2 { y + 1 } else { y };
    (y, m, d)
}

fn is_leap(y: i64) -> bool {
    (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
}

fn days_in_month(y: i64, m: i64) -> i64 {
    match m {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        2 => {
            if is_leap(y) {
                29
            } else {
                28
            }
        }
        _ => 0,
    }
}

/// Exactly `n` ASCII digits, all characters digits.
fn all_digits(s: &str) -> bool {
    !s.is_empty() && s.bytes().all(|b| b.is_ascii_digit())
}

/// A 1-or-2 digit unsigned number.
fn small_num(s: &str) -> Option<i64> {
    if (1..=2).contains(&s.len()) && all_digits(s) {
        s.parse().ok()
    } else {
        None
    }
}

struct Start {
    year: i64,
    month: i64,
    day: i64,
    hour: i64,
    minute: i64,
}

fn parse_start(s: &str) -> Option<Start> {
    let b = s.as_bytes();
    if b.len() != 16 {
        return None;
    }
    if b[4] != b'-' || b[7] != b'-' || b[10] != b'T' || b[13] != b':' {
        return None;
    }
    let year_s = &s[0..4];
    let month_s = &s[5..7];
    let day_s = &s[8..10];
    let hour_s = &s[11..13];
    let min_s = &s[14..16];
    for part in [year_s, month_s, day_s, hour_s, min_s] {
        if !all_digits(part) {
            return None;
        }
    }
    let year: i64 = year_s.parse().ok()?;
    let month: i64 = month_s.parse().ok()?;
    let day: i64 = day_s.parse().ok()?;
    let hour: i64 = hour_s.parse().ok()?;
    let minute: i64 = min_s.parse().ok()?;
    if !(1970..=2099).contains(&year) {
        return None;
    }
    if !(1..=12).contains(&month) {
        return None;
    }
    if day < 1 || day > days_in_month(year, month) {
        return None;
    }
    if !(0..=23).contains(&hour) || !(0..=59).contains(&minute) {
        return None;
    }
    Some(Start {
        year,
        month,
        day,
        hour,
        minute,
    })
}

fn parse_count(s: &str) -> Option<usize> {
    let v = small_num(s)?;
    if (1..=20).contains(&v) {
        Some(v as usize)
    } else {
        None
    }
}

/// Parse one cron field into a membership table indexed by value (0..=max).
fn parse_field(s: &str, min: i64, max: i64) -> Option<Vec<bool>> {
    let mut set = vec![false; (max + 1) as usize];
    for item in s.split(',') {
        if item.is_empty() {
            return None;
        }
        let in_range = |v: i64| v >= min && v <= max;
        if item == "*" {
            for v in min..=max {
                set[v as usize] = true;
            }
        } else if let Some(step_s) = item.strip_prefix("*/") {
            let step = small_num(step_s)?;
            if step < 1 {
                return None;
            }
            let mut v = min;
            while v <= max {
                set[v as usize] = true;
                v += step;
            }
        } else {
            let (base, step) = match item.split_once('/') {
                Some((b, st)) => {
                    let step = small_num(st)?;
                    if step < 1 {
                        return None;
                    }
                    (b, Some(step))
                }
                None => (item, None),
            };
            let (a, b) = match base.split_once('-') {
                Some((lo, hi)) => {
                    let a = small_num(lo)?;
                    let b = small_num(hi)?;
                    if a > b {
                        return None;
                    }
                    (a, b)
                }
                None => {
                    // A single number; a step is only valid with a range.
                    if step.is_some() {
                        return None;
                    }
                    let a = small_num(base)?;
                    (a, a)
                }
            };
            if !in_range(a) || !in_range(b) {
                return None;
            }
            let step = step.unwrap_or(1);
            let mut v = a;
            while v <= b {
                set[v as usize] = true;
                v += step;
            }
        }
    }
    Some(set)
}

struct Schedule {
    minute: Vec<bool>,
    hour: Vec<bool>,
    dom: Vec<bool>,
    month: Vec<bool>,
    dow: Vec<bool>,
}

fn run_line(line: &str, lineno: usize, out: &mut String) {
    let tokens: Vec<&str> = line.split(' ').collect();
    if tokens.len() != 7 {
        out.push_str(&format!("line {}: error: bad line\n", lineno));
        return;
    }
    let start = match parse_start(tokens[0]) {
        Some(s) => s,
        None => {
            out.push_str(&format!("line {}: error: bad start\n", lineno));
            return;
        }
    };
    let count = match parse_count(tokens[1]) {
        Some(c) => c,
        None => {
            out.push_str(&format!("line {}: error: bad count\n", lineno));
            return;
        }
    };
    let minute = parse_field(tokens[2], 0, 59);
    let hour = parse_field(tokens[3], 0, 23);
    let dom = parse_field(tokens[4], 1, 31);
    let month = parse_field(tokens[5], 1, 12);
    let dow = parse_field(tokens[6], 0, 6);
    let sched = match (minute, hour, dom, month, dow) {
        (Some(minute), Some(hour), Some(dom), Some(month), Some(dow)) => Schedule {
            minute,
            hour,
            dom,
            month,
            dow,
        },
        (None, _, _, _, _) => {
            out.push_str(&format!("line {}: error: bad minute\n", lineno));
            return;
        }
        (_, None, _, _, _) => {
            out.push_str(&format!("line {}: error: bad hour\n", lineno));
            return;
        }
        (_, _, None, _, _) => {
            out.push_str(&format!("line {}: error: bad day-of-month\n", lineno));
            return;
        }
        (_, _, _, None, _) => {
            out.push_str(&format!("line {}: error: bad month\n", lineno));
            return;
        }
        (_, _, _, _, None) => {
            out.push_str(&format!("line {}: error: bad day-of-week\n", lineno));
            return;
        }
    };

    let start_day = days_from_civil(start.year, start.month, start.day);
    let start_total = start_day * 1440 + start.hour * 60 + start.minute;
    let mut runs: Vec<i64> = Vec::new();
    'days: for day in start_day..=start_day + WINDOW_DAYS {
        let (_, m, d) = civil_from_days(day);
        let wd = (day + 4).rem_euclid(7) as usize;
        if !sched.month[m as usize] || !sched.dom[d as usize] || !sched.dow[wd] {
            continue;
        }
        for h in 0..24usize {
            if !sched.hour[h] {
                continue;
            }
            for mi in 0..60usize {
                if !sched.minute[mi] {
                    continue;
                }
                let t = day * 1440 + (h as i64) * 60 + mi as i64;
                if t <= start_total {
                    continue;
                }
                runs.push(t);
                if runs.len() == count {
                    break 'days;
                }
            }
        }
    }

    if runs.is_empty() {
        out.push_str(&format!("line {}: never\n", lineno));
        return;
    }
    out.push_str(&format!("line {}: {} runs\n", lineno, runs.len()));
    for t in runs {
        let day = t.div_euclid(1440);
        let rem = t.rem_euclid(1440);
        let (y, m, d) = civil_from_days(day);
        out.push_str(&format!(
            "{:04}-{:02}-{:02} {:02}:{:02}\n",
            y,
            m,
            d,
            rem / 60,
            rem % 60
        ));
    }
}

fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).expect("read stdin");
    let mut out = String::new();
    for (i, line) in input.lines().enumerate() {
        let lineno = i + 1;
        if line.bytes().all(|b| b == b' ') {
            continue;
        }
        run_line(line, lineno, &mut out);
    }
    io::stdout().write_all(out.as_bytes()).expect("write stdout");
}
