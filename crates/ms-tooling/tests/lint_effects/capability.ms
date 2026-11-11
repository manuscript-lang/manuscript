interface Logger:
    fn info(msg: String) Unit

type ConsoleLogger:
    prefix: String

fn ConsoleLogger.info(msg: String) Unit:
    print(msg)

fn price(log: Logger, n: Int) Int:
    log.info("pricing")
    return n * 2

fn wire() Int:
    return price(ConsoleLogger("x"), 3)

export fn main() Int:
    return price(ConsoleLogger("x"), 1)
