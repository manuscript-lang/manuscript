# Manuscript

Simple enough for AI to write. Clear enough for humans to review. Easy enough for computers to verify.

```manuscript
type coder using (fs: Filesystem, sh: Shell)
  Agent
  task: string
  system: () => """
    You are a senior engineer. Task: {task}
    Write clean code. Be concise.
  """
  tools: [read_file, write_file, run_cmd]

// Read file contents
fn read_file(path: string): string using (fs: Filesystem)
  fs.read(path)

// Write to file
fn write_file(path: string, content: string) using (fs: Filesystem)
  fs.write(path, content)

// Run shell command
fn run_cmd(cmd: string): string using (sh: Shell)
  sh.exec(cmd).stdout
```

```manuscript
with let fs = Filesystem(), let sh = Shell()
  coder(task: "Refactor auth.ts").run("Go")
```

---

## Why Manuscript

**`using` and `with` replace dependency injection.**  
Functions declare what they need. Callers provide it. Same code runs in prod and tests—swap the capability, not the code.

```manuscript
fn deploy(code: string) using (fs: Filesystem, sh: Shell)
  fs.write("app.js", code)
  sh.exec("node app.js")

with let fs = Filesystem(), let sh = Shell()
  deploy(code)

with let fs = MockFilesystem(), let sh = MockShell()
  deploy(code)
```

Capability types are defined with `context TypeName` (e.g. `context Filesystem`); see [Syntax § Capabilities](./syntax.md#7-capabilities).

**Prompts are templates.**  
Multi-line strings with `{interpolation}`, `{if}`, and `{for}`. No escaping.

```manuscript
system: () => """
  You are a {role}.
  
  {for skill in skills}
  - You know {skill}
  {end}
"""
```

**Statically typed.**  
Types flow through your code. Tool signatures become schemas the LLM can use. Errors caught at compile time.

**Minimal syntax, fewer tokens.**  
No semicolons, braces, or `async/await`. Indentation defines scope. Less noise means fewer tokens for LLMs to write—and easier for humans to review.

---

## Testing

First-class `test` blocks. Provide capabilities with `with` and mock as needed.

```manuscript
test "agent creates file"
  with let fs = MockFilesystem(), let llm = MockLLM()
    coder(task: "Create main.js").run("Start")
    assert fs.exists("main.js")
```

---

## Syntax

```manuscript
let name = "world"                  // immutable
var count = 0                       // mutable

type User
  id: number
  name: string
  role: string = "member"           // default
  email?: string                    // optional

fn greet(u: User): string
  "Hello, {u.name}"

match code
  200..299 => "ok"
  400..499 => "client error"
  _ => "error"

users | filter((u) => u.active) | map((u) => u.name)
```

See [Syntax](./syntax.md) for the full language: control flow, loops, generics, interfaces, error handling, concurrency (`spawn`, `race`), set literals `<1, 2, 3>`, and the standard library.

---

## Install

```bash
bun add -g manuscript
```

```bash
manuscript run agent.ms      # run
manuscript check agent.ms    # type check
```

**VS Code:** `cd vscode-extension && ./install.sh`

---

[Syntax](./syntax.md) · [Stdlib](./stdlib.md) · [Design](./REQUIREMENTS.md) · MIT
