import (
    Closeable, panic from "@std/core.ms",
    append_file, read_file, temporary from "@std/os/fs.ms",
    expect_equal, expect_contains, expect_fault from "@std/test/test.ms",
)

type Door:
    id: Int
    log: String
    closed: Bool = false
    fail: Bool = false

impl Closeable for Door:
    var fn close() Unit!:
        if not self.closed:
            self.closed = true
            try append_file(self.log, "{self.id},").wait()
            if self.fail: return error(Error("close failed"))

fn events(log: String) String!:
    return ok((try read_file(log).wait()).decode_utf8().get(""))

fn named(log: String, op: Int, index: Int, fail: Bool = false) Unit:
    var items = [Door(1, log.clone(), fail: fail)]

    if op == 0: items.set(index, Door(2, log))
    else if op == 1: items.insert(index, Door(2, log))
    else if op == 2:
        let _old = items.replace(index, Door(2, log))
    else if op == 3: items.append(Door(2, log))
    else: items.prepend(Door(2, log))

fn computed(log: String, op: Int, index: Int, fail: Bool = false) Unit:
    if op == 0: [Door(1, log.clone(), fail: fail)].set(index, Door(2, log))
    else if op == 1: [Door(1, log.clone(), fail: fail)].insert(index, Door(2, log))
    else if op == 2:
        let _old = [Door(1, log.clone(), fail: fail)].replace(index, Door(2, log))
    else if op == 3: [Door(1, log.clone(), fail: fail)].append(Door(2, log))
    else: [Door(1, log.clone(), fail: fail)].prepend(Door(2, log))

test "named and computed bad bounds close incoming before existing":
    for op in 0..3:
        for index in [-2, 2]:
            let tmp = try temporary("list-transfer-")
            let log = "{tmp.path()}/log"
            try expect_contains(
                (try expect_fault(fn: named(log.clone(), op, index))), "index"
            )
            try expect_equal((try events(log)), "2,1,")

            let temp = try temporary("list-computed-transfer-")
            let other = "{temp.path()}/log"
            try expect_contains(
                (
                    try expect_fault(
                        fn: computed(other.clone(), op, index)
                    )
                ),
                "index"
            )
            try expect_equal((try events(other)), "2,1,")

test "successful direct and computed transfers close each owner once":
    for op in 0..5:
        let tmp = try temporary("list-transfer-ok-")
        let log = "{tmp.path()}/log"
        named(log.clone(), op, 0)

        let expected = if op == 3: "2,1," else: "1,2,"
        try expect_equal((try events(log)), expected)

        let temp = try temporary("list-computed-ok-")
        let other = "{temp.path()}/log"
        computed(other.clone(), op, 0)

        let computed_expected = if op == 2 or op == 3: "2,1," else: "1,2,"
        try expect_equal((try events(other)), computed_expected)

fn later_fault(log: String) Unit:
    var items = [Door(1, log.clone())]
    items.set(value: Door(2, log), index: panic("later operand"))

fn bad_index() Int!:
    return error(Error("index failed"))

fn later_try(log: String) Unit!:
    var items = [Door(1, log.clone())]
    items.set(value: Door(2, log), index: try bad_index())

test "later named operand faults and try exits preserve incoming owner":
    let tmp = try temporary("list-later-fault-")
    let log = "{tmp.path()}/log"
    try expect_contains(
        (try expect_fault(fn: later_fault(log.clone()))), "later operand"
    )
    try expect_equal((try events(log)), "2,1,")

    let temp = try temporary("list-later-try-")
    let other = "{temp.path()}/log"
    try expect_equal(later_try(other.clone()).is_error(), true)
    try expect_equal((try events(other)), "2,1,")

test "failed old close preserves pending incoming owner":
    let tmp = try temporary("list-old-close-")
    let log = "{tmp.path()}/log"
    let message = try expect_fault(fn: named(log.clone(), 0, 0, true))
    try expect_contains(message, "closed")
    try expect_equal((try events(log)), "1,2,")

    let temp = try temporary("list-computed-old-close-")
    let other = "{temp.path()}/log"
    let error = try expect_fault(fn: computed(other.clone(), 0, 0, true))
    try expect_contains(error, "closed")
    try expect_equal((try events(other)), "1,2,")

type Holder:
    items: List[Door]

fn field(log: String) Unit:
    var holder = Holder([Door(1, log.clone())])
    holder.items.set(3, Door(2, log))

fn slot(log: String) Unit:
    var items = [Door(1, log.clone())]
    let action = fn(index: Int): items.set(index, Door(2, log.clone()))
    action(3)

test "field and closure-slot receivers retain cleanup on fault":
    let tmp = try temporary("list-field-")
    let log = "{tmp.path()}/log"
    try expect_contains((try expect_fault(fn: field(log.clone()))), "index")
    try expect_equal((try events(log)), "2,1,")

    let temp = try temporary("list-slot-")
    let other = "{temp.path()}/log"
    try expect_contains((try expect_fault(fn: slot(other))), "index")
    try expect_equal((try events(other)), "2,1,")

fn optional(log: String, index: Int) Unit:
    var items: List[Door?] = [Door(1, log.clone())]
    items.set(index, Door(2, log))

fn computed_failed_new_close(log: String) Unit:
    let _old = [Door(1, log.clone())].replace(0, Door(2, log, fail: true))

test "implicit optional payload and outgoing replacement survive cleanup faults":
    let tmp = try temporary("list-optional-")
    let log = "{tmp.path()}/log"
    try expect_contains((try expect_fault(fn: optional(log.clone(), 3))), "index")
    try expect_equal((try events(log)), "2,1,")

    let temp = try temporary("list-replace-new-close-")
    let other = "{temp.path()}/log"
    let message = try expect_fault(fn: computed_failed_new_close(other.clone()))
    try expect_contains(message, "closed")
    try expect_equal((try events(other)), "2,1,")

fn repeated(log: String) Unit:
    var items: List[Door] = []
    for id in 0..40:
        items.append(Door(id, log.clone()))
    for id in 0..40:
        let _old = items.replace(id, Door(id + 40, log.clone()))

test "repeated successful transfers retire only their own cleanup":
    let tmp = try temporary("list-repeated-")
    let log = "{tmp.path()}/log"
    repeated(log)

    var expected = ""
    for id in 0..40: expected = "{expected}{id},"
    for id in 0..40: expected = "{expected}{79 - id},"
    try expect_equal((try events(log)), expected)

type PanicDoor:
    id: Int
    log: String
    fail: Bool
    closed: Bool = false

impl Closeable for PanicDoor:
    var fn close() Unit!:
        if not self.closed:
            self.closed = true
            try append_file(self.log, "{self.id},").wait()
            if self.fail: panic("capture close panic")

fn captured(log: String, id: Int, fail: Bool) fn() Int:
    let door = PanicDoor(id, log, fail)
    return fn: door.id

type Envelope:
    id: Int
    log: String
    callback: fn() Int
    closed: Bool = false

impl Closeable for Envelope:
    var fn close() Unit!:
        if not self.closed:
            self.closed = true
            try append_file(self.log, "{self.id},").wait()

fn callback_drop(log: String) Unit:
    var items = [Envelope(1, log.clone(), captured(log.clone(), 3, true))]
    items.set(0, Envelope(2, log, fn: 4))

test "faulting captured close during detached old drop preserves new list owner":
    let tmp = try temporary("list-callback-drop-")
    let log = "{tmp.path()}/log"
    let message = try expect_fault(fn: callback_drop(log.clone()))
    try expect_contains(message, "capture close panic")
    try expect_equal((try events(log)), "1,3,2,")

type EnvelopeHolder:
    items: List[Envelope]

fn callback_places(log: String, kind: Int) Unit:
    if kind == 0:
        var holder = EnvelopeHolder(
            [Envelope(1, log.clone(), captured(log.clone(), 3, true))]
        )
        holder.items.set(0, Envelope(2, log, fn: 4))
    else if kind == 1:
        var groups = [[Envelope(1, log.clone(), captured(log.clone(), 3, true))]]
        groups[0].set(0, Envelope(2, log, fn: 4))
    else if kind == 2:
        var items = [Envelope(1, log.clone(), captured(log.clone(), 3, true))]
        let action = fn: items.set(0, Envelope(2, log.clone(), fn: 4))
        action()
    else:
        [Envelope(1, log.clone(), captured(log.clone(), 3, true))].set(
            0, Envelope(2, log, fn: 4)
        )

test "old capture drop fault observes updated field indexed slot and computed receivers":
    for kind in 0..4:
        let tmp = try temporary("list-place-callback-")
        let log = "{tmp.path()}/log"
        let message = try expect_fault(fn: callback_places(log.clone(), kind))
        try expect_contains(message, "capture close panic")
        try expect_equal((try events(log)), "1,3,2,")

fn owned_named(log: String, index: Int) Unit:
    var items = [Door(1, log.clone())]
    let next = Door(2, log)
    items.insert(index, next)

fn valid_later() Int!: return ok(0)

fn succeeding_try(log: String) Unit!:
    var items = [Door(1, log.clone())]
    items.set(value: Door(2, log), index: try valid_later())

test "valid negative end and named owner transfers preserve single close":
    for op in [0, 1, 2]:
        let tmp = try temporary("list-negative-ok-")
        let log = "{tmp.path()}/log"
        named(log.clone(), op, -1)
        try expect_equal((try events(log)), "1,2,")

    let tmp = try temporary("list-end-ok-")
    let log = "{tmp.path()}/log"
    owned_named(log.clone(), 1)
    try expect_equal((try events(log)), "2,1,")

    let temp = try temporary("list-named-fault-")
    let other = "{temp.path()}/log"
    try expect_contains((try expect_fault(fn: owned_named(other.clone(), 2))), "index")
    try expect_equal((try events(other)), "2,1,")

    let success = try temporary("list-success-try-")
    let path = "{success.path()}/log"
    try succeeding_try(path.clone())
    try expect_equal((try events(path)), "1,2,")

fn after_pop(var items: List[Door]) Int:
    let _removed = items.pop()
    return 0

fn changed_length(log: String) Unit:
    var items = [Door(1, log.clone())]
    items.set(value: Door(2, log), index: after_pop(var items))

test "final bounds use receiver after later operand mutation":
    let tmp = try temporary("list-current-bounds-")
    let log = "{tmp.path()}/log"
    try expect_contains((try expect_fault(fn: changed_length(log.clone()))), "index")
    try expect_equal((try events(log)), "1,2,")

fn optional_list(log: String) List[Door?]:
    return [Door(1, log)]

fn computed_absent(log: String) Unit:
    optional_list(log).set(0, none)

fn computed_arg_fault(log: String) Unit:
    optional_list(log).append(panic("incoming failed"))

test "computed receiver closes when payload absent or construction faults":
    let tmp = try temporary("list-absent-")
    let log = "{tmp.path()}/log"
    computed_absent(log.clone())
    try expect_equal((try events(log)), "1,")

    let temp = try temporary("list-arg-fault-")
    let other = "{temp.path()}/log"
    try expect_contains(
        (try expect_fault(fn: computed_arg_fault(other.clone()))), "incoming failed"
    )
    try expect_equal((try events(other)), "1,")
