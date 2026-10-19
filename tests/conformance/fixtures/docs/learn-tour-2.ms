# conform: tags=interpolation,modules,mutation,stdlib-testing,testing,tier-core,try-result
# conform: phase=test
# conform: origin=documentation/learn/tour.md:31
import expect_equal from "@std/testing.ms"

test "unread message count":
    let customer = "Sam"
    var unread = 2
    unread += 1
    let message = "{customer}, you have {unread} unread messages."
    let enabled: Bool = true
    try expect_equal(enabled, true)
    try expect_equal(message, "Sam, you have 3 unread messages.")
