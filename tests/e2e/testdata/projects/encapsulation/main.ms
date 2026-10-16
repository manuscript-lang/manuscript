import {Counter, new_counter} from "./counter.ms"
import expect_equal from "@std/testing.ms"

test "clients use only the exported operations":
    let counter = new_counter(1).unwrap()
    counter.increment()
    expect_equal(counter.value(), 2)

test "the factory rejects invalid state":
    expect_equal(new_counter(-1).is_ok(), false)
