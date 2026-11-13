type Vec3:
    x: Float
    y: Float
    z: Float

type Body:
    pos: Vec3
    vel: Vec3
    mass: Float
    id: Int
    live: Bool

fn add(a: Vec3, b: Vec3) Vec3:
    return Vec3(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z)

fn scale(a: Vec3, k: Float) Vec3:
    return Vec3(x: a.x * k, y: a.y * k, z: a.z * k)

fn step(b: Body, dt: Float) Body:
    if not b.live:
        return b.clone()
    return Body(pos: add(b.pos, scale(b.vel, dt)), vel: b.vel.clone(), mass: b.mass, id: b.id, live: b.live)

fn kick(b: Body, k: Float) Body:
    var out = b.clone()
    out.vel = scale(b.vel, k)
    out.live = b.mass > 0.5
    return out

fn energy(b: Body) Float:
    return 0.5 * b.mass * (b.vel.x * b.vel.x + b.vel.y * b.vel.y + b.vel.z * b.vel.z)

fn run(start: Body, n: Float) Body:
    var b = start
    var i = 0.0
    while i < n:
        b = step(b, 0.01)
        if i > 100.0:
            b = kick(b, 0.99)
        i = i + 1.0
    return b

fn main() Int:
    a := Body(pos: Vec3(x: 0.0, y: 1.0, z: 2.0), vel: Vec3(x: 1.0, y: 0.5, z: 0.25), mass: 2.0, id: 0, live: true)
    c := Body(pos: Vec3(x: 5.0, y: 5.0, z: 5.0), vel: Vec3(x: -1.0, y: 0.0, z: 1.0), mass: 0.25, id: 100, live: true)
    r := run(a, 1000.0)
    s := run(c, 500.0)
    print(r.pos.x)
    print(r.pos.y)
    print(r.pos.z)
    print(r.id)
    print(s.live)
    print(s.id)
    print(energy(r) + energy(s))
    return 0
