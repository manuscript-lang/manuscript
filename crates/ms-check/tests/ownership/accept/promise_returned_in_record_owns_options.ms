import Promise, promise from "@std/concurrency/promise.ms"

type Options:
    count: Int

type Server:
    running: Promise[Int]

fn count_of(options: Options) Int!:
    return ok(options.count)

fn serve(options: Options) Server:
    return Server(running: promise(fn: count_of(options)))
