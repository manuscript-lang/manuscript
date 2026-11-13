fn grind(a: Float, b: Float, up: Bool) Float:
    var x = a
    var y = b
    if up:
        x = x + 1.0
    x = x * 1.0001 + 0.5
    y = y - x / 3.0
    x = x * 1.0001 + 1.5
    y = y - x / 3.0
    x = x * 1.0001 + 2.5
    y = y - x / 3.0
    x = x * 1.0001 + 3.5
    y = y - x / 3.0
    x = x * 1.0001 + 4.5
    y = y - x / 3.0
    x = x * 1.0001 + 5.5
    y = y - x / 3.0
    x = x * 1.0001 + 6.5
    y = y - x / 3.0
    x = x * 1.0001 + 7.5
    y = y - x / 3.0
    x = x * 1.0001 + 8.5
    y = y - x / 3.0
    x = x * 1.0001 + 9.5
    y = y - x / 3.0
    x = x * 1.0001 + 10.5
    y = y - x / 3.0
    x = x * 1.0001 + 11.5
    y = y - x / 3.0
    x = x * 1.0001 + 12.5
    y = y - x / 3.0
    x = x * 1.0001 + 13.5
    y = y - x / 3.0
    x = x * 1.0001 + 14.5
    y = y - x / 3.0
    x = x * 1.0001 + 15.5
    y = y - x / 3.0
    x = x * 1.0001 + 16.5
    y = y - x / 3.0
    x = x * 1.0001 + 17.5
    y = y - x / 3.0
    x = x * 1.0001 + 18.5
    y = y - x / 3.0
    x = x * 1.0001 + 19.5
    y = y - x / 3.0
    x = x * 1.0001 + 20.5
    y = y - x / 3.0
    x = x * 1.0001 + 21.5
    y = y - x / 3.0
    x = x * 1.0001 + 22.5
    y = y - x / 3.0
    x = x * 1.0001 + 23.5
    y = y - x / 3.0
    x = x * 1.0001 + 24.5
    y = y - x / 3.0
    x = x * 1.0001 + 25.5
    y = y - x / 3.0
    x = x * 1.0001 + 26.5
    y = y - x / 3.0
    x = x * 1.0001 + 27.5
    y = y - x / 3.0
    x = x * 1.0001 + 28.5
    y = y - x / 3.0
    x = x * 1.0001 + 29.5
    y = y - x / 3.0
    x = x * 1.0001 + 30.5
    y = y - x / 3.0
    x = x * 1.0001 + 31.5
    y = y - x / 3.0
    x = x * 1.0001 + 32.5
    y = y - x / 3.0
    x = x * 1.0001 + 33.5
    y = y - x / 3.0
    x = x * 1.0001 + 34.5
    y = y - x / 3.0
    x = x * 1.0001 + 35.5
    y = y - x / 3.0
    x = x * 1.0001 + 36.5
    y = y - x / 3.0
    x = x * 1.0001 + 37.5
    y = y - x / 3.0
    x = x * 1.0001 + 38.5
    y = y - x / 3.0
    x = x * 1.0001 + 39.5
    y = y - x / 3.0
    x = x * 1.0001 + 40.5
    y = y - x / 3.0
    x = x * 1.0001 + 41.5
    y = y - x / 3.0
    x = x * 1.0001 + 42.5
    y = y - x / 3.0
    x = x * 1.0001 + 43.5
    y = y - x / 3.0
    x = x * 1.0001 + 44.5
    y = y - x / 3.0
    x = x * 1.0001 + 45.5
    y = y - x / 3.0
    x = x * 1.0001 + 46.5
    y = y - x / 3.0
    x = x * 1.0001 + 47.5
    y = y - x / 3.0
    x = x * 1.0001 + 48.5
    y = y - x / 3.0
    x = x * 1.0001 + 49.5
    y = y - x / 3.0
    x = x * 1.0001 + 50.5
    y = y - x / 3.0
    x = x * 1.0001 + 51.5
    y = y - x / 3.0
    x = x * 1.0001 + 52.5
    y = y - x / 3.0
    x = x * 1.0001 + 53.5
    y = y - x / 3.0
    x = x * 1.0001 + 54.5
    y = y - x / 3.0
    x = x * 1.0001 + 55.5
    y = y - x / 3.0
    x = x * 1.0001 + 56.5
    y = y - x / 3.0
    x = x * 1.0001 + 57.5
    y = y - x / 3.0
    x = x * 1.0001 + 58.5
    y = y - x / 3.0
    x = x * 1.0001 + 59.5
    y = y - x / 3.0
    return x + y

fn wander(a: Float, steps: Float) Float:
    var x = a
    var n = 0.0
    while n < steps:
        x = x * 1.01 + n
        x = x - n / 1.5
        x = x - n / 2.5
        x = x - n / 3.5
        x = x - n / 4.5
        x = x - n / 5.5
        x = x - n / 6.5
        x = x - n / 7.5
        x = x - n / 8.5
        x = x - n / 9.5
        x = x - n / 10.5
        x = x - n / 11.5
        x = x - n / 12.5
        x = x - n / 13.5
        x = x - n / 14.5
        x = x - n / 15.5
        x = x - n / 16.5
        x = x - n / 17.5
        x = x - n / 18.5
        x = x - n / 19.5
        x = x - n / 20.5
        x = x - n / 21.5
        x = x - n / 22.5
        x = x - n / 23.5
        x = x - n / 24.5
        x = x - n / 25.5
        x = x - n / 26.5
        x = x - n / 27.5
        x = x - n / 28.5
        x = x - n / 29.5
        x = x - n / 30.5
        x = x - n / 31.5
        x = x - n / 32.5
        x = x - n / 33.5
        x = x - n / 34.5
        x = x - n / 35.5
        x = x - n / 36.5
        x = x - n / 37.5
        x = x - n / 38.5
        x = x - n / 39.5
        n = n + 1.0
    return x

fn mix(a: Int, b: Int, up: Bool) Int:
    if up:
        return a + b * 3
    return a - b

fn main() Int:
    print(grind(2.0, 3.0, true))
    print(grind(5.0, 1.0, false))
    print(wander(1.0, 100.0))
    print(wander(2.0, 50.0))
    print(mix(5, 7, true) + mix(5, 7, false))
    return 0
