// conform: tags=control-flow,diagnostics,faults,interfaces,modules,mutation,optional,records,stdlib-bytes,stdlib-io,strings,tier-stdlib,try-result
// conform: phase=check
// conform: origin=tests/e2e/testdata/stdlib/support/streams.ms
import ReadStream, Source, stream from "@std/io/io.ms"
import from_bytes from "@std/io/streams.ms"
import Bytes from "@std/bytes.ms"

// A reader over `text` in chunks of `chunk` bytes, so line and scalar boundaries fall inside reads.
export fn memory(text: String, chunk: Int = 3) ReadStream[Bytes]:
    return from_bytes(text.to_bytes(), chunk)

// A reader whose every read fails with `Closed`, like a stream that was closed under its reader.
type ClosedSource:
    unused: Int

impl Source[Bytes] for ClosedSource:
    var fn next() Bytes?!:
        return error(Error("I/O: resource is closed", kind: ErrorCategory.Closed))

    var fn close() Unit!:
        return ok(unit)

export fn closed_reader() ReadStream[Bytes]:
    return stream[Bytes](ClosedSource(0))
