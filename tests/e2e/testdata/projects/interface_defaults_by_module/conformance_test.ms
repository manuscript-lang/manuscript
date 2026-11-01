import expect_equal from "@std/test/test.ms"
import Echo from "./first.ms"
import Quiet from "./second.ms"

# Both types implement `Commands` with the same methods; `first.ms` is padded so its node
# ids differ from `second.ms`, and each omitted argument must still take `Commands.run`'s default.
test "an omitted argument takes the default of its own operation":
    let echoed = Echo(3).run("fake", []) | try
    try expect_equal(echoed.exit_code, 3)
    try expect_equal(echoed.stdout.length(), 0)

    let quiet = Quiet(4).run("fake", []) | try
    try expect_equal(quiet.exit_code, 4)
