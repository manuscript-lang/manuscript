import expect_ok from "@std/test/test.ms"
import connect, listen from "@std/net/net.ms"
import sleep from "@std/os/time.ms"

# A write to a peer that has gone away must return an error. Without SIGPIPE ignored the
# whole process dies with the signal instead.
test "writing to a closed connection returns an error":
    let listener = listen("127.0.0.1:0") | try expect_ok
    var client = connect(listener.address(), 2.seconds) | try expect_ok
    let accepted = listener.accept(2.seconds) | try expect_ok
    try client.close()

    var attempts = 0

    while attempts < 200:
        sleep(10.milliseconds)

        let written = accepted.write("ping", 1.seconds)

        if let _sent = written:
            attempts += 0
        else:
            return ok(unit)

        attempts += 1

    return error(Error("writes to a closed peer never failed"))
