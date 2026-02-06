// @test: Type Definitions - Types with fields and defaults

// === Type with required fields ===
type Point
  x: number
  y: number

let p = Point(3, 4)
// @expect: 3 4
print(p.x, p.y)

// === Type with default fields ===
type Config
  name: string
  value: number = 0
  enabled: bool = true

let cfg1 = Config("test")
// @expect: test 0 true
print(cfg1.name, cfg1.value, cfg1.enabled)

let cfg2 = Config("test2", 42, false)
// @expect: test2 42 false
print(cfg2.name, cfg2.value, cfg2.enabled)

// === Type with optional fields ===
type User
  name: string
  age: number
  email?: string

let user1 = User("Alice", 30)
// @expect: Alice 30
print(user1.name, user1.age)

// === Type used in functions ===
fn distance(p: Point): number
  sqrt(p.x ^ 2 + p.y ^ 2)

// @expect: 5
print(distance(p))

fn add_points(a: Point, b: Point): Point
  Point(a.x + b.x, a.y + b.y)

let p2 = Point(2, 3)
let p3 = add_points(p, p2)
// @expect: 5 7
print(p3.x, p3.y)

// === Nested type structures ===
type Rectangle
  origin: Point
  width: number
  height: number

let rect = Rectangle(Point(0, 0), 10, 5)
// @expect: 0 0
print(rect.origin.x, rect.origin.y)
// @expect: 10 5
print(rect.width, rect.height)

// === Type with computed field ===
type Circle
  radius: number
  diameter: () => radius * 2

let circle = Circle(5)
// @expect: 5
print(circle.radius)
// @expect: 10
print(circle.diameter())

// === Multiple type instances ===
type Counter
  name: string
  value: number = 0

let c1 = Counter("first")
let c2 = Counter("second", 10)
// @expect: first 0
print(c1.name, c1.value)
// @expect: second 10
print(c2.name, c2.value)

// === Type in list ===
let points = [Point(1, 2), Point(3, 4), Point(5, 6)]
// @expect: 3
print(len(points))
// @expect: 3 4
print(points[1].x, points[1].y)

// === Type in map ===
let config_map = {dev: Config("dev", 1), prod: Config("prod", 2)}
// @expect: dev 1
print(config_map.dev.name, config_map.dev.value)
// @expect: prod 2
print(config_map.prod.name, config_map.prod.value)
