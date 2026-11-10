import (
    read_all from "@std/io/streams.ms",
    stdin from "@std/io/io.ms",
)

type Rec:
    timestamp: String
    level: String
    method: String
    path: String
    status: String
    latency_text: String
    latency: Int

type PathStat:
    path: String
    count: Int
    total: Int

fn all_digits(s: String) Bool:
    for v in s.scalar_values():
        if v < 48 or v > 57: return false
    return true

fn digits_value(s: String) Int:
    var v = 0
    for d in s.scalar_values():
        v = v * 10 + (d - 48)
    return v

fn parse_line(line: String) Rec?:
    let parts = line.split(" ")
    if parts.length() != 6: return none

    let level = parts[1]
    if not (level == "DEBUG" or level == "INFO" or level == "WARN" or level == "ERROR"): return none

    let method = parts[2]
    if not (
        method == "GET"
        or method == "POST"
        or method == "PUT"
        or method == "DELETE"
    ): return none
    if parts[0].is_empty(): return none
    if not parts[3].starts_with("/"): return none
    if parts[4].length() != 3 or not all_digits(parts[4]): return none

    let lat = parts[5]
    if lat.length() < 1 or lat.length() > 9 or not all_digits(lat): return none

    return Rec(
        timestamp: parts[0].clone(), level: level.clone(), method: method.clone(),
        path: parts[3].clone(), status: parts[4].clone(), latency_text: lat.clone(),
        latency: digits_value(lat)
    )

fn path_order(a: PathStat, b: PathStat) Int:
    if a.count > b.count: return -1
    if a.count < b.count: return 1

    return a.path.compare(b.path)

export fn main() Int:
    let text = read_all(stdin()).get().decode_utf8().get("")
    var valid = List[Rec]()
    var malformed = 0

    for line in text.split("\n"):
        if line.trim().is_empty(): continue

        var ok = false

        if let r = parse_line(line):
            valid.append(r)
            ok = true

        if not ok: malformed += 1

    var debug = 0
    var info = 0
    var warn = 0
    var error = 0
    var s2 = 0
    var s3 = 0
    var s4 = 0
    var s5 = 0
    var sother = 0
    var counts = Map[String, Int]()
    var totals = Map[String, Int]()
    var lats = List[Int]()

    for r in valid:
        if r.level == "DEBUG": debug += 1
        if r.level == "INFO": info += 1
        if r.level == "WARN": warn += 1
        if r.level == "ERROR": error += 1

        let c = r.status.get(0)

        if c == "2": s2 += 1
        else if c == "3": s3 += 1
        else if c == "4": s4 += 1
        else if c == "5": s5 += 1
        else: sother += 1

        counts[r.path.clone()] = counts.get_or(r.path, 0) + 1
        totals[r.path.clone()] = totals.get_or(r.path, 0) + r.latency
        lats.append(r.latency)

    let n = valid.length()
    print("valid: {n}")
    print("malformed: {malformed}")
    print("DEBUG: {debug}")
    print("INFO: {info}")
    print("WARN: {warn}")
    print("ERROR: {error}")
    print("status: 2xx={s2} 3xx={s3} 4xx={s4} 5xx={s5} other={sother}")

    var p95 = 0

    if n > 0:
        lats.sort()

        let rank = (95 * n + 99) / 100
        p95 = lats[rank - 1]

    print("p95: {p95}")

    if n > 0:
        var best = 0
        for i in 0..n:
            if valid[i].latency > valid[best].latency: best = i

        let b = valid[best]
        print("slowest: {b.latency_text} {b.method} {b.path} {b.timestamp}")

    print("top:")

    var stats = List[PathStat]()
    for p in counts.keys():
        stats.append(
            PathStat(
                path: p.clone(), count: counts.get_or(p, 0), total: totals.get_or(p, 0)
            )
        )
    stats.sort(fn(a: PathStat, b: PathStat) Int: path_order(a, b))

    var shown = 0

    for s in stats:
        if shown >= 3: break

        print("{s.path} {s.count} avg={s.total / s.count}")
        shown += 1

    return 0
