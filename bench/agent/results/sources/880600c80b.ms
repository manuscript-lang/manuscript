import stdin from "@std/io.ms"
import stdout from "@std/io.ms"
import {read_lines} from "@std/streams.ms"

type Entry:
    timestamp: String
    level: String
    method: String
    path: String
    status: String
    latency: Int

type PathStat:
    path: String
    count: Int
    total: Int

fn is_digits(text: String) Bool:
    if text.length() == 0: return false

    for i in 0..text.length():
        let c = text.get(i)
        if c < "0" or c > "9": return false

    return true

fn parse(line: String) Optional[Entry]:
    let f = line.split(" ")
    if f.length() != 6: return none
    if f[0].length() == 0: return none
    if not ["DEBUG", "INFO", "WARN", "ERROR"].contains(f[1]): return none
    if not ["GET", "POST", "PUT", "DELETE"].contains(f[2]): return none
    if not f[3].starts_with("/"): return none
    if f[4].length() != 3 or not is_digits(f[4]): return none
    if f[5].length() > 9 or not is_digits(f[5]): return none

    return some(
        Entry(
            timestamp: f[0].clone(), level: f[1].clone(), method: f[2].clone(),
            path: f[3].clone(), status: f[4].clone(), latency: f[5].parse_int().get(0)
        )
    )

fn by_rank(a: PathStat, b: PathStat) Int:
    if a.count != b.count: return b.count - a.count

    return a.path.compare(b.path)

export fn main() Int:
    var valid = List[Entry]()
    var malformed = 0

    for line in read_lines(stdin()).get():
        if line.trim().length() == 0: continue

        if let e = parse(line):
            valid.append(e)
        else:
            malformed += 1

    var out = stdout()
    out.write("valid: {valid.length()}\n").get()
    out.write("malformed: {malformed}\n").get()
    out.write("DEBUG: {valid.filter(fn e: e.level == "DEBUG").length()}\n").get()
    out.write("INFO: {valid.filter(fn e: e.level == "INFO").length()}\n").get()
    out.write("WARN: {valid.filter(fn e: e.level == "WARN").length()}\n").get()
    out.write("ERROR: {valid.filter(fn e: e.level == "ERROR").length()}\n").get()

    let class2 = valid.filter(fn e: e.status.get(0) == "2").length()
    let class3 = valid.filter(fn e: e.status.get(0) == "3").length()
    let class4 = valid.filter(fn e: e.status.get(0) == "4").length()
    let class5 = valid.filter(fn e: e.status.get(0) == "5").length()
    (
        out
        .write(
            "status: 2xx={class2} 3xx={class3} 4xx={class4} 5xx={class5} other={valid.length() - class2 - class3 - class4 - class5}\n"
        )
        .get()
    )

    let n = valid.length()

    if n == 0:
        out.write("p95: 0\n").get()
    else:
        let sorted_lat = valid.map(fn e: e.latency).sorted()
        let rank = (95 * n + 99) / 100
        out.write("p95: {sorted_lat[rank - 1]}\n").get()

        var slow = 0
        for i in 0..n:
            if valid[i].latency > valid[slow].latency: slow = i

        let s = valid[slow]
        out.write("slowest: {s.latency} {s.method} {s.path} {s.timestamp}\n").get()

    out.write("top:\n").get()

    var counts = Map[String, Int]()
    var totals = Map[String, Int]()

    for e in valid:
        counts.add(e.path.clone(), counts.get_or(e.path, 0) + 1)
        totals.add(e.path.clone(), totals.get_or(e.path, 0) + e.latency)

    let stats = counts.keys().map(
        fn p: PathStat(
            path: p.clone(), count: counts.get_or(p, 0), total: totals.get_or(p, 0)
        )
    )
    let ranked = stats.sorted(by_rank)

    for i in 0..ranked.length():
        if i == 3: break

        let s = ranked[i]
        out.write("{s.path} {s.count} avg={s.total / s.count}\n").get()

    return 0
