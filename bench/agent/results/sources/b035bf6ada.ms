import {read_all, stdin, stdout} from "@std/io.ms"

type Entry:
    timestamp: String
    level: String
    method: String
    path: String
    status: String
    latency: Int

fn is_digits(text: String) Bool:
    if text.is_empty(): return false

    for i in 0..text.length():
        if not "0123456789".contains(text.get(i)): return false
    return true

fn parse_line(line: String) Optional[Entry]:
    let fields = line.split(" ")
    if fields.length() != 6: return none

    let level = fields[1]
    let method = fields[2]
    let path = fields[3]
    let status = fields[4]
    let latency = fields[5]
    if not ["DEBUG", "INFO", "WARN", "ERROR"].contains(level): return none
    if not ["GET", "POST", "PUT", "DELETE"].contains(method): return none
    if not path.starts_with("/"): return none
    if status.length() != 3 or not is_digits(status): return none
    if latency.length() > 9 or not is_digits(latency): return none

    return Entry(
        timestamp: fields[0].clone(), level: level.clone(), method: method.clone(),
        path: path.clone(), status: status.clone(), latency: latency.parse_int().get(0)
    )

export fn main() Int:
    let text = read_all(stdin()).get().decode_utf8().get("")
    var valid = List[Entry]()
    var malformed = 0

    for line in text.split("\n"):
        if line.trim().is_empty(): continue

        if let entry = parse_line(line):
            valid.append(entry)
        else:
            malformed += 1

    var out = List[String]()
    out.append("valid: {valid.length()}")
    out.append("malformed: {malformed}")
    for level in ["DEBUG", "INFO", "WARN", "ERROR"]:
        out.append("{level}: {valid.filter(fn e: e.level == level).length()}")

    let class_2xx = valid.filter(fn e: e.status.get(0) == "2").length()
    let class_3xx = valid.filter(fn e: e.status.get(0) == "3").length()
    let class_4xx = valid.filter(fn e: e.status.get(0) == "4").length()
    let class_5xx = valid.filter(fn e: e.status.get(0) == "5").length()
    let other = valid.length() - class_2xx - class_3xx - class_4xx - class_5xx
    out.append(
        "status: 2xx={class_2xx} 3xx={class_3xx} 4xx={class_4xx} 5xx={class_5xx} other={other}"
    )

    let n = valid.length()
    var p95 = 0

    if n > 0:
        let sorted = valid.map(fn e: e.latency).sorted()
        p95 = sorted[(95 * n + 99) / 100 - 1]

    out.append("p95: {p95}")

    if n > 0:
        var slowest = 0
        for i in 1..n:
            if valid[i].latency > valid[slowest].latency: slowest = i

        let s = valid[slowest]
        out.append("slowest: {s.latency} {s.method} {s.path} {s.timestamp}")

    out.append("top:")

    var counts = Map[String, Int]()
    var totals = Map[String, Int]()

    for e in valid:
        counts.add(e.path.clone(), counts.get_or(e.path, 0) + 1)
        totals.add(e.path.clone(), totals.get_or(e.path, 0) + e.latency)

    let ranked = counts.entries().sorted(
        fn a, b: (if a.value != b.value: b.value - a.value else: a.key.compare(b.key))
    )

    for i in 0..(if ranked.length() > 3: 3 else: ranked.length()):
        let row = ranked[i]
        out.append("{row.key} {row.value} avg={totals.get_or(row.key, 0) / row.value}")

    stdout().write(out.join("\n") + "\n").get()
    return 0
