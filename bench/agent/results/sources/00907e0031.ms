// ms: allow_effect std.console.*

import stdin, stdout from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"

type Rec:
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

// Parses plain ASCII digits of a length in [min_len, max_len]; none otherwise.
fn digits_value(s: String, min_len: Int, max_len: Int) Int?:
    if s.length() < min_len or s.length() > max_len:
        return none
    if s.starts_with("+") or s.starts_with("-"):
        return none

    return s.parse_int()

fn parse_line(line: String) Rec?:
    let f = line.split(" ")
    if f.length() != 6:
        return none

    for x in f:
        if x.is_empty():
            return none

    let level = f[1]
    if not (level == "DEBUG" or level == "INFO" or level == "WARN" or level == "ERROR"):
        return none

    let method = f[2]
    if not (
        method == "GET"
        or method == "POST"
        or method == "PUT"
        or method == "DELETE"
    ):
        return none
    if not f[3].starts_with("/"):
        return none

    if let st = digits_value(f[4], 3, 3):
        if let lat = digits_value(f[5], 1, 9):
            return Rec(
                ts: f[0].clone(), level: level.clone(), method: method.clone(),
                path: f[3].clone(), status: st, latency: lat
            )
    return none

fn cmp_stat(a: PathStat, b: PathStat) Int:
    if a.count != b.count:
        return b.count - a.count

    return a.path.compare(b.path)

export fn main() Int:
    let text = read_all(stdin()).get()
    let pieces = text.split("\n".as_bytes())
    var valid = List[Rec]()
    var malformed = 0

    for piece in pieces:
        if let line = piece.decode_utf8():
            if line.trim().is_empty():
                continue

            if let r = parse_line(line):
                valid.append(r)
            else:
                malformed += 1
        else:
            malformed += 1

    var debug = 0
    var info = 0
    var warn = 0
    var error = 0
    var s2 = 0
    var s3 = 0
    var s4 = 0
    var s5 = 0
    var sother = 0
    var lats = List[Int]()
    var best = 0
    var counts = Map[String, Int]()
    var totals = Map[String, Int]()

    for i in 0..valid.length():
        let r = valid[i]

        if r.level == "DEBUG":
            debug += 1
        else if r.level == "INFO":
            info += 1
        else if r.level == "WARN":
            warn += 1
        else:
            error += 1

        let d = r.status / 100

        if d == 2:
            s2 += 1
        else if d == 3:
            s3 += 1
        else if d == 4:
            s4 += 1
        else if d == 5:
            s5 += 1
        else:
            sother += 1

        lats.append(r.latency)
        if r.latency > valid[best].latency:
            best = i

        if counts.contains(r.path):
            let c = counts[r.path]
            let t = totals[r.path]
            counts[r.path.clone()] = c + 1
            totals[r.path.clone()] = t + r.latency
        else:
            counts[r.path.clone()] = 1
            totals[r.path.clone()] = r.latency

    var out = "valid: {valid.length()}\nmalformed: {malformed}\nDEBUG: {debug}\nINFO: {info}\nWARN: {warn}\nERROR: {error}\n"
    out += "status: 2xx={s2} 3xx={s3} 4xx={s4} 5xx={s5} other={sother}\n"

    let n = lats.length()

    if n == 0:
        out += "p95: 0\n"
    else:
        lats.sort()

        let rank = (95 * n + 99) / 100
        out += "p95: {lats[rank - 1]}\n"

        let s = valid[best]
        out += "slowest: {s.latency} {s.method} {s.path} {s.ts}\n"

    out += "top:\n"

    var stats = List[PathStat]()
    for p in counts.keys():
        stats.append(PathStat(path: p.clone(), count: counts[p], total: totals[p]))
    stats.sort(cmp_stat)

    var k = 0

    while k < 3 and k < stats.length():
        let st = stats[k]
        out += "{st.path} {st.count} avg={st.total / st.count}\n"
        k += 1

    stdout().write(out).get()
    return 0
