from "@std/io.ms" import read_all, stdin, stdout
from "@std/collections.ms" import range
from "@std/math.ms" import min

type PathStat:
    path: String
    count: Int
    total: Int

type Entry:
    timestamp: String
    level: String
    method: String
    path: String
    status: String
    latency: Int
    latency_text: String

def all_digits(text: String) -> Bool:
    if text.is_empty(): return False

    return text.scalar_values().fold(True, lambda ok, v: ok and v >= 48 and v <= 57)

def parse_entry(line: String) -> Optional[Entry]:
    let fields = line.split(" ")
    if fields.length() != 6: return none

    let level = fields[1]
    let method = fields[2]
    let path = fields[3]
    let status = fields[4]
    let latency_text = fields[5]
    if fields[0].is_empty(): return none
    if not ["DEBUG", "INFO", "WARN", "ERROR"].contains(level): return none
    if not ["GET", "POST", "PUT", "DELETE"].contains(method): return none
    if not path.starts_with("/"): return none
    if status.length() != 3 or not all_digits(status): return none
    if latency_text.length() > 9 or not all_digits(latency_text): return none

    return some(
        Entry(
            timestamp: fields[0], level: level, method: method, path: path,
            status: status, latency: latency_text.parse_int().get(0),
            latency_text: latency_text
        )
    )

def compare_paths(a: PathStat, b: PathStat) -> Int:
    if a.count != b.count: return b.count - a.count

    return a.path.compare(b.path)

def report(text: String) -> Unit:
    stdout().write(f"{text}\n").get()

export def main() -> Int:
    let text = read_all(stdin()).get().decode_utf8().get()
    var levels = Map[String, Int]()
    var status_counts = [0, 0, 0, 0, 0]
    var counts = Map[String, Int]()
    var totals = Map[String, Int]()
    var latencies: List[Int] = []
    var valid = 0
    var malformed = 0
    var slowest: Optional[Entry] = none

    for line in text.split("\n"):
        if line.trim().is_empty(): continue

        if let entry = parse_entry(line):
            valid += 1
            levels.add(entry.level, levels.get_or(entry.level, 0) + 1)

            let digit = entry.status.scalar_at(0) - 48

            if digit == 2: status_counts[0] += 1
            elif digit == 3: status_counts[1] += 1
            elif digit == 4: status_counts[2] += 1
            elif digit == 5: status_counts[3] += 1
            else: status_counts[4] += 1

            counts.add(entry.path, counts.get_or(entry.path, 0) + 1)
            totals.add(entry.path, totals.get_or(entry.path, 0) + entry.latency)
            latencies.append(entry.latency)

            if let best = slowest:
                if entry.latency > best.latency: slowest = some(entry)
            else:
                slowest = some(entry)
        else:
            malformed += 1

    report(f"valid: {valid}")
    report(f"malformed: {malformed}")
    for level in ["DEBUG", "INFO", "WARN", "ERROR"]:
        report(f"{level}: {levels.get_or(level, 0)}")
    report(
        f"status: 2xx={status_counts[0]} 3xx={status_counts[1]} 4xx={status_counts[2]} 5xx={status_counts[3]} other={status_counts[4]}"
    )

    let sorted_latencies = latencies.sorted(lambda a, b: a - b)
    let n = sorted_latencies.length()
    var p95 = 0
    if n > 0: p95 = sorted_latencies[(95 * n + 99) / 100 - 1]
    report(f"p95: {p95}")
    if let best = slowest:
        report(
            f"slowest: {best.latency_text} {best.method} {best.path} {best.timestamp}"
        )
    report("top:")

    var stats: List[PathStat] = []

    for path in counts.keys():
        let count = counts.get_or(path, 0)
        stats.append(PathStat(path: path, count: count, total: totals.get_or(path, 0)))

    let paths = stats.sorted(lambda a, b: compare_paths(a, b))

    for i in range(0, min(3, paths.length())):
        let stat = paths[i]
        report(f"{stat.path} {stat.count} avg={stat.total / stat.count}")

    return 0
