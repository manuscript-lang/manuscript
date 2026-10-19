# conform: tags=formatter,interfaces,parser,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/cleanup/closeable.md:10
interface Closeable:
    fn close() Unit
