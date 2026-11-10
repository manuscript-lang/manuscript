import (
    stdin, stdout from "@std/io/io.ms",
    read_all from "@std/io/streams.ms",
    StringBuilder from "@std/string.ms",
)

type Entry:
    ts: String
    level: String
    method: String
    path: String
    status: Int
    latency: Int

type PathStat:
    path: String
    count: Int
    total: Int

fn all_digits(s: String) Bool:
    if s.length() == 0: return false

    for c in s.chars():
        if not "0123456789".contains(c): return false
    return true

fn parse_entry(line: String) Entry?:
    parts := line.split(" ")
    if parts.length() != 6: return none

    ts := parts[0]
    level := parts[1]
    method := parts[2]
    path := parts[3]
    status := parts[4]
    latency := parts[5]
    if ts.length() == 0: return none
    if not (level == "DEBUG" or level == "INFO" or level == "WARN" or level == "ERROR"): return none
    if not (
        method == "GET"
        or method == "POST"
        or method == "PUT"
        or method == "DELETE"
    ): return none
    if path.length() == 0 or not path.starts_with("/"): return none
    if status.length() != 3 or not all_digits(status): return none
    if latency.length() < 1 or latency.length() > 9 or not all_digits(latency): return none

    return Entry(
        ts: ts.clone(), level: level.clone(), method: method.clone(),
        path: path.clone(), status: status.parse_int().get(0),
        latency: latency.parse_int().get(0)
    )

fn is_blank(line: String) Bool:
    return line.trim() == ""

fn stat_cmp(a: PathStat, b: PathStat) Int:
    if a.count != b.count:
        if a.count > b.count: return -1

        return 1

    return a.path.compare(b.path)

export fn main() Int:
    data := read_all(stdin()).get()
    text := data.decode_utf8().get("")
    lines := text.split("\n")
    var malformed = 0
    var debug_n = 0
    var info_n = 0
    var warn_n = 0
    var error_n = 0
    var s2 = 0
    var s3 = 0
    var s4 = 0
    var s5 = 0
    var s_other = 0
    var entries = List[Entry]()

    for line in lines:
        if is_blank(line): continue

        if e := parse_entry(line):
            entries.append(e)
        else:
            malformed += 1

    var lats = List[Int]()
    var counts = Map[String, Int]()
    var totals = Map[String, Int]()
    var slowest = -1

    for i in 0..entries.length():
        e := entries[i]

        if e.level == "DEBUG": debug_n += 1
        else if e.level == "INFO": info_n += 1
        else if e.level == "WARN": warn_n += 1
        else: error_n += 1

        d := e.status / 100

        if d == 2: s2 += 1
        else if d == 3: s3 += 1
        else if d == 4: s4 += 1
        else if d == 5: s5 += 1
        else: s_other += 1

        lats.append(e.latency)
        if slowest < 0 or e.latency > entries[slowest].latency: slowest = i

        if counts.contains(e.path):
            counts[e.path.clone()] = counts[e.path] + 1
            totals[e.path.clone()] = totals[e.path] + e.latency
        else:
            counts[e.path.clone()] = 1
            totals[e.path.clone()] = e.latency

    var out = StringBuilder()
    n := entries.length()
    out.append("valid: {n}\n")
    out.append("malformed: {malformed}\n")
    out.append("DEBUG: {debug_n}\n")
    out.append("INFO: {info_n}\n")
    out.append("WARN: {warn_n}\n")
    out.append("ERROR: {error_n}\n")
    out.append("status: 2xx={s2} 3xx={s3} 4xx={s4} 5xx={s5} other={s_other}\n")

    if n == 0:
        out.append("p95: 0\n")
    else:
        lats.sort()

        rank := (95 * n + 99) / 100
        out.append("p95: {lats[rank - 1]}\n")

        s := entries[slowest]
        out.append("slowest: {s.latency} {s.method} {s.path} {s.ts}\n")

    out.append("top:\n")

    var stats = List[PathStat]()
    for p in counts.keys():
        stats.append(PathStat(path: p.clone(), count: counts[p], total: totals[p]))
    stats.sort(stat_cmp)

    for i in 0..3:
        if i >= stats.length(): break

        st := stats[i]
        out.append("{st.path} {st.count} avg={st.total / st.count}\n")

    stdout().write(out.build()).get()
    return 0
