import Shared from "@std/concurrency/shared.ms"

type Counter:
    values: List[Int]

impl Counter:
    var fn bump() Unit:
        self.values.append(1)

    fn count_after(after: fn() Unit) Int:
        after()
        return self.values.length()

type Holder:
    counter: Shared[Counter]

fn through_alias() Int:
    var shared = Shared(Counter([]))
    var other = shared
    return shared.count_after(fn() Unit: other.bump())  # error: this callback changes

fn through_record(var holder: Holder) Int:
    var shared = Shared(Counter([]))
    return shared.count_after(fn() Unit: holder.counter.bump())  # error: this callback changes
