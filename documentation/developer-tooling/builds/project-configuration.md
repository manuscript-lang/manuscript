+++
title = "Project configuration"
weight = 1
+++

# Project configuration

Keep source selection and bundled inputs visible in review; create these files in one project directory.

## A project manifest

`ms.toml` (configuration, not Manuscript source):

```toml
[project]
name = "store"
source = "./src"
entry = "./src/main.ms"

[embed]
"@assets" = "./assets"
```

## Embedded files

Save `hello from assets` followed by a newline in `assets/message.txt`, then save `src/main.ms`:

<!-- manuscript-example: {"mode":"run","filename":"src/main.ms","target":"ms.toml","files":{"ms.toml":"[project]\nname = \"store\"\nsource = \"./src\"\nentry = \"./src/main.ms\"\n\n[embed]\n\"@assets\" = \"./assets\"\n","assets/message.txt":"hello from assets\n"},"stdout":"hello from assets\n"} -->
```manuscript {filename="src/main.ms"}
import files from "@assets"

fn message() String!:
    let tree = files()
    let contents = try tree.read("message.txt", none)
    return ok(try contents.decode_utf8().ok_or(Error("asset is not UTF-8")))

export fn main() Int:
    if let text = message():
        print(text.trim())
        return 0
    return 1
```

```sh
ms run ms.toml
```

```text
hello from assets
```

- Embedded contents travel with the executable; the example handles both read and UTF-8 failures.
- Manuscript is in alpha; syntax, APIs and project settings may change.

<span id="commands-and-module-discovery"></span>
<span id="library-projects-and-copied-dependencies"></span>
<span id="resolving-an-import"></span>
<span id="module-identity-and-configuration-scope"></span>

Next: [module imports](../../core-language/modules/declarations.md), [manifest rules](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-driver/src/project/manifest.rs), [discovery rules](https://github.com/manuscript-lang/manuscript/tree/main/crates/ms-driver/src/project) and [build caches](incremental-compilation.md).
