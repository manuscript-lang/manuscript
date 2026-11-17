fn pick(xs: List[Int], i: Int) Int:
    return xs
        .get(i)

fn chain(m: Map[String, Int]) Int:
    c := m.get("c") // keep this note
        .get_or(3)
    return c

export fn main() Void:
    print(f"{pick([1, 2], 1)} {chain(Map[String, Int]())}")
