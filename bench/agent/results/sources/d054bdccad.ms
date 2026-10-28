import {stdin, stdout} from "@std/io.ms"
import read_lines from "@std/streams.ms"

type Record:
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

fn all_digits(text: String) Bool:
    for i in 0..text.length():
        let c = text.get(i)
        if c.compare("0") < 0 or c.compare("9") > 0: return false

    return true

fn parse_line(line: String) Optional[Record]:
    let fields = line.split(" ")
    if fields.length() != 6: return none

    let timestamp = fields[0]
    let level = fields[1]
    let method = fields[2]
    let path = fields[3]
    let status = fields[4]
    let latency = fields[5]
    if timestamp.length() == 0: return none
    if not ["DEBUG", "INFO", "WARN", "ERROR"].contains(level): return none
    if not ["GET", "POST", "PUT", "DELETE"].contains(method): return none
    if path.length() == 0 or not path.starts_with("/"): return none
    if status.length() != 3 or not all_digits(status): return none
    if latency.length() < 1 or latency.length() > 9 or not all_digits(latency): return none

    return Record(
        timestamp: timestamp.clone(), level: level.clone(), method: method.clone(),
        path: path.clone(), status: status.clone(), latency: latency.parse_int().get(0)
    )

fn busier(a: PathStat, b: PathStat) Int:
    if a.count > b.count: return -1
    if a.count < b.count: return 1

    return a.path.compare(b.path)

export fn main() Int:
    let lines = read_lines(stdin()).get()
    var records = List[Record]()
    var malformed = 0

    for line in lines:
        if line.trim().length() == 0: continue

        if let rec = parse_line(line):
            records.append(rec)
        else:
            malformed += 1

    var levels = Map[String, Int]()
    var classes = Map[String, Int]()
    var latencies = List[Int]()
    var counts = Map[String, Int]()
    var totals = Map[String, Int]()

    for rec in records:
        levels[rec.level.clone()] = levels.get_or(rec.level, 0) + 1

        let cls = rec.status.get(0)
        classes[cls.clone()] = classes.get_or(cls, 0) + 1
        latencies.append(rec.latency)
        counts[rec.path.clone()] = counts.get_or(rec.path, 0) + 1
        totals[rec.path.clone()] = totals.get_or(rec.path, 0) + rec.latency

    var out = List[String]()
    out.append("valid: {records.length()}")
    out.append("malformed: {malformed}")
    for level in ["DEBUG", "INFO", "WARN", "ERROR"]:
        out.append("{level}: {levels.get_or(level, 0)}")

    let c2 = classes.get_or("2", 0)
    let c3 = classes.get_or("3", 0)
    let c4 = classes.get_or("4", 0)
    let c5 = classes.get_or("5", 0)
    out.append(
        "status: 2xx={c2} 3xx={c3} 4xx={c4} 5xx={c5} other={records.length() - c2 - c3 - c4 - c5}"
    )
    latencies.sort()

    let n = latencies.length()
    var p95 = 0
    if n > 0: p95 = latencies[(95 * n + 99) / 100 - 1]
    out.append("p95: {p95}")

    var best = -1
    for i in 0..records.length():
        if best < 0 or records[i].latency > records[best].latency: best = i

    if best >= 0:
        let rec = records[best]
        out.append("slowest: {rec.latency} {rec.method} {rec.path} {rec.timestamp}")

    var stats = List[PathStat]()
    for path in counts.keys():
        stats.append(
            PathStat(
                path: path.clone(), count: counts[path], total: totals[path]
            )
        )
    stats.sort(busier)
    out.append("top:")

    for i in 0..stats.length():
        if i >= 3: break

        let s = stats[i]
        out.append("{s.path} {s.count} avg={s.total / s.count}")

    stdout().write(out.join("\n") + "\n").get()
    return 0
