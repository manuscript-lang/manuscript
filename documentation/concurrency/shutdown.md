+++
title = "Shutdown on SIGINT and SIGTERM"
weight = 8
+++

# Shutdown on SIGINT and SIGTERM

Put shutdown work in a `Closeable.close()` registered by `with`. The native application host requests cancellation on SIGINT or SIGTERM, unwinds registered scopes, and waits for cleanup and joined work. `ms run` forwards those signals and waits for the native application. Successful cleanup still exits 130 for SIGINT or 143 for SIGTERM.

## Observing a signal does not claim it

`control().watch_signals()` creates an observer. It does not acknowledge, claim, or suppress host cancellation. `SignalStream.next()` is cancellable; cancellation unwinds instead of returning a `ProcessError`. Signal delivery and host cancellation run independently. `next()` can deliver before cancellation reaches it, but code following that delivery has no protected interval in which to finish.

Save this example as `observe.ms`, build it with `ms build observe.ms -o observe`, and send SIGTERM to that disposable program after it prints `waiting`:

<!-- manuscript-example: {"mode":"signal","name":"observer"} -->
```manuscript
import List from "@std/collections.ms"
import stdout from "@std/io.ms"
import control from "@std/process.ms"
import sleep from "@std/time.ms"

export fn main() -> Int:
    match control().watch_signals(signals: [2, 15]):
        error(_):
            return 1
        ok(signals):
            with signals = signals:
                stdout().write(data: "waiting\n".to_bytes())
                let observed = signals.next()
                stdout().write(data: "got signal\n".to_bytes())
                sleep(duration: 100.milliseconds)
                stdout().write(data: "after sleep\n".to_bytes())
                return 0
```

```sh
./observe > observe.log &
pid=$!
# Wait until observe.log contains "waiting", then:
kill -TERM "$pid"
wait "$pid"   # status 143
cat observe.log
```

`got signal` may appear or be skipped. `sleep`, writes, locks, and other cancellation checkpoints can unwind before the next statement runs. Neither observing the signal nor returning a normal status overrides cancellation once the host accepts it. Do not use the code after `next()` as a shutdown callback. Observers are useful for signals that the host does not treat as stop requests, subject to platform support and lossy OS delivery.

## Close the server under the cleanup shield

Registered cleanup ignores the cancellation that initiated unwinding. Calls made directly from `close()` use that shield too: they may suspend, acquire a lock, or perform bounded socket I/O. Here “synchronous shutdown” means doing and finishing the work in the close call, not requiring nonblocking operations.

The shield does not change existing workers' execution parents. Workers in a `TaskGroup` constructed under `main` are cancelled with `main`; they may already have stopped when server cleanup starts. `TaskGroup.close()` cancels unfinished workers and joins their cleanup. It does not drain their ordinary bodies. Likewise, a Scheduler's drain setting cannot revive work cancelled through its construction parent.

This deliberately small server accepts one client. It registers dependencies outside the server scope, joins its worker before using the connection for shutdown, writes the farewell directly from `close()`, and closes the connection. The worker's own `with` cleanup prints `worker stopped`; its ordinary farewell after the long sleep is abandoned on cancellation.

Save as `shutdown.ms` and run `ms build shutdown.ms -o shutdown`:

<!-- manuscript-example: {"mode":"signal","name":"server"} -->
```manuscript
import Closeable from "@std/cleanup.ms"
import List from "@std/collections.ms"
import stdout from "@std/io.ms"
import {network, Listener, Connection} from "@std/net.ms"
import control from "@std/process.ms"
import {TaskGroup, check_cancelled} from "@std/tasks.ms"
import sleep from "@std/time.ms"

type WorkerCleanup:
    label: String

impl Closeable for WorkerCleanup:
    fn close() -> Unit:
        stdout().write(data: "{self.label} stopped\n".to_bytes())

type Server:
    listener: Listener
    client: Connection
    workers: TaskGroup
    closed: Bool = false

impl Closeable for Server:
    fn close() -> Unit:
        if self.closed:
            return
        self.closed = true
        self.listener.close()
        self.workers.close()
        check_cancelled()
        sleep(duration: 10.milliseconds)
        match self.client.write(data: "farewell\n".to_bytes(), timeout: 1.seconds):
            ok(_):
                stdout().write(data: "farewell sent\n".to_bytes())
            error(cause):
                stdout().write(data: "farewell failed: {cause.message()}\n".to_bytes())
        self.client.close()

fn serve() -> Result[Unit, Error]:
    with signals = try control().watch_signals(signals: [2, 15]):
        with listener = try network().listen(address: "127.0.0.1:0"):
            stdout().write(data: "{listener.address()}\n".to_bytes())
            with client = try listener.accept():
                with workers = TaskGroup():
                    with server = Server(listener: listener, client: client, workers: workers):
                        workers.start(fn():
                            with cleanup = WorkerCleanup(label: "worker"):
                                stdout().write(data: "ready\n".to_bytes())
                                sleep(duration: 3600.seconds)
                                client.write(data: "worker farewell\n".to_bytes())
                                return unit
                        )
                        let observed = signals.next()
                        return ok(unit)

export fn main() -> Int:
    match serve():
        ok(_):
            return 0
        error(cause):
            stdout().write(data: "{cause.message()}\n".to_bytes())
            return 1
```

Start `./shutdown`, connect a TCP client to the printed loopback address (for example `nc 127.0.0.1 <port>`), and wait for `ready`. From another terminal send `kill -TERM <shutdown-pid>`. The client receives `farewell` and then EOF; the server prints `worker stopped` followed by `farewell sent` and exits 143. SIGINT gives the same cleanup with status 130. The repository integration test executes these exact code fences for both signals, directly and through `ms run`.

For several clients or queued messages, keep pending data in application-owned state, stop admission, join workers, and drain the remaining data directly in `close()` while sockets are still open. Protect shared state with one `Synchronized` wrapper and ensure workers release its guards during cleanup. Never hold a guard while joining a worker that needs the same guard. A reference captured by a worker does not keep an outer resource scope open.

## Limits

- The server example is for POSIX SIGINT/SIGTERM. Windows forced termination through `send_signal` does not provide this graceful path. SIGKILL, process crashes, and external forced termination bypass cleanup.
- A successful socket write means bytes were accepted by the transport, not that the peer processed them. Peer disconnects and write timeouts remain possible. This example reports an expected farewell error and still closes the socket; an application needing delivery acknowledgement must implement and bound that protocol explicitly.
- Automatic `close()` returns `Unit`. Handle expected flush failures inside it, or expose a separate Result-returning `finish()` for ordinary operation. An explicit `server.close()` call in already-cancelled ordinary code is itself cancellable; the shield here comes from registered `with` cleanup.
- Shielding is not a time limit. Bound shutdown I/O explicitly. Joining uncooperative work can still wait indefinitely. The current native `RunMain` has no cleanup watchdog or second-signal escalation; do not rely on the host-escalation policy described for runtime implementers as an implemented CLI deadline.
- There is no signal-claiming API, public cancellation catch/shield block, or reparenting API that lets existing workers continue their normal bodies after host cancellation. A helper with that guarantee requires a separate lifetime/API decision. The cookbook preserves the existing observation and lifetime rules.

See [cancellation checkpoints](cancellation.md#propagation-and-checkpoints), [cleanup order](../core-language/cleanup/exit-order.md), and [process signals](../standard-library/process.md#signals).
