# conform: tags=formatter,interpolation,modules,mutation,parser,stdlib-testing,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=documentation/learn/tour.md:31
from "@std/testing.ms" import expect_equal

test "unread message count":
    let customer = "Sam"
    var unread = 2
    unread += 1

    let message = f"{customer}, you have {unread} unread messages."
    let enabled: Bool = True
    try expect_equal(enabled, True)
    try expect_equal(message, "Sam, you have 3 unread messages.")
