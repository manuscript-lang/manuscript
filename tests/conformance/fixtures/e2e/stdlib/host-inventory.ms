# conform: tags=control-flow,stdlib-system,stdlib-testing,testing,tier-io,try-result
# conform: phase=test
import {expect_equal, expect_false, expect_true} from "@std/testing.ms"
import {system} from "@std/process.ms"
import IpFamily from "@std/net.ms"

test "network interfaces describe each address and include a loopback":
    let found = system().network_interfaces()

    if let items = found:
        var loopback = false

        for item in items:
            try expect_false(item.name.byte_length() == 0)
            try expect_false(item.address.byte_length() == 0)
            try expect_false(item.netmask.byte_length() == 0)
            try expect_true(item.scope_id > 0)
            try expect_equal(item.family == IpFamily.IPv6, item.address.contains(":"))

            if item.internal:
                loopback = true
                try expect_equal(item.mac, "")

        try expect_true(loopback)

test "cpus report non-negative cumulative times":
    let found = system().cpus()

    if let cpus = found:
        try expect_false(cpus.is_empty())

        for cpu in cpus:
            try expect_true(cpu.speed_mhz >= 0)
            try expect_true(cpu.user >= 0 and cpu.nice >= 0)
            try expect_true(cpu.system >= 0 and cpu.idle >= 0 and cpu.irq >= 0)

test "metrics report memory, uptime, load averages and parallelism":
    let found = system().metrics()

    if let m = found:
        try expect_true(m.total_memory > 0)
        try expect_true(m.free_memory <= m.total_memory)
        try expect_true(m.available_memory <= m.total_memory)
        try expect_true(m.uptime.to_nanoseconds() > 0)
        try expect_equal(m.load_average.length(), 3)
        for load in m.load_average:
            try expect_true(load >= 0.0)
        try expect_true(m.available_parallelism >= 1)
