type Point:
    x: Int

fn identity(value: Int) Int:
    return value

fn sample(point: Point) Int:
    return point.x + identity(1)
