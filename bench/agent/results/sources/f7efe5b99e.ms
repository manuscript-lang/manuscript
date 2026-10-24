from "@std/io.ms" import read_line, stdin, stdout
from "@std/collections.ms" import range

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

def out(text: String) -> Unit:
    stdout().write(text).get()

def is_digits(text: String, min_len: Int, max_len: Int) -> Bool:
    if text.length() < min_len or text.length() > max_len:
        return False

    for c in text.chars():
        if not "0123456789".contains(c):
            return False
    return True

def parse_entry(line: String) -> Optional[Entry]:
    let fields = line.split(" ")
    if fields.length() != 6:
        return none

    let timestamp = fields.get(0)
    let level = fields.get(1)
    let method = fields.get(2)
    let path = fields.get(3)
    let status = fields.get(4)
    let latency_text = fields.get(5)
    if timestamp.is_empty():
        return none
    if not ["DEBUG", "INFO", "WARN", "ERROR"].contains(level):
        return none
    if not ["GET", "POST", "PUT", "DELETE"].contains(method):
        return none
    if not path.starts_with("/"):
        return none
    if not is_digits(status, 3, 3):
        return none
    if not is_digits(latency_text, 1, 9):
        return none

    return some(
        Entry(
            timestamp: timestamp, level: level, method: method, path: path,
            status: status, latency: latency_text.parse_int().get(0)
        )
    )

def compare_int(left: Int, right: Int) -> Int:
    return left - right

def compare_paths(left: PathStat, right: PathStat) -> Int:
    if left.count != right.count:
        return right.count - left.count

    return left.path.compare(right.path)

def p95(latencies: List[Int]) -> Int:
    if latencies.is_empty():
        return 0

    let rank = (95 * latencies.length() + 99) / 100
    return latencies.get(rank - 1)

def report(entries: List[Entry], malformed: Int) -> Unit:
    var debug = 0
    var info = 0
    var warn = 0
    var error = 0
    var status_2xx = 0
    var status_3xx = 0
    var status_4xx = 0
    var status_5xx = 0
    var status_other = 0
    var latencies: List[Int] = []
    var slowest: Optional[Entry] = none
    var counts: Map[String, Int] = Map[String, Int]()
    var totals: Map[String, Int] = Map[String, Int]()

    for entry in entries:
        if entry.level == "DEBUG":
            debug += 1
        elif entry.level == "INFO":
            info += 1
        elif entry.level == "WARN":
            warn += 1
        else:
            error += 1

        let digit = entry.status.get(0)

        if digit == "2":
            status_2xx += 1
        elif digit == "3":
            status_3xx += 1
        elif digit == "4":
            status_4xx += 1
        elif digit == "5":
            status_5xx += 1
        else:
            status_other += 1

        latencies.append(entry.latency)
        if slowest.is_none() or entry.latency > slowest.get().latency:
            slowest = some(entry)
        counts.add(entry.path, counts.get_or(entry.path, 0) + 1)
        totals.add(entry.path, totals.get_or(entry.path, 0) + entry.latency)

    out(f"valid: {entries.length()}\n")
    out(f"malformed: {malformed}\n")
    out(f"DEBUG: {debug}\n")
    out(f"INFO: {info}\n")
    out(f"WARN: {warn}\n")
    out(f"ERROR: {error}\n")
    out(
        f"status: 2xx={status_2xx} 3xx={status_3xx} 4xx={status_4xx} 5xx={status_5xx} other={status_other}\n"
    )
    out(f"p95: {p95(latencies.sorted(compare_int))}\n")

    if slowest.is_some():
        let slow = slowest.get()
        out(f"slowest: {slow.latency} {slow.method} {slow.path} {slow.timestamp}\n")

    var stats: List[PathStat] = []
    for path in counts.keys():
        stats.append(
            PathStat(
                path: path, count: counts.get_or(path, 0), total: totals.get_or(path, 0)
            )
        )

    let ranked = stats.sorted(compare_paths)
    out("top:\n")

    for i in range(0, ranked.length()):
        if i == 3:
            break

        let stat = ranked.get(i)
        out(f"{stat.path} {stat.count} avg={stat.total / stat.count}\n")

export def main() -> Int:
    var entries: List[Entry] = []
    var malformed = 0
    var reading = True

    while reading:
        let read = read_line(stdin()).get()

        if read.is_none():
            reading = False
        else:
            let line = read.get()
            if line.trim().is_empty():
                continue

            let entry = parse_entry(line)

            if entry.is_none():
                malformed += 1
            else:
                entries.append(entry.get())

    report(entries, malformed)
    stdout().flush().get()
    return 0
