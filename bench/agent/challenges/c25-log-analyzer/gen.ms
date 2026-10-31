# Generator for c25-log-analyzer. Deterministic; run: ms run bench/agent/gen.ms -- c25
import GenCase, make_case, write_cases from "../../lib/gen.ms"
import seeded from "../../lib/pyrandom.ms"
import Random from "../../lib/pyrandom.ms"

let LEVELS = ["DEBUG", "INFO", "WARN", "ERROR"]
let METHODS = ["DELETE", "GET", "POST", "PUT"]

fn digits(s: String) Bool: (
    not s.is_empty()
    and s.chars().all(fn c: "0123456789".contains(c))
)

type Entry:
    level: String
    path: String
    status: Int
    latency: Int
    method: String
    ts: String

fn parse(line: String) Entry?:
    let f = line.split(" ")
    if f.length() != 6: return none
    if f[0].is_empty() or not LEVELS.contains(f[1]) or not METHODS.contains(f[2]): return none
    if not f[3].starts_with("/") or not (f[4].length() == 3 and digits(f[4])): return none
    if not digits(f[5]) or f[5].length() > 9: return none

    return Entry(
        f[1].clone(), f[3].clone(), f[4].parse_int().get(0), f[5].parse_int().get(0),
        f[2].clone(), f[0].clone()
    )

fn solve(s: String) String:
    var valid = 0
    var bad = 0
    var classes = [0, 0, 0, 0, 0]
    var lats = List[Int]()
    var slow: Entry? = none
    var levels = Map[String, Int]()
    var counts = Map[String, Int]()
    var totals = Map[String, Int]()

    for line in s.split("\n"):
        if line.trim().is_empty(): continue

        let r = parse(line)

        if r.is_none():
            bad += 1
            continue

        let e = r.get(Entry("", "", 0, 0, "", ""))
        valid += 1
        levels[e.level.clone()] = levels.get_or(e.level, 0) + 1

        let first = "{e.status}".take(1)

        let class = if first == "2": 0 else: if first == "3": 1 else: if first == "4": 2 else: if first == "5": 3 else: 4

        classes[class] = classes[class] + 1
        lats.append(e.latency)
        if slow.is_none() or e.latency > slow.get(e).latency: slow = e.clone()
        counts[e.path.clone()] = counts.get_or(e.path, 0) + 1
        totals[e.path.clone()] = totals.get_or(e.path, 0) + e.latency

    var out = ["valid: {valid}", "malformed: {bad}"]
    for l in LEVELS: out.append("{l}: {levels.get_or(l, 0)}")
    out.append(
        "status: 2xx={classes[0]} 3xx={classes[1]} 4xx={classes[2]} 5xx={classes[3]} other={classes[4]}"
    )

    let sorted_lats = lats.sorted()
    out.append(
        "p95: {if lats.is_empty(): 0 else: sorted_lats[(95 * lats.length() + 99) / 100 - 1]}"
    )
    if let e = slow: out.append("slowest: {e.latency} {e.method} {e.path} {e.ts}")
    out.append("top:")

    let order = counts.keys().sorted(
        fn a,
        b: if counts.get_or(a, 0) != counts.get_or(b, 0): counts.get_or(
            b, 0
        ) - counts.get_or(a, 0) else: a.compare(b)
    )
    for p in order.take(3):
        out.append(
            "{p} {counts.get_or(p, 0)} avg={totals.get_or(p, 0) / counts.get_or(p, 0)}"
        )
    return out.map(fn o: o + "\n").join("")

fn mk(name: String, s: String) GenCase: make_case(name, s, solve(s))

fn good(var rnd: Random, i: Int) String:
    let level = rnd.choice(LEVELS)
    let method = rnd.choice(METHODS)
    let path = rnd.choice(
        [
            "/", "/api/users", "/api/orders", "/health", "/static/app.js", "/login",
            "/a", "/b", "/c"
        ]
    )
    let statuses = [200, 200, 201, 301, 404, 500, 503]
    let pick = rnd.below(statuses.length())
    let lat = rnd.randint(0, 900)
    return "2024-05-01T10:{"{i / 60 % 60}".pad_start(2, "0")}:{"{i % 60}".pad_start(2, "0")} {level} {method} {path} {statuses[pick]} {lat}"

fn mangle(var rnd: Random, l: String) String:
    var f = l.split(" ")
    let k = rnd.randrange(0, 9)

    if k == 0:
        f[1] = f[1].lower()
    else if k == 1:
        f[2] = "PATCH"
    else if k == 2:
        let rest = f[3].slice(1, f[3].length()).get("")
        f[3] = if rest.is_empty(): "x" else: rest
    else if k == 3:
        f[4] = "20"
    else if k == 4:
        f[5] = "12ms"
    else if k == 5:
        f = f.take(5)
    else if k == 6:
        f.append("extra")
    else if k == 7:
        return l + " "
    else:
        f[5] = ""

    return f.join(" ")

fn rand_log(var rnd: Random, n: Int, bad: Float) String:
    var ls = List[String]()

    for i in 0..n:
        let l = good(var rnd, i)
        ls.append(if rnd.random() < bad: mangle(var rnd, l) else: l)
        if rnd.random() < 0.03: ls.append(rnd.choice(["", "   "]))

    return ls.join("\n") + "\n"

export fn gen_c25() Unit:
    var rnd = seeded(25)
    let examples = [
        mk(
            "basic",
            "2024-05-01T10:00:00 INFO GET /api/users 200 12\n2024-05-01T10:00:01 ERROR POST /api/orders 503 250\nthis line is broken\n2024-05-01T10:00:02 INFO GET /api/users 200 15\n2024-05-01T10:00:03 WARN GET /health 404 1\n"
        ),
        mk("all-malformed", "x\n\nINFO GET / 200 1\n")
    ]
    var p95 = ""
    for i in 0..40: p95 = p95 + "t{i} INFO PUT /q{i % 3} 200 {(i * 37) % 101}\n"

    let small = rand_log(var rnd, 40, 0.1)
    let mid = rand_log(var rnd, 600, 0.2)
    let large = rand_log(var rnd, 5000, 0.05)
    let hidden = examples.concat(
        [
            mk("empty", ""),
            mk("only-blank", "\n  \n\n"),
            mk("one-valid", "t DEBUG PUT /x 099 0\n"),
            mk(
                "tie-break-path",
                "t INFO GET /b 200 1\nt INFO GET /a 200 1\nt INFO GET /c 200 1\nt INFO GET /d 200 1\nt INFO GET /d 200 3\n"
            ),
            mk(
                "floor-avg",
                "t INFO GET /p 200 1\nt INFO GET /p 200 2\nt INFO GET /p 200 2\n"
            ),
            mk(
                "status-classes",
                "t INFO GET /p 499 1\nt INFO GET /p 500 1\nt INFO GET /p 999 1\nt INFO GET /p 099 1\nt INFO GET /p 100 1\nt INFO GET /p 302 1\nt INFO GET /p 204 1\n"
            ),
            mk("p95-and-slowest", p95 + "t99 INFO GET /z 200 100\n"),
            mk(
                "spacing-and-case",
                "t INFO  GET /p 200 1\nt  INFO GET /p 200 1\n t INFO GET /p 200 1\nt info GET /p 200 1\nt INFO get /p 200 1\nt INFO GET p 200 1\nt INFO GET /p 2000 1\nt INFO GET /p 20a 1\nt INFO GET /p 200 -1\nt INFO GET /p 200 1234567890\nt INFO GET /p 200 123456789\n"
            ),
            mk("no-trailing-newline", "t ERROR POST /z 500 7"),
            mk("random-small", small),
            mk("random-mid", mid),
            mk("random-large", large)
        ]
    )
    write_cases("c25-log-analyzer", examples, hidden)
