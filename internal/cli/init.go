package cli

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

const initHelp = `Usage: ms init [directory]

Create a runnable project in the directory (default: the current directory).
Writes ms.toml, src/main.ms (a hello program), test.ms, and a .gitignore that
excludes the .ms-cache/ build cache. An existing file is never overwritten; the
command fails before writing anything when ms.toml, src/main.ms, or test.ms exist.

Keep .ms-cache/ out of version control.

Options:
  -h, --help  Show this help without creating files

Examples:
  ms init
  ms init hello
  cd hello && ms run ms.toml -- first second
`

const initMain = `import arguments from "@std/cli.ms"
import stdout from "@std/io.ms"

export fn main() -> Int:
    let message = "Arguments: {arguments().length()}\n"

    match stdout().write(data: message.to_bytes()):
    ok(_):
        return 0
    error(_):
        return 1
`

const initTest = `import panic from "@std/faults.ms"

test "arithmetic":
    if not (2 + 3 == 5):
        return panic(message: "arithmetic failed")
`

const initIgnore = ".ms-cache/\n"

func runInit(args []string) int {
	directory := "."
	given := false
	for _, arg := range args {
		if strings.HasPrefix(arg, "-") || given {
			fmt.Fprintln(os.Stderr, "unexpected init argument:", arg, "; ms init takes at most one directory, e.g. ms init hello")
			return 2
		}
		if arg == "" {
			fmt.Fprintln(os.Stderr, "ms init: the directory is empty; pass a directory name such as ms init hello, or omit it for the current directory")
			return 2
		}
		directory, given = arg, true
	}
	absolute, err := filepath.Abs(directory)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	files := []struct{ name, content string }{
		{"ms.toml", fmt.Sprintf("[project]\nname = %q\nsource = \"./src\"\nentry = \"./src/main.ms\"\n", projectName(absolute))},
		{filepath.Join("src", "main.ms"), initMain},
		{"test.ms", initTest},
	}
	for _, file := range files {
		if _, err := os.Lstat(filepath.Join(absolute, file.name)); err == nil {
			fmt.Fprintf(os.Stderr, "ms init: %s already exists; run it in an empty directory or remove the file first\n", filepath.Join(directory, file.name))
			return 1
		}
	}
	fail := func(err error) int {
		fmt.Fprintf(os.Stderr, "ms init: cannot create project in %s: %v\n", directory, err)
		return 1
	}
	if err := os.MkdirAll(filepath.Join(absolute, "src"), 0o755); err != nil {
		return fail(err)
	}
	for _, file := range files {
		if err := os.WriteFile(filepath.Join(absolute, file.name), []byte(file.content), 0o644); err != nil {
			return fail(err)
		}
	}
	if err := ignoreBuildCache(filepath.Join(absolute, ".gitignore")); err != nil {
		return fail(err)
	}
	fmt.Println("Created project in", directory)
	fmt.Println("Next: ms run", shellQuote(filepath.Join(directory, "ms.toml")), "-- first second")
	return 0
}

// ignoreBuildCache creates .gitignore, or appends the cache entry to an existing
// one that does not already exclude it.
func ignoreBuildCache(path string) error {
	existing, err := os.ReadFile(path)
	if err != nil && !os.IsNotExist(err) {
		return err
	}
	for _, line := range strings.Split(string(existing), "\n") {
		switch strings.TrimSpace(line) {
		case ".ms-cache", ".ms-cache/", "/.ms-cache", "/.ms-cache/":
			return nil
		}
	}
	content := string(existing)
	if content != "" && !strings.HasSuffix(content, "\n") {
		content += "\n"
	}
	return os.WriteFile(path, []byte(content+initIgnore), 0o644)
}

// projectName derives a manifest name from the directory: lowercase letters,
// digits, '-' and '_', falling back to "app".
func projectName(directory string) string {
	var b strings.Builder
	for _, r := range strings.ToLower(filepath.Base(directory)) {
		switch {
		case r >= 'a' && r <= 'z', r >= '0' && r <= '9', r == '-', r == '_':
			b.WriteRune(r)
		case r == ' ' || r == '.':
			b.WriteByte('-')
		}
	}
	if name := strings.Trim(b.String(), "-_"); name != "" {
		return name
	}
	return "app"
}

// shellQuote quotes a path for display in a command the user can paste.
func shellQuote(path string) string {
	if !strings.ContainsAny(path, " \t\n'\"\\$`!&;|<>()*?[]{}#~") {
		return path
	}
	return "'" + strings.ReplaceAll(path, "'", `'\''`) + "'"
}
