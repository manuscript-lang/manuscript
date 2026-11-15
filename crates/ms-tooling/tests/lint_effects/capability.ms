interface Logger:
    fn info(msg: String) Void

type ConsoleLogger:
    prefix: String

fn ConsoleLogger.info(msg: String) Void:
    print(msg)

fn price(log: Logger, n: Int) Int:
    log.info("pricing")
    return n * 2

fn wire() Int:
    return price(ConsoleLogger("x"), 3)

export fn main() Int:
    return price(ConsoleLogger("x"), 1)
