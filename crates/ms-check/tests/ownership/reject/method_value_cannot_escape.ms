def adder(var xs: List[Int]) -> Callable[[Int], Unit]:
    return xs.append  # error: cannot be returned
