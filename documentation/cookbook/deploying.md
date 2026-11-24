+++
title = "Deploying one binary"
weight = 22
+++

# Deploying one binary

Build a program into a single executable, copy it to a server or into a container, and run it there with nothing else installed.

## Build the executable

Save as `app.ms`.

<!-- manuscript-example: {"mode":"run","stdout":"hello from a single file\n"} -->
```manuscript
fn main() Void {
    print("hello from a single file")
}
```

Build it for release, small and static, then run the result:

```sh
ms build app.ms --build-type MinSizeRel --static -o app
./app
```

```text
Built app
hello from a single file
```

- `--static` (Linux) links a self-contained musl executable that does not depend on the system's C library, so it runs on any Linux of the same architecture. Without it, the executable needs glibc 2.28 or newer.
- `MinSizeRel` strips symbols for the smallest file. Use `Release` to keep function names for profilers and backtraces.
- The executable includes the runtime and the parts of the standard library the program reaches. The example above is under a megabyte.
- Builds link with the linker bundled in `ms`; no C compiler or SDK is needed on the build machine.
- Build on the platform you ship to, for example one CI job per platform.

## Check before you ship

`ms verify` runs the checker, the format check, lint and the tests and returns one result:

```sh
ms verify
```

The format check fails on any file `ms fmt` would change, so run `ms fmt` first.

## Run it in a container

The executable needs no base image, so the container holds one file:

```dockerfile
FROM scratch
COPY app /app
ENTRYPOINT ["/app"]
```

A service listens on `0.0.0.0` inside a container and takes its port and other settings from [environment variables](service-config.md). It stops cleanly on the SIGTERM that the container runtime sends ([stopping cleanly](shutdown.md)).
