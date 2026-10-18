import {expect_true} from "@std/testing.ms"
import {stdout} from "@std/io.ms"
import {clock} from "@std/time.ms"

type Boom:
    code: Int

impl Error for Boom:
    fn message() String: "boom {self.code}"

fn describe(e: Error) String: e.message()

test "repeated calls through one site":
    let c = clock()
    var i = 0

    while i < 3:
        let a = c.now()
        let b = c.now()
        try expect_true((b.difference(other: a).to_milliseconds() >= 0))
        i = i + 1

    let out = stdout()
    var n = 0

    while n < 2:
        try expect_true((out.write(data: "x").is_ok()))
        n = n + 1

    try expect_true((describe(e: Error(value: Boom(code: 1))) == "boom 1"))
    try expect_true((describe(e: Error(value: Boom(code: 2))) == "boom 2"))
