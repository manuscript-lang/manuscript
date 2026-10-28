def combine(left: Int, right: Int) -> Int:
    return left + right

def defaults(left: Int = 1, right: Int = 2) -> Int:
    return left + right

def collections(items: List[Int], lookup: Map[String, Int]) -> Int:
    return 0

def invoke(callback: Callable[[Int, Int], Int], value: Int) -> Int:
    return callback(value, value)

def invoke_empty(callback: Callable[[], Int], value: Int) -> Int:
    return callback() + value

def first[T](left: T, right: T) -> T:
    return left

type Pair:
    left: Int
    right: Int

impl Pair:
    def combine(left: Int, right: Int) -> Int:
        return self.left + left + right

def use(right: Int, left: Int, pair: Pair, callback: Callable[[Int, Int], Int]) -> Int:
    return combine(1, 2)
