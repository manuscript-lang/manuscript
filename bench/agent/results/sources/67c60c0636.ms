import {stdin, stdout} from "@std/io.ms"
import read_lines from "@std/streams.ms"

type Record:
    timestamp: String
    level: String
    method: String
    path: String
    status: Int
    latency_text: String
    latency: Int

type PathStat:
    path: String
    count: Int
    total: Int

fn is_digits(text: String) Bool:
    return text.length() > 0 and text.chars().all(fn c: "0123456789".contains(c))

fn parse(line: String) Optional[Record]:
    let fields = line.split(" ")
    if fields.length() != 6: return none

    let timestamp = fields[0]
    let level = fields[1]
    let method = fields[2]
    let path = fields[3]
    let status = fields[4]
    let latency = fields[5]
    if timestamp.is_empty(): return none
    if not ["DEBUG", "INFO", "WARN", "ERROR"].contains(level): return none
    if not ["GET", "POST", "PUT", "DELETE"].contains(method): return none
    if not path.starts_with("/"): return none
    if status.length() != 3 or not is_digits(status): return none
    if latency.length() > 9 or not is_digits(latency): return none

    return some(
        Record(
            timestamp: timestamp.clone(), level: level.clone(), method: method.clone(),
            path: path.clone(), status: status.parse_int().get(0),
            latency_text: latency.clone(), latency: latency.parse_int().get(0)
        )
    )

fn rank(a: PathStat, b: PathStat) Int:
    if a.count != b.count: return b.count - a.count

    return a.path.compare(b.path)

export fn main() Int:
    var records = List[Record]()
    var malformed = 0
    var levels = Map[String, Int]()

    for line in read_lines(stdin()).get():
        if line.trim().is_empty(): continue

        if let record = parse(line):
            levels.update(record.level.clone(), 0, fn n: n + 1)
            records.append(record)
        else:
            malformed += 1

    var s2 = 0
    var s3 = 0
    var s4 = 0
    var s5 = 0
    var s_other = 0

    for r in records:
        let bucket = r.status / 100

        if bucket == 2: s2 += 1
        else if bucket == 3: s3 += 1
        else if bucket == 4: s4 += 1
        else if bucket == 5: s5 += 1
        else: s_other += 1

    var lines = List[String]()
    lines.append("valid: {records.length()}")
    lines.append("malformed: {malformed}")
    lines.append("DEBUG: {levels.get_or("DEBUG", 0)}")
    lines.append("INFO: {levels.get_or("INFO", 0)}")
    lines.append("WARN: {levels.get_or("WARN", 0)}")
    lines.append("ERROR: {levels.get_or("ERROR", 0)}")
    lines.append("status: 2xx={s2} 3xx={s3} 4xx={s4} 5xx={s5} other={s_other}")

    if records.length() == 0:
        lines.append("p95: 0")
    else:
        let sorted_records = records.sorted(fn a, b: a.latency - b.latency)
        let n = sorted_records.length()
        let rank_index = (95 * n + 99) / 100 - 1
        lines.append("p95: {sorted_records[rank_index].latency_text}")

        var slowest = 0
        for i in 0..records.length():
            if records[i].latency > records[slowest].latency: slowest = i

        let s = records[slowest]
        lines.append("slowest: {s.latency_text} {s.method} {s.path} {s.timestamp}")

    lines.append("top:")

    if records.length() > 0:
        var counts = Map[String, Int]()
        var totals = Map[String, Int]()

        for r in records:
            counts.update(r.path, 0, fn n: n + 1)
            totals.update(r.path, 0, fn t: t + r.latency)

        var stats = List[PathStat]()
        for p in counts.keys():
            stats.append(
                PathStat(
                    path: p.clone(), count: counts.get_or(p, 0),
                    total: totals.get_or(p, 0)
                )
            )
        stats.sort(rank)

        let shown = if stats.length() < 3: stats.length() else: 3

        for i in 0..shown:
            let s = stats[i]
            lines.append("{s.path} {s.count} avg={s.total / s.count}")

    stdout().write(lines.join("\n") + "\n").get()
    return 0
