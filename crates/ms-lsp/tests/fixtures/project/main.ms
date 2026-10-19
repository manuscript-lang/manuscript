import {double, Counter} from "./util.ms"
import helper from "./helper.ms"

fn main() Int:
    let counter = Counter(count: 1)
    let value = double(counter.count)
    return helper(value)
