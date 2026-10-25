from "@std/sync.ms" import lock
from "@std/http.ms" import Request, HttpHeaders, headers
from "@std/io.ms" import ReadStream, IoError
from "@std/bytes.ms" import Bytes
from "@std/shared.ms" import Shared, share
from "@std/core.ms" import Closeable

# Finite limits for streaming multipart/form-data, including skipped part bodies.
export type MultipartLimits:
    # Encoded body bytes including delimiters, headers, preamble and epilogue.
    max_bytes: Int = 33554432
    # Payload bytes per part.
    max_part_bytes: Int = 16777216
    # Maximum number of parts, including skipped form fields.
    max_parts: Int = 128
    # Header bytes per part, including CRLF separators.
    max_header_bytes: Int = 8192
    # Header fields per part.
    max_headers: Int = 32

# Metadata and a reader valid only during the multipart callback.
export type MultipartPart:
    # Required form field name; repeated names remain separate parts.
    name: String
    # Untrusted client filename; never use as a filesystem path.
    filename: Optional[String]
    # Validated headers preserving repeated values.
    headers: HttpHeaders
    # Scoped payload reader. Returning success drains unread bytes within all limits.
    body: ReadStream

type Parameters:
    kind: String
    values: Map[String, String]

# Strict MIME parameter parser, preserving quoted semicolons and escaped characters.
def parameters(text: String) -> Result[Parameters, IoError]:
    var pieces = List[String]()
    var piece = ""
    var quoted = False
    var escaped = False

    for char in text.chars():
        if escaped:
            piece += char
            escaped = False
            continue

        if char == "\\" and quoted:
            escaped = True
            piece += char
            continue

        if char == "\"": quoted = not quoted

        if char == ";" and not quoted:
            pieces.append(piece.trim().clone())
            piece = ""
        else: piece += char

    if quoted or escaped: return error(IoError.InvalidData)

    pieces.append(piece.trim().clone())

    var result = Parameters(pieces[0].lower(), Map[String, String]())

    for item in pieces.slice(1, pieces.length()).get():
        let split = item.index_of("=")
        if split.is_none(): return error(IoError.InvalidData)

        let key = item.take(split.get()).trim().lower()
        let raw = item.drop(split.get() + 1).trim()
        if key == "" or key.ends_with("*") or result.values.contains(key): return error(
            IoError.InvalidData
        )

        for char in key.chars():
            let code = char.scalar_values() [0]
            if code <= 32 or code >= 127 or "()<>@,;:\\\"/[]?=".contains(char): return error(
                IoError.InvalidData
            )

        var value = ""

        if raw.starts_with("\""):
            if raw.scalar_length() < 2 or not raw.ends_with("\""): return error(
                IoError.InvalidData
            )

            var escape = False

            for char in raw.slice(1, raw.scalar_length() - 1).get().chars():
                if escape:
                    value += char
                    escape = False
                elif char == "\\": escape = True
                elif char == "\"": return error(IoError.InvalidData)
                else: value += char

            if escape: return error(IoError.InvalidData)
        else:
            if raw == "": return error(IoError.InvalidData)

            for char in raw.chars():
                let code = char.scalar_values() [0]
                if code <= 32 or code >= 127 or "()<>@,;:\\\"/[]?=".contains(char): return error(
                    IoError.InvalidData
                )

            value = raw.clone()

        for code in value.scalar_values():
            if code < 32 or code == 127: return error(IoError.InvalidData)
        result.values.add(key, value)

    return ok(result)

type Scanner:
    input: Request
    pending: Bytes
    remaining: Int
    marker: Bytes
    part_remaining: Int
    eof: Bool = False
    ended: Bool = False
    final: Bool = False

type Held[T]:
    value: T

impl Closeable for Held[T]:
    var def close() -> Unit: ()

extern def msrt_shield_enter() -> Unit

extern def msrt_shield_exit() -> Unit

type Preparation:
    active: Bool = True

impl Closeable for Preparation:
    var def close() -> Unit: msrt_shield_exit()

type Step:
    case Wait
    case End
    case Data(bytes: Bytes)

# These transactions never call user code or wait. Cancellation is deferred until
# the updated scanner is back in its cleanup-owned shared slot.
def append_input(
    shared: Shared[Scanner],
    chunk: Optional[Bytes]
) -> Result[Unit, IoError]:
    msrt_shield_enter()

    with let preparation = Preparation():
        with var scanner_guard = lock(shared):
            if chunk.is_none():
                scanner_guard.value.eof = True
                return ok(())

            let bytes = chunk.get()
            if bytes.length() == 0:
                return error(IoError.InvalidData)
            if bytes.length() > 65536 or bytes.length() > scanner_guard.value.remaining:
                return error(IoError.LimitExceeded)

            scanner_guard.value.remaining -= bytes.length()
            scanner_guard.value.pending = scanner_guard.value.pending.concat(bytes)

        return ok(())

def fill(shared: Shared[Scanner]) -> Result[Unit, IoError]:
    if shared.get().eof: return error(IoError.InvalidData)

    with let chunk = Held(try shared.get().input.body.read(some(65536))):
        return append_input(shared, chunk.value)

impl Scanner:
    var def line_step(limit: Int) -> Result[Step, IoError]:
        let at = self.pending.index_of("\r\n".to_bytes())

        if at.is_some():
            if at.get() + 2 > limit: return error(IoError.LimitExceeded)

            let line = self.pending.slice(0, at.get()).get()
            self.pending = self.pending.slice(at.get() + 2, self.pending.length()).get()
            return ok(Step.Data(line))

        if self.pending.length() >= limit: return error(IoError.LimitExceeded)
        if self.eof: return error(IoError.InvalidData)

        return ok(Step.Wait)

    var def payload_step(wanted: Int) -> Result[Step, IoError]:
        if self.ended: return ok(Step.End)

        let found = self.pending.index_of(self.marker)
        var available = self.pending.length() - self.marker.length() - 4

        if found.is_some():
            let at = found.get()

            if at > 0: available = at
            else:
                let needed = self.marker.length() + 2

                if self.pending.length() < needed:
                    if self.eof: return error(IoError.InvalidData)

                    return ok(Step.Wait)

                let suffix = self.pending.slice(self.marker.length(), needed).get()

                if suffix == "\r\n".to_bytes() or suffix == "--".to_bytes():
                    self.final = suffix == "--".to_bytes()
                    self.pending = (
                        self
                        .pending
                        .slice(needed, self.pending.length())
                        .get()
                    )
                    self.ended = True
                    return ok(Step.End)

                available = 1

        if available > 0:
            let count = wanted if wanted < available else available

            if count > self.part_remaining: return error(IoError.LimitExceeded)

            let result = self.pending.slice(0, count).get()
            self.pending = self.pending.slice(count, self.pending.length()).get()
            self.part_remaining -= count
            return ok(Step.Data(result))

        if self.eof: return error(IoError.InvalidData)

        return ok(Step.Wait)

def scan(shared: Shared[Scanner], limit: Int, line: Bool) -> Result[Step, IoError]:
    msrt_shield_enter()

    with let preparation = Preparation():
        with var scanner_guard = lock(shared):
            return scanner_guard.value.line_step(limit) if line else scanner_guard.value.payload_step(
                limit
            )

def read_line(shared: Shared[Scanner], limit: Int) -> Result[Bytes, IoError]:
    while True:
        with let step = Held(try scan(shared, limit, True)):
            match step.value:
                case Data(bytes): return ok(bytes.clone())
                case End: return error(IoError.InvalidData)
                case Wait: try fill(shared)

    return error(IoError.InvalidData)

def payload(shared: Shared[Scanner], wanted: Int) -> Result[Optional[Bytes], IoError]:
    while True:
        with let step = Held(try scan(shared, wanted, False)):
            match step.value:
                case Data(bytes): return ok(some(bytes.clone()))
                case End: return ok(none)
                case Wait: try fill(shared)

    return error(IoError.InvalidData)

type PartReader:
    scanner: Shared[Scanner]
    active: Shared[Bool]
    busy: Shared[Bool]
    failed: Shared[Bool]

impl ReadStream for PartReader:
    var def close() -> Unit:
        with var flag_guard = lock(self.active):
            flag_guard.value = False

    var def read(max_bytes: Optional[Int] = none) -> Result[Optional[Bytes], IoError]:
        if not self.active.get() or self.busy.get(): return error(IoError.Closed)

        let wanted = max_bytes.get(65536)
        if wanted <= 0: return error(IoError.InvalidInput)

        with var flag_guard = lock(self.busy):
            flag_guard.value = True

        let result = payload(self.scanner, wanted)
        with var flag_guard = lock(self.busy):
            flag_guard.value = False
        if not self.active.get(): return error(IoError.Closed)

        if result.is_error():
            with var flag_guard = lock(self.failed):
                flag_guard.value = True
            with var flag_guard = lock(self.active):
                flag_guard.value = False

        return result

type PartScope:
    active: Shared[Bool]
    busy: Shared[Bool]
    failed: Shared[Bool]
    part: MultipartPart

impl Closeable for PartScope:
    var def close() -> Unit:
        with var flag_guard = lock(self.active):
            flag_guard.value = False

type MultipartScope:
    scanner: Shared[Scanner]
    opening: Bytes
    closing: Bytes

impl Closeable for MultipartScope:
    var def close() -> Unit: ()

def prepare(
    request: Request,
    limits: MultipartLimits
) -> Result[MultipartScope, IoError]:
    msrt_shield_enter()

    with let preparation = Preparation():
        if (
            limits.max_bytes < 0
            or limits.max_part_bytes < 0
            or limits.max_parts < 0
            or limits.max_header_bytes < 2
            or limits.max_headers < 0
        ): return error(IoError.InvalidInput)

        let media = request.headers.values("Content-Type")
        if media.is_none(): return error(IoError.InvalidInput)

        let values = media.get()
        if values.length() != 1 or values[0].length() > 1024: return error(
            IoError.InvalidInput
        )

        let decoded = values[0].decode_utf8()
        if decoded.is_none(): return error(IoError.InvalidInput)

        let parsed = try parameters(decoded.get())
        if parsed.kind != "multipart/form-data": return error(IoError.InvalidInput)

        let boundary = parsed.values.get("boundary")
        if (
            boundary.is_none()
            or boundary.get().byte_length() < 1
            or boundary.get().byte_length() > 70
            or boundary.get().ends_with(" ")
        ): return error(IoError.InvalidInput)

        for char in boundary.get().chars():
            if not "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'()+_,-./:=? ".contains(
                char
            ): return error(IoError.InvalidInput)

        let opening = ("--" + boundary.get()).to_bytes()
        return ok(
            MultipartScope(
                share(
                    Scanner(
                        request.clone(), "".to_bytes(), limits.max_bytes,
                        ("\r\n--" + boundary.get()).to_bytes(), limits.max_part_bytes
                    )
                ),
                opening.clone(),
                opening.concat("--".to_bytes())
            )
        )

def reset_part(shared: Shared[Scanner], limit: Int) -> Unit:
    msrt_shield_enter()

    with let preparation = Preparation():
        with var scanner_guard = lock(shared):
            scanner_guard.value.ended = False
            scanner_guard.value.part_remaining = limit

def clear_pending(shared: Shared[Scanner]) -> Unit:
    msrt_shield_enter()
    with let preparation = Preparation():
        with var scanner_guard = lock(shared):
            scanner_guard.value.pending = "".to_bytes()

def append_header(fields: HttpHeaders, raw: Bytes) -> Result[Unit, IoError]:
    let decoded = raw.decode_utf8()
    if decoded.is_none(): return error(IoError.InvalidData)

    let line = decoded.get()
    let colon = line.index_of(":")
    if colon.is_none(): return error(IoError.InvalidData)

    let added = fields.append(
        line.take(colon.get()), line.drop(colon.get() + 1).trim().to_bytes()
    )
    if added.is_error(): return error(IoError.InvalidData)

    return ok(())

def part_scope(
    shared: Shared[Scanner],
    fields: HttpHeaders
) -> Result[PartScope, IoError]:
    msrt_shield_enter()

    with let preparation = Preparation():
        let dispositions = fields.text("Content-Disposition")
        if (
            dispositions.is_error()
            or dispositions.get().is_none()
            or dispositions.get().get().length() != 1
        ): return error(IoError.InvalidData)

        let disposition = try parameters(dispositions.get().get() [0])
        if disposition.kind != "form-data" or not disposition.values.contains("name"): return error(
            IoError.InvalidData
        )
        if fields.values("Content-Transfer-Encoding").is_some(): return error(
            IoError.InvalidData
        )

        let active = share(True)
        let busy = share(False)
        let failed = share(False)
        return ok(
            PartScope(
                active,
                busy,
                failed,
                MultipartPart(
                    disposition.values.get("name").get().clone(),
                    disposition.values.get("filename").clone(), fields.clone(),
                    PartReader(shared, active, busy, failed)
                )
            )
        )

def read_part(
    shared: Shared[Scanner],
    limits: MultipartLimits
) -> Result[PartScope, IoError]:
    reset_part(shared, limits.max_part_bytes)

    with let fields = Held(headers()):
        var remaining = limits.max_header_bytes + 0
        var count = 0

        while True:
            with let raw = Held(try read_line(shared, remaining)):
                remaining -= raw.value.length() + 2
                if raw.value.length() == 0: break

                count += 1
                if count > limits.max_headers: return error(IoError.LimitExceeded)

                try append_header(fields.value, raw.value)

        return part_scope(shared, fields.value)

def epilogue(shared: Shared[Scanner]) -> Result[Unit, IoError]:
    clear_pending(shared)

    while not shared.get().eof:
        try fill(shared)
        clear_pending(shared)

    return ok(())

def opening(scope: MultipartScope, limits: MultipartLimits) -> Result[Bool, IoError]:
    while True:
        with let line = Held(try read_line(scope.scanner, limits.max_header_bytes)):
            if line.value == scope.opening: return ok(True)

            if line.value == scope.closing:
                try epilogue(scope.scanner)
                return ok(False)

    return error(IoError.InvalidData)

# Visits multipart form parts sequentially without buffering their payloads.
# Readers expire on callback return/fault/cancellation. Successful callbacks drain unread
# payloads; errors stop parsing. Input ownership stays with the caller. Filenames are metadata.
export def multipart(
    request: Request,
    visit: Callable[[MultipartPart], Result[Unit, IoError]],
    limits: MultipartLimits = MultipartLimits()
) -> Result[Unit, IoError]:
    with let scope = try prepare(request, limits):
        if not try opening(scope, limits): return ok(())

        var count = 0

        while not scope.scanner.get().final:
            if count >= limits.max_parts: return error(IoError.LimitExceeded)

            count += 1

            with let part = try read_part(scope.scanner, limits):
                try visit(part.part)
                with var flag_guard = lock(part.active):
                    flag_guard.value = False
                if part.busy.get() or part.failed.get(): return error(
                    IoError.InvalidData
                )

                while True:
                    with let chunk = Held(try payload(scope.scanner, 65536)):
                        if chunk.value.is_none(): break

        while scope.scanner.get().pending.length() < 2 and not scope.scanner.get().eof:
            try fill(scope.scanner)
        if (
            scope.scanner.get().pending.length() != 0
            and not scope.scanner.get().pending.starts_with(
                "\r\n".to_bytes()
            )
        ): return error(IoError.InvalidData)

        return epilogue(scope.scanner)

    return error(IoError.Closed)

from "@std/fs.ms" import filesystem, join, FileSystemError
from "@std/io.ms" import copy

# Spools one part into a private temporary directory and invokes visit with its path.
# The file and directory are removed on return, error, fault or cancellation. The
# client filename is never used as a path. Move/copy the file during visit to retain it.
export def with_upload(
    part: MultipartPart,
    visit: Callable[[String], Result[Unit, IoError]],
    max_bytes: Int = 16777216
) -> Result[Unit, IoError]:
    if max_bytes < 0: return error(IoError.InvalidInput)

    with let directory = try file_result(filesystem().temporary("manuscript-upload-")):
        with let path = Held(join([directory.path(), "payload"])):
            with let file = try file_result(filesystem().open(path.value, "wx", 384)):
                with let output = Held(file.writer()):
                    let count = try copy(part.body, output.value, some(max_bytes))
            return visit(path.value)

    return error(IoError.Closed)

def file_result[T](result: Result[T, FileSystemError]) -> Result[T, IoError]:
    if let value = result.to_optional(): return ok(value)

    return error(IoError.Unavailable)
