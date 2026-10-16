export interface Counter:
    fn value() -> Int
    fn increment() -> Unit

type CounterState:
    count: Int

impl Counter for CounterState:
    fn value() -> Int:
        return self.count
    fn increment() -> Unit:
        self.count = self.count + 1

export fn new_counter(start: Int) -> Result[Counter, String]:
    if start < 0:
        return error("start must be nonnegative")
    let state = Counter(value: CounterState(count: start))
    return ok(state)
