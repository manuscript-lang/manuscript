import double, Counter from "./util.ms"
import helper from "./helper.ms"

fn main() Int:
    counter := Counter(count: 1)
    value := double(counter.count)
    return helper(value)
