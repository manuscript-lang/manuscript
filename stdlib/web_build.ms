from "@std/core.ms" import Closeable
from "@std/http.ms" import Request, Response, Body, HttpError
from "@std/web_assets.ms" import Asset, Assets, asset
from "@std/fs.ms" import filesystem, join, dirname, FileSystemError
from "@std/io.ms" import IoError

# One generated deployment file and its URL representation.
export type StaticFile:
    # URL path used by the asset router.
    url: String
    # Portable relative output path, validated by StaticBuild.add.
    path: String
    # Immutable encoded representation served at this file’s URL.
    value: Asset

# Explicit static-site build manifest. Page handlers are ordinary functions called at build time.
export type StaticBuild:
    # Maximum generated files admitted to this build; defaults to 4096.
    max_files: Int = 4096
    # Maximum total encoded representation bytes.
    max_bytes: Int = 67108864
    # Generated files in insertion order.
    files: List[StaticFile] = []
    # Current encoded byte count.
    bytes: Int = 0

impl StaticBuild:
    # Adds a representation with an exact URL and portable output path. Collisions fail before mutation.
    var def add(url: String, path: String, value: Asset) -> Result[Unit, HttpError]:
        if (
            self.max_files < 0
            or self.max_bytes < 0
            or self.bytes < 0
            or self.bytes > self.max_bytes
        ): return error(HttpError.InvalidInput)
        if (
            self.files.length() >= self.max_files
            or value.data.length() > self.max_bytes - self.bytes
        ): return error(HttpError.LimitExceeded)
        if not portable(path): return error(HttpError.InvalidInput)

        var checked = Assets()
        try checked.add(url.clone(), value.clone())

        for file in self.files:
            let existing = file.path.lower()
            let candidate = path.lower()
            if (
                file.url == url
                or existing == candidate
                or existing.starts_with(candidate + "/")
                or candidate.starts_with(existing + "/")
            ): return error(HttpError.InvalidInput)

        self.bytes += value.data.length()
        self.files.append(StaticFile(url, path, value))
        return ok(())

    # Invokes a page handler with a synthetic GET, snapshots its buffered 200 body, and adds it.
    # Cookies, Vary and response-only dynamic behavior are rejected; use live routes for those pages.
    var def render(
        url: String,
        path: String,
        page: Callable[[Request], Response]
    ) -> Result[Unit, HttpError]:
        let response = page(Request(path: url.clone()))
        if (
            response.status != 200
            or response.headers.values("Set-Cookie").is_some()
            or response.headers.values("Vary").is_some()
        ): return error(HttpError.InvalidInput)

        var header_bytes = 8192
        let names = response.headers.names()
        if names.length() > 16: return error(HttpError.InvalidInput)

        for name in names:
            if not ["content-type", "cache-control", "x-content-type-options"].contains(
                name.lower()
            ): return error(HttpError.InvalidInput)

            for raw in response.headers.values(name).get():
                if raw.length() > header_bytes: return error(HttpError.LimitExceeded)

                header_bytes -= raw.length()

        var cache_control = "public, max-age=0, must-revalidate"
        let policy = response.headers.text("Cache-Control")
        if policy.is_error(): return error(HttpError.InvalidInput)

        if let values = policy.get():
            if values.length() != 1: return error(HttpError.InvalidInput)

            for directive in values[0].lower().split(","):
                if ["private", "no-store"].contains(directive.trim().split("=") [0]): return error(
                    HttpError.InvalidInput
                )
            cache_control = values[0].clone()

        let media = response.headers.text("Content-Type")
        if media.is_error() or media.get().is_none() or media.get().get().length() != 1: return error(
            HttpError.InvalidInput
        )

        let data = buffered(response.body)
        if data.is_none(): return error(HttpError.InvalidInput)
        if (
            response.content_length.is_some()
            and response.content_length.get() != data.get().length()
        ): return error(HttpError.InvalidInput)

        return self.add(
            url,
            path,
            try asset(
                data.get().clone(), media.get().get() [0].clone(),
                cache_control: cache_control
            )
        )

    # Creates an immutable URL manifest for serving generated pages through the normal router.
    def assets() -> Result[Assets, HttpError]:
        var result = Assets()
        for file in self.files: try result.add(file.url.clone(), file.value.clone())
        return ok(result)

    # Writes to a new private staging directory and invokes visit with its path.
    # All paths are revalidated; file/directory collisions and preexisting symlinks cannot enter
    # staging through this API. Cleanup removes staging on every exit. Publish/copy inside visit.
    def stage(visit: Callable[[String], Result[Unit, IoError]]) -> Result[Unit, IoError]:
        with Held(try validated(self)) as checked:
            with try io_result(filesystem().temporary("manuscript-static-")) as directory:
                with Held(directory.path()) as root:
                    var index = 0

                    while index < checked.value.files.length():
                        try stage_file(root.value, checked.value.files[index])
                        index += 1

                    return visit(root.value)

        return error(IoError.Closed)

type Held[T]:
    value: T

impl Closeable for Held[T]:
    var def close() -> Unit: ()

def validated(build: StaticBuild) -> Result[StaticBuild, IoError]:
    var checked = StaticBuild(build.max_files, build.max_bytes)

    for file in build.files:
        let valid = checked.add(file.url.clone(), file.path.clone(), file.value.clone())
        if valid.is_error(): return error(IoError.InvalidInput)

    return ok(checked)

def stage_file(root: String, file: StaticFile) -> Result[Unit, IoError]:
    with Held(join([root.clone(), file.path.clone()])) as path:
        try io_result(filesystem().create_directory(dirname(path.value), True))
        with try io_result(filesystem().open(path.value, "wx", 420)) as output:
            return io_result(output.write_bytes(file.value.data))

    return error(IoError.Closed)

from "@std/bytes.ms" import Bytes

def buffered(body: Body) -> Optional[Bytes]:
    match body:
        case Buffered(data): return some(data.clone())
        case _: return none

def portable(path: String) -> Bool:
    if path.byte_length() == 0 or path.byte_length() > 1024 or path.starts_with("/"): return False

    for part in path.split("/"):
        if (
            part == ""
            or part == "."
            or part == ".."
            or part.ends_with(".")
            or part.byte_length() > 255
        ): return False

        let base = part.split(".") [0].lower()
        if [
            "con", "prn", "aux", "nul", "com1", "com2", "com3", "com4", "com5", "com6",
            "com7", "com8", "com9", "lpt1", "lpt2", "lpt3", "lpt4", "lpt5", "lpt6",
            "lpt7", "lpt8", "lpt9"
        ].contains(base): return False

        for char in part.chars():
            if not "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-".contains(
                char
            ): return False

    return True

def io_result[T](result: Result[T, FileSystemError]) -> Result[T, IoError]:
    if let value = result.to_optional(): return ok(value)

    return error(IoError.Unavailable)
