# conform: tags=aliasing,closures,control-flow,interfaces,interpolation,lists,match,modules,mutation,records,stdlib-collections,stdlib-testing,strings,testing,tier-stdlib,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/list-equality-mutation.ms
from "@std/testing.ms" import fail
from "@std/collections.ms" import range

type Element:
    id: Int
    on_equal: Callable[[], Unit]

impl Equal for Element:
    def equals(other: Element) -> Bool:
        self.on_equal()

        return self.id == other.id

type Visits:
    count: Int

def noop() -> Unit:
    return

def check_equality(side: String, mutation: String) -> Result[Unit, Error]:
    var left: List[Element] = []
    var right: List[Element] = []
    let calls = Visits(0)

    let visit = lambda:
        calls.count = calls.count + 1
        if calls.count != 1:
            return

        var target = left
        if side == "right":
            target = right

        let next_action = target[1].on_equal

        if mutation == "shrink" or mutation == "shrink_mismatch":
            target.splice(0, target.length(), [])
            return

        if mutation == "append":
            target.append(Element(7, noop))
            return

        if mutation == "append_write":
            target.append(Element(7, noop))
            target.set(1, Element(77, next_action))
            return

        if mutation == "grow_write":
            for index in range(0, 100):
                target.append(Element(7, noop))
            target.set(1, Element(77, next_action))
            return

        target.set(1, Element(77, next_action))

    for id in [1, 2, 3]:
        left.append(Element(id, visit))
        right.append(Element(id, visit))

    if mutation == "shrink_mismatch":
        right.set(2, Element(99, visit))

    let expected = (
        mutation != "shrink_mismatch"
        and mutation != "append_write"
        and mutation != "overwrite"
    )
    var expected_calls = 3
    if mutation == "append_write" or mutation == "overwrite":
        expected_calls = 2

    let same = left == right
    if same != expected or calls.count != expected_calls: return fail(
        f"{side}/{mutation}: equality {same}/{calls.count}, expected {expected}/{expected_calls}"
    )

    return ok(())

test "element Equal mutating either List retains both captured headers":
    for side in ["left", "right"]:
        for mutation in [
            "shrink", "shrink_mismatch", "append", "append_write", "grow_write",
            "overwrite"
        ]:
            (try check_equality(side, mutation))
