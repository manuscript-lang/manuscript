import {new_counter} from "./counter.ms"

fn main() -> Unit:
    let counter = new_counter(1).unwrap()
    counter.count = -1
