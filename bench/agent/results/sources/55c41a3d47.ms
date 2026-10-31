import stdin, stdout from "@std/io.ms"
import read_lines from "@std/streams.ms"

type Rec:
    ts: String
    level: String
    method: String
    path: String
    status: String
    lat_text: String
    lat: Int

fn is_digits(s: String) Bool:
    if s.is_empty():
        return false

    for i in 0..s.scalar_length():
        if not "0123456789".contains(s.get(i)):
            return false
    return true

fn parse(line: String) Rec?:
    let f = line.split(" ")
    if f.length() != 6:
        return none
    if f[0].is_empty():
        return none

    let lvl = f[1]
    if not (lvl == "DEBUG" or lvl == "INFO" or lvl == "WARN" or lvl == "ERROR"):
        return none

    let m = f[2]
    if not (m == "GET" or m == "POST" or m == "PUT" or m == "DELETE"):
        return none
    if f[3].is_empty() or not f[3].starts_with("/"):
        return none
    if f[4].scalar_length() != 3 or not is_digits(f[4]):
        return none
    if f[5].scalar_length() > 9 or not is_digits(f[5]):
        return none

    let lat = f[5].parse_int().get(0)
    return Rec(
        ts: f[0].clone(), level: lvl.clone(), method: m.clone(), path: f[3].clone(),
        status: f[4].clone(), lat_text: f[5].clone(), lat: lat
    )

export fn main() Int:
    let lines = read_lines(stdin()).get()
    var recs = List[Rec]()
    var malformed = 0

    for line in lines:
        if line.trim().is_empty():
            continue

        if let r = parse(line):
            recs.append(r)
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
    var other = 0

    for r in recs:
        if r.level == "DEBUG":
            debug += 1
        else if r.level == "INFO":
            info += 1
        else if r.level == "WARN":
            warn += 1
        else:
            error += 1

        let c = r.status.get(0)

        if c == "2":
            s2 += 1
        else if c == "3":
            s3 += 1
        else if c == "4":
            s4 += 1
        else if c == "5":
            s5 += 1
        else:
            other += 1

    var lats = List[Int]()
    for r in recs:
        lats.append(r.lat)
    lats.sort()

    let n = lats.length()
    var p95 = 0
    if n > 0:
        p95 = lats[(95 * n + 99) / 100 - 1]

    var best = -1
    for i in 0..recs.length():
        if best < 0 or recs[i].lat > recs[best].lat:
            best = i

    var counts = Map[String, Int]()
    var totals = Map[String, Int]()

    for r in recs:
        counts.add(r.path.clone(), counts.get_or(r.path, 0) + 1)
        totals.add(r.path.clone(), totals.get_or(r.path, 0) + r.lat)

    stdout().write("valid: {n}\n").get()
    stdout().write("malformed: {malformed}\n").get()
    stdout().write("DEBUG: {debug}\n").get()
    stdout().write("INFO: {info}\n").get()
    stdout().write("WARN: {warn}\n").get()
    stdout().write("ERROR: {error}\n").get()
    stdout().write("status: 2xx={s2} 3xx={s3} 4xx={s4} 5xx={s5} other={other}\n").get()
    stdout().write("p95: {p95}\n").get()

    if best >= 0:
        let r = recs[best]
        stdout().write("slowest: {r.lat_text} {r.method} {r.path} {r.ts}\n").get()

    stdout().write("top:\n").get()

    let paths = counts.keys()
    var used = List[Bool]()
    for i in 0..paths.length():
        used.append(false)

    var k = 0

    while k < 3 and k < paths.length():
        var pick = -1

        for i in 0..paths.length():
            if used[i]:
                continue

            if pick < 0:
                pick = i
            else:
                let ci = counts.get_or(paths[i], 0)
                let cp = counts.get_or(paths[pick], 0)
                if ci > cp or (ci == cp and paths[i].compare(paths[pick]) < 0):
                    pick = i

        used[pick] = true

        let p = paths[pick]
        let c = counts.get_or(p, 0)
        let avg = totals.get_or(p, 0) / c
        stdout().write("{p} {c} avg={avg}\n").get()
        k += 1

    return 0
