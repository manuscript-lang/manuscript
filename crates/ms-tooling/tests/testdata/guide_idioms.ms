fn twice(value: Int) Int: value * 2

fn fail(_value: Int) Int!: error(Error("kept"))

fn main() Int:
    value: Int := 2
    input: Int? := value
    mapped: (Int!)? := input.map(fail)
    if result := mapped:
        if _value := result:
            return 2
        else:
            if result.err().message != "kept": return 4
    else: return 3
    values := [1, 2, 3, 4]
    total := values | .filter(fn x: x > 2) | .map(fn x: x * 2) | .sum()
    if total != 14: return 5
    if twice(value) == 4: return 0
    else: return 1
