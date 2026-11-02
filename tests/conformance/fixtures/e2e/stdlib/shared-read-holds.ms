# conform: tags=interfaces,stdlib-shared,stdlib-tasks,tier-io
# conform: phase=run
# conform: timeout=20
import stdout from "@std/io/io.ms"
import Shared from "@std/concurrency/shared.ms"
import TaskGroup from "@std/concurrency/tasks.ms"
import milliseconds, sleep from "@std/os/time.ms"

interface Namer:
    fn slow_name() String

# Long names live on the heap, so a payload replaced under a reader would be freed.
type Notes:
    names: List[String]

impl Notes:
    fn slow_first() String:
        sleep(milliseconds(50))
        return self.names[0]

impl Namer for Notes:
    fn slow_name() String:
        sleep(milliseconds(50))
        return self.names[0].clone()

type Box:
    namer: Namer

interface Sink:
    var fn put(name: String) Unit

impl Sink for Notes:
    var fn put(name: String) Unit:
        self.names.append(name)

# Changes its payload only through an interface field: still a change, so it waits for readers.
type Relay:
    sink: Sink

impl Relay:
    var fn send(name: String) Unit:
        self.sink.put(name)

fn slow_relay(relay: Relay) String:
    sleep(milliseconds(50))
    return "relay read"

fn say(text: String) Unit:
    let _ = stdout().write(text + "\n")

fn slow(notes: Notes) String:
    sleep(milliseconds(50))
    return notes.names[0]

fn first_names(notes: Notes) List[String]:
    return notes.names

fn timed(label: String, notes: Notes) Unit:
    say("start " + label)
    sleep(milliseconds(50))
    say("end " + label + " " + notes.names[0])

fn notes(name: String) Notes:
    return Notes([name + "-a-name-long-enough-for-the-heap"])

# A read call parks; a change from another task waits until the read ends.
export fn main() Int:
    var plain = Shared(notes("old"))
    let by_function = plain
    var plain_writer = plain
    var functions = TaskGroup[Int]()
    functions.spawn(fn var ch:
        say("function read " + slow(by_function))
        return 0
    )
    functions.spawn(fn var ch:
        sleep(milliseconds(10))
        plain_writer = notes("new")
        say("function written")
        return 0
    )
    let _ = functions.results()
    functions.close().get(none)

    let by_method = plain
    var methods = TaskGroup[Int]()
    methods.spawn(fn var ch:
        say("method read " + by_method.slow_first())
        return 0
    )
    methods.spawn(fn var ch:
        sleep(milliseconds(10))
        plain_writer = notes("newer")
        say("method written")
        return 0
    )
    let _ = methods.results()
    methods.close().get(none)

    var boxed = Shared(Box(notes("old")))
    let reader = boxed
    var writer = boxed
    var group = TaskGroup[Int]()
    group.spawn(fn var ch:
        say("interface read " + reader.namer.slow_name())
        return 0
    )
    group.spawn(fn var ch:
        sleep(milliseconds(10))
        writer = Box(notes("new"))
        say("interface written")
        return 0
    )
    let _ = group.results()
    group.close().get(none)

    # A lent result through a handle is a copy: the change does not wait for it.
    var shared = Shared(notes("old"))
    let held = shared
    var changer = shared
    var lent = TaskGroup[Int]()
    lent.spawn(fn var ch:
        let names = first_names(held)
        sleep(milliseconds(50))
        say("lent read " + names[0])
        return 0
    )
    lent.spawn(fn var ch:
        sleep(milliseconds(10))
        changer = notes("new")
        say("lent written")
        return 0
    )
    let _ = lent.results()
    lent.close().get(none)

    # Reads share the value: both start before either ends.
    let first = shared
    let second = shared
    var readers = TaskGroup[Int]()
    readers.spawn(fn var ch:
        timed("first", first)
        return 0
    )
    readers.spawn(fn var ch:
        timed("second", second)
        return 0
    )
    let _ = readers.results()
    readers.close().get(none)

    var relay = Shared(Relay(notes("old")))
    let relay_reader = relay
    var relay_writer = relay
    var relays = TaskGroup[Int]()
    relays.spawn(fn var ch:
        say(slow_relay(relay_reader))
        return 0
    )
    relays.spawn(fn var ch:
        sleep(milliseconds(10))
        relay_writer.send("more")
        say("relay written")
        return 0
    )
    let _ = relays.results()
    relays.close().get(none)

    # A reader cancelled while parked inside its read lets the value change.
    let parked = shared
    var cancelled = TaskGroup[Int](timeout: milliseconds(20))
    cancelled.spawn(fn var ch:
        let _ = slow(parked)
        sleep(milliseconds(60000))
        return 0
    )
    let _ = cancelled.wait()
    cancelled.close().get(none)
    shared = notes("after-cancel")
    say("changed " + shared.names[0])
    return 0
