# The whole-program kernels from bench/perf/kernels/ms, rewritten for the
# proposed value semantics: `mut` replaces `var`, values have one owner,
# parameters borrow unless marked `mut`, and list elements are reached by
# index because two `mut` borrows into one list would overlap.

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

fn sieve(n: Int) Int:
    mut flags = List[Bool]()
    mut i = 0
    while i <= n:
        flags.append(true)
        i += 1
    mut count = 0
    i = 2
    while i <= n:
        if flags[i]:
            count += 1
            mut j = i * i
            while j <= n:
                flags[j] = false
                j += i
        i += 1
    return count

fn advance(mut bodies: List[Body], steps: Int) Float:
    let n = bodies.length()
    mut s = 0
    while s < steps:
        mut i = 0
        while i < n:
            mut j = i + 1
            while j < n:
                let a = bodies[i]
                let b = bodies[j]
                let dx = a.x - b.x
                let dy = a.y - b.y
                let dz = a.z - b.z
                let d2 = dx * dx + dy * dy + dz * dz + 0.01
                let mag = 0.01 / (d2 * d2)
                bodies[i].vx -= dx * b.mass * mag
                bodies[i].vy -= dy * b.mass * mag
                bodies[i].vz -= dz * b.mass * mag
                bodies[j].vx += dx * a.mass * mag
                bodies[j].vy += dy * a.mass * mag
                bodies[j].vz += dz * a.mass * mag
                j += 1
            i += 1
        i = 0
        while i < n:
            bodies[i].x += 0.01 * bodies[i].vx
            bodies[i].y += 0.01 * bodies[i].vy
            bodies[i].z += 0.01 * bodies[i].vz
            i += 1
        s += 1
    mut e = 0.0
    mut k = 0
    while k < n:
        let a = bodies[k]
        e += a.mass * (a.vx * a.vx + a.vy * a.vy + a.vz * a.vz)
        k += 1
    return e

fn cell(g: Grid, x: Int, y: Int) Int:
    let wx = (x + g.width) % g.width
    let wy = (y + g.height) % g.height
    return g.cells[wy * g.width + wx]

fn neighbors(g: Grid, x: Int, y: Int) Int:
    mut n = 0
    mut dy = -1
    while dy <= 1:
        mut dx = -1
        while dx <= 1:
            if not (dx == 0 and dy == 0):
                n += cell(g, x + dx, y + dy)
            dx += 1
        dy += 1
    return n

fn step(g: Grid) Grid:
    mut next = List[Int]()
    mut y = 0
    while y < g.height:
        mut x = 0
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
    mut cells = List[Int]()
    mut i = 0
    while i < 128 * 128:
        if i % 7 == 0 or i % 11 == 0:
            cells.append(1)
        else:
            cells.append(0)
        i += 1
    mut g = Grid(128, 128, cells)
    mut n = 0
    while n < gens:
        g = step(g)
        n += 1
    mut sum = 0
    mut k = 0
    while k < g.cells.length():
        sum += g.cells[k]
        k += 1
    return sum

fn matmul(n: Int) Float:
    mut a = List[List[Float]]()
    mut b = List[List[Float]]()
    mut i = 0
    while i < n:
        mut ra = List[Float]()
        mut rb = List[Float]()
        mut j = 0
        while j < n:
            ra.append((i + j).to_float())
            rb.append((i - j).to_float())
            j += 1
        a.append(ra)
        b.append(rb)
        i += 1
    mut total = 0.0
    i = 0
    while i < n:
        mut j = 0
        while j < n:
            mut s = 0.0
            mut k = 0
            while k < n:
                s += a[i][k] * b[k][j]
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
    mut total = 0
    mut r = 0
    while r < rounds:
        total += check(make(16))
        r += 1
    return total

fn collatz(limit: Int) Int:
    mut best = 0
    mut n = 1
    while n < limit:
        mut x = n
        mut steps = 0
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
    mut m = Map[Int, Int]()
    mut i = 0
    while i < n:
        let k = (i * 7919) % 5003
        m.add(k, m.get(k).get(0) + 1)
        i += 1
    return m.length()

fn nbody() Int:
    mut bodies = List[Body]()
    bodies.append(Body(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 10.0))
    bodies.append(Body(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 1.0))
    bodies.append(Body(0.0, 2.0, 0.0, 1.0, 0.0, 0.0, 1.0))
    bodies.append(Body(0.0, 0.0, 3.0, 0.0, 0.0, 1.0, 1.0))
    bodies.append(Body(4.0, 4.0, 0.0, 0.0, 0.0, 0.0, 0.5))
    return (advance(mut bodies, 200000) * 1000.0).truncate_to_int().get(0)

export fn main() Int:
    mut t = now_us()
    mut r = sieve(5000000)
    report("sieve_5M", now_us() - t, r)
    t = now_us()
    r = nbody()
    report("nbody_200k", now_us() - t, r)
    t = now_us()
    r = life(50)
    report("life_128x128_50", now_us() - t, r)
    t = now_us()
    r = matmul(200).truncate_to_int().get(0)
    report("matmul_200", now_us() - t, r)
    t = now_us()
    r = trees(20)
    report("trees_d16_x20", now_us() - t, r)
    t = now_us()
    r = collatz(1000000)
    report("collatz_1M", now_us() - t, r)
    t = now_us()
    r = wordfreq(2000000)
    report("map_count_2M", now_us() - t, r)
    return 0
