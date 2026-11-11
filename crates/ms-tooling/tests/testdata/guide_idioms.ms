fn twice(value: Int) Int: value * 2

fn fail(_value: Int) Int!: error(Error("kept"))

fn main() Int:
    value: Int := 2
    input: Int? := value
    mapped: (Int!)? := input.map(fail)
    if result := mapped:
        if not result.is_error(): return 2
    else: return 3
    if twice(value) == 4: return 0
    else: return 1
