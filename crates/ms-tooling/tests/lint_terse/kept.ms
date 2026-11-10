fn keep(xs: List[Int], flag: Bool, n: Int) Int:
    var after = 0
    while after < n:
        after += 1

    var skip = 0
    while skip < n:
        skip += 1
        if skip == 2:
            continue
        print("{skip}")

    var limit = 3
    var run = 0
    while run < limit:
        limit -= 1
        run += 1

    var mood = 0
    if mood == 0:
        mood = 5

    var plain = 0
    plain = 1
    var by_two = 0
    while by_two < n:
        by_two += 2
    return after + skip + limit + run + mood + plain + by_two

export fn main() Int:
    return keep([1], true, 3)
