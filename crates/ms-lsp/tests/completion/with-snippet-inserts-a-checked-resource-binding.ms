from "@std/core.ms" import Closeable

type Resource:
    value: Int

impl Closeable for Resource:
    var def close() -> Unit: return ()

def main() -> Unit:
    wi
