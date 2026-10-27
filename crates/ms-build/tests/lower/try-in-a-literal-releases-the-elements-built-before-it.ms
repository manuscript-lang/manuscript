# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
from "@std/core.ms" import TextError

def bad() -> Result[String, Error]:
    return error(TextError("no"))

def list() -> Result[Int, Error]:
    let xs = ["a", try bad(), "c"]
    return ok(xs.length())

def nested() -> Result[Int, Error]:
    let xs = [["a"], ["b", try bad()]]
    return ok(xs.length())

def map_value() -> Result[Int, Error]:
    let m = {"a": "x", "b": try bad()}
    return ok(m.length())

def map_key() -> Result[Int, Error]:
    let m = {"a": "x", (try bad()): "y"}
    return ok(m.length())

export def main() -> Int:
    let _a = list()
    let _b = nested()
    let _c = map_value()
    let _d = map_key()
    return 0
