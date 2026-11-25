// conform: tags=diagnostics,formatter,interfaces,tier-core
// conform: phase=check,parse
// conform: origin=documentation/core-language/cleanup/closeable.md:10
interface Closeable {
	fn close() Void
}
// expect-exit: 0
