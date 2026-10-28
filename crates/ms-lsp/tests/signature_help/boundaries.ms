fn combine(left: Int, right: Int) Int:
    return left + right

fn defaults(left: Int = 1, right: Int = 2) Int:
    return left + right

fn collections(items: List[Int], lookup: Map[String, Int]) Int:
    return 0

fn invoke(callback: fn(Int, Int) Int, value: Int) Int:
    return callback(value, value)

fn invoke_empty(callback: fn() Int, value: Int) Int:
    return callback() + value

fn first[T](left: T, right: T) T:
    return left

type Pair:
    left: Int
    right: Int

impl Pair:
    fn combine(left: Int, right: Int) Int:
        return self.left + left + right

fn use(right: Int, left: Int, pair: Pair, callback: fn(Int, Int) Int) Int:
    return combine(1, 2)
