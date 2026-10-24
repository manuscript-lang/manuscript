# conform: tags=diagnostics,interfaces,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/cleanup/closeable.md:10
interface Closeable:
    def close() -> Unit
