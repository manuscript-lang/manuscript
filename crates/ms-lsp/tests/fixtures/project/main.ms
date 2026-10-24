from "./util.ms" import double, Counter
from "./helper.ms" import helper

def main() -> Int:
    let counter = Counter(count: 1)
    let value = double(counter.count)
    return helper(value)
