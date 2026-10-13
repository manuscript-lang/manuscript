Welcome to Manuscript!

The single ms binary (ms.exe on Windows) includes Manuscript's native build tools,
required references, runtime, standard library, and native dependencies. No
separate Go installation or package downloads are needed. Copy the binary anywhere
on PATH. No companion toolchain directory is required. On first native use, ms
unpacks its reduced build payload into the OS user cache and reuses it thereafter.
The Delve terminal and DAP debugger are embedded: no dlv executable is needed.
On macOS only, native debugging still requires Apple debugserver from Xcode
command line tools and OS authorization. ms does not install it or change signing
credentials or security settings. Linux/Windows use Delve native backends.
CGO is disabled. MANUSCRIPT_CACHE_DIR selects a different writable cache directory.

From this directory on macOS/Linux:
  ./ms lock examples/hello/ms.toml
  ./ms run examples/hello/ms.toml -- first second
  ./ms build examples/hello/ms.toml -o hello
  ./hello first second
  ./ms test examples/hello/test.ms

In Windows PowerShell:
  .\ms.exe lock examples/hello/ms.toml
  .\ms.exe run examples/hello/ms.toml -- first second
  .\ms.exe build examples/hello/ms.toml -o hello.exe
  .\hello.exe first second
  .\ms.exe test examples/hello/test.ms

The hello program prints "Arguments: 2". Rerun lock when changing Manuscript or
the target toolchain. Native executables you build run independently of this
distribution. MANUSCRIPT_GO explicitly selects an alternative Go executable.

Documentation: https://manuscript-lang.github.io/manuscript/
Go and native dependency licenses are in licenses/ and embedded in the binary.
First builds use your OS's normal writable Go build cache directory.
