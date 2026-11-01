import stdout from "@std/io/io.ms"
import monotonic from "@std/os/time.ms"

type Body:
    x: Float
    y: Float
    z: Float
    vx: Float
    vy: Float
    vz: Float
    mass: Float

type Grid:
    width: Int
    height: Int
    cells: List[Int]

type Tree:
    case Leaf
    case Node(left: Tree, right: Tree)

fn say(text: String) Unit:
    let _ignored = stdout().write(text)

fn sieve(n: Int) Int:
    var flags: List[Bool] = List[Bool]()
    var i = 0

    while i <= n:
        flags.append(true)
        i += 1

    var count = 0
    i = 2

    while i <= n:
        if flags.get(i):
            count += 1

            var j = i * i

            while j <= n:
                flags.set(j, false)
                j += i

        i += 1

    return count

fn advance(var bodies: List[Body], steps: Int) Float:
    let n = bodies.length()
    var s = 0

    while s < steps:
        var i = 0

        while i < n:
            var a = bodies.get(i)
            var j = i + 1

            while j < n:
                var b = bodies.get(j)
                let dx = a.x - b.x
                let dy = a.y - b.y
                let dz = a.z - b.z
                let d2 = dx * dx + dy * dy + dz * dz + 0.01
                let mag = 0.01 / (d2 * d2)
                a.vx -= dx * b.mass * mag
                a.vy -= dy * b.mass * mag
                a.vz -= dz * b.mass * mag
                b.vx += dx * a.mass * mag
                b.vy += dy * a.mass * mag
                b.vz += dz * a.mass * mag
                bodies.set(j, b)
                j += 1

            bodies.set(i, a)
            i += 1

        i = 0

        while i < n:
            var a = bodies.get(i)
            a.x += 0.01 * a.vx
            a.y += 0.01 * a.vy
            a.z += 0.01 * a.vz
            bodies.set(i, a)
            i += 1

        s += 1

    var e = 0.0
    var k = 0

    while k < n:
        let a = bodies.get(k)
        e += a.mass * (a.vx * a.vx + a.vy * a.vy + a.vz * a.vz)
        k += 1

    return e

fn cell(g: Grid, x: Int, y: Int) Int:
    let wx = (x + g.width) % g.width
    let wy = (y + g.height) % g.height
    return g.cells.get(wy * g.width + wx)

fn neighbors(g: Grid, x: Int, y: Int) Int:
    var n = 0
    var dy = -1

    while dy <= 1:
        var dx = -1

        while dx <= 1:
            if not (dx == 0 and dy == 0):
                n += cell(g, x + dx, y + dy)
            dx += 1

        dy += 1

    return n

fn step(g: Grid) Grid:
    var next = List[Int]()
    var y = 0

    while y < g.height:
        var x = 0

        while x < g.width:
            let n = neighbors(g, x, y)
            let alive = cell(g, x, y) == 1

            if n == 3 or (alive and n == 2):
                next.append(1)
            else:
                next.append(0)

            x += 1

        y += 1

    return Grid(g.width, g.height, next)

fn life(gens: Int) Int:
    var cells = List[Int]()
    var i = 0

    while i < 128 * 128:
        if i % 7 == 0 or i % 11 == 0:
            cells.append(1)
        else:
            cells.append(0)

        i += 1

    var g = Grid(128, 128, cells)
    var n = 0

    while n < gens:
        g = step(g)
        n += 1

    return g.cells.fold(0, fn(acc: Int, v: Int) Int: return acc + v)

fn matmul(n: Int) Float:
    var a = List[List[Float]]()
    var b = List[List[Float]]()
    var i = 0

    while i < n:
        var ra = List[Float]()
        var rb = List[Float]()
        var j = 0

        while j < n:
            ra.append((i + j).to_float())
            rb.append((i - j).to_float())
            j += 1

        a.append(ra)
        b.append(rb)
        i += 1

    var total = 0.0
    i = 0

    while i < n:
        var j = 0

        while j < n:
            var s = 0.0
            var k = 0

            while k < n:
                s += a.get(i).get(k) * b.get(k).get(j)
                k += 1

            total += s
            j += 1

        i += 1

    return total

fn make(depth: Int) Tree:
    if depth == 0:
        return Leaf

    return Node(make(depth - 1), make(depth - 1))

fn check(t: Tree) Int:
    match t:
        Leaf:
            return 1
        Node(l, r):
            return 1 + check(l) + check(r)

fn trees(rounds: Int) Int:
    var total = 0
    var r = 0

    while r < rounds:
        total += check(make(16))
        r += 1

    return total

fn collatz(limit: Int) Int:
    var best = 0
    var n = 1

    while n < limit:
        var x = n
        var steps = 0

        while x != 1:
            if x % 2 == 0:
                x = x / 2
            else:
                x = 3 * x + 1

            steps += 1

        if steps > best:
            best = steps
        n += 1

    return best

fn wordfreq(n: Int) Int:
    var m = Map[Int, Int]()
    var i = 0

    while i < n:
        let k = (i * 7919) % 5003
        m.add(k, m.get_or(k, 0) + 1)
        i += 1

    return m.length()

fn timed(name: String, run: fn() Int) Unit:
    let t = monotonic()
    let r = run()
    say("{name} {monotonic().difference(t).to_nanoseconds() / 1000} {r}\n")

export fn main() Int:
    timed("sieve_5M", fn() Int: return sieve(5000000))

    timed(
        "nbody_200k",
        fn() Int:
            var bodies = [
                Body(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 10.0),
                Body(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 1.0),
                Body(0.0, 2.0, 0.0, 1.0, 0.0, 0.0, 1.0),
                Body(0.0, 0.0, 3.0, 0.0, 0.0, 1.0, 1.0),
                Body(4.0, 4.0, 0.0, 0.0, 0.0, 0.0, 0.5)
            ]
            return (advance(var bodies, 200000) * 1000.0).truncate_to_int().get(0)
    )

    timed("life_128x128_50", fn() Int: return life(50))
    timed("matmul_200", fn() Int: return matmul(200).truncate_to_int().get(0))
    timed("trees_d16_x20", fn() Int: return trees(20))
    timed("collatz_1M", fn() Int: return collatz(1000000))
    timed("map_count_2M", fn() Int: return wordfreq(2000000))
    return 0
