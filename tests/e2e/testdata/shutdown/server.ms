import Closeable from "@std/cleanup.ms"
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
