import stdin, stdout from "@std/io.ms"
import read_lines from "@std/streams.ms"
import range from "@std/collections.ms"

type PathStat:
    path: String
    count: Int
    total: Int

type Record:
    timestamp: String
    level: String
    method: String
    path: String
    status: Int
    latency: Int

fn all_digits(text: String) Bool:
    for c in text.chars():
        if c.compare("0") < 0 or c.compare("9") > 0:
            return false
    return true

fn parse_record(line: String) Optional[Record]:
    let fields = line.split(" ")
    if fields.length() != 6:
        return none

    let timestamp = fields[0]
    let level = fields[1]
    let method = fields[2]
    let path = fields[3]
    let status = fields[4]
    let latency = fields[5]
    if timestamp.is_empty():
        return none
    if level != "DEBUG" and level != "INFO" and level != "WARN" and level != "ERROR":
        return none
    if method != "GET" and method != "POST" and method != "PUT" and method != "DELETE":
        return none
    if path.is_empty() or not path.starts_with("/"):
        return none
    if status.length() != 3 or not all_digits(status):
        return none
    if latency.length() < 1 or latency.length() > 9 or not all_digits(latency):
        return none

    return some(
        Record(
            timestamp: timestamp, level: level, method: method, path: path,
            status: status.parse_int().get(0), latency: latency.parse_int().get(0)
        )
    )

fn rank_order(left: PathStat, right: PathStat) Int:
    if left.count != right.count:
        return right.count - left.count

    return left.path.compare(right.path)

export fn main() Int:
    let lines = read_lines(stdin()).get()
    var malformed = 0
    var records: List[Record] = []

    for line in lines:
        if line.trim().is_empty():
            continue

        if let record = parse_record(line):
            records.append(record)
        else:
            malformed += 1

    var debug_count = 0
    var info_count = 0
    var warn_count = 0
    var error_count = 0
    var class_2xx = 0
    var class_3xx = 0
    var class_4xx = 0
    var class_5xx = 0
    var class_other = 0
    var latencies: List[Int] = []
    var slowest: Optional[Record] = none
    var counts = Map[String, Int]()
    var totals = Map[String, Int]()

    for record in records:
        if record.level == "DEBUG":
            debug_count += 1
        else if record.level == "INFO":
            info_count += 1
        else if record.level == "WARN":
            warn_count += 1
        else:
            error_count += 1

        let class = record.status / 100

        if class == 2:
            class_2xx += 1
        else if class == 3:
            class_3xx += 1
        else if class == 4:
            class_4xx += 1
        else if class == 5:
            class_5xx += 1
        else:
            class_other += 1

        latencies.append(record.latency)

        if let current = slowest:
            if record.latency > current.latency:
                slowest = some(record)
        else:
            slowest = some(record)

        counts.add(record.path, counts.get_or(record.path, 0) + 1)
        totals.add(record.path, totals.get_or(record.path, 0) + record.latency)

    var p95 = 0

    if latencies.length() > 0:
        let sorted_latencies = latencies.sorted(fn(a: Int, b: Int) Int: a - b)
        let rank = (95 * sorted_latencies.length() + 99) / 100
        p95 = sorted_latencies[rank - 1]

    var out = ""
    out += "valid: {records.length()}\n"
    out += "malformed: {malformed}\n"
    out += "DEBUG: {debug_count}\n"
    out += "INFO: {info_count}\n"
    out += "WARN: {warn_count}\n"
    out += "ERROR: {error_count}\n"
    out += "status: 2xx={class_2xx} 3xx={class_3xx} 4xx={class_4xx} 5xx={class_5xx} other={class_other}\n"
    out += "p95: {p95}\n"
    if let worst = slowest:
        out += "slowest: {worst.latency} {worst.method} {worst.path} {worst.timestamp}\n"
    out += "top:\n"

    var stats: List[PathStat] = []
    for path in counts.keys():
        stats.append(
            PathStat(
                path: path, count: counts.get_or(path, 0), total: totals.get_or(path, 0)
            )
        )

    let ranked = stats.sorted(rank_order)
    var shown = ranked.length()
    if shown > 3:
        shown = 3

    for i in range(0, shown):
        let stat = ranked[i]
        out += "{stat.path} {stat.count} avg={stat.total / stat.count}\n"

    stdout().write(out).get()
    return 0
