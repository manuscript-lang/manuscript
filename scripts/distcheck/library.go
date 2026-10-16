package main

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
)

func libraryFixture(directory string) (string, error) {
	root := filepath.Join(directory, "library")
	cli := filepath.Join(directory, "ms")
	if runtime.GOOS == "windows" {
		cli += ".exe"
	}
	for name, text := range map[string]string{
		"ms.toml":      "# library\n[project]\nname = \"library\"\nsource = \"src\"\n",
		"src/value.ms": "export fn value() -> Int: return 3\n",
		"src/unimported.ms": `import panic from "@std/faults.ms"
import filesystem from "@std/fs.ms"
export fn other() -> Int: return 4
test "source":
    if other() != 4: return panic("bad other")
    match filesystem().read_file(path: "fixture.txt", max_bytes: 1024):
        ok(data):
            if data.length() != 7: return panic("wrong fixture size")
        error(_):
            return panic("library fixture cwd changed")
`,
		"fixture.txt":         "fixture",
		"tests/value_test.ms": "import value from \"../src/value.ms\"\nimport panic from \"@std/faults.ms\"\ntest \"separate\":\n    if value() != 3: return panic(\"bad value\")\n",
		"tests/defaults_test.ms": fmt.Sprintf(`import {parse, CsvOptions} from "@std/csv.ms"
import {base64_encode, base64_decode} from "@std/encoding.ms"
import commands from "@std/process.ms"
import filesystem from "@std/fs.ms"
import {compress, decompress, CompressionFormat} from "@std/compress.ms"
import panic from "@std/faults.ms"
test "copied native defaults":
    let first = CsvOptions()
    first.delimiter = ";"
    if CsvOptions().delimiter != ",": return panic("shared default options")
    match parse("a,b\n"):
        error(_): return panic("default CSV parse failed")
        ok(rows):
            if rows.length() != 1: return panic("default CSV rows")
    if base64_encode("f".to_bytes()) != "Zg==": return panic("default alphabet")
    match base64_decode("Zg=="):
        error(_): return panic("default Base64 decode failed")
        ok(bytes):
            if bytes.to_string().unwrap() != "f": return panic("default decoded bytes")
    let run = commands().run
    match run(program: %q, arguments: ["--version"]):
        error(_): return panic("default command stdin failed")
        ok(output):
            if output.exit_code != 0 or output.stdout.length() == 0: return panic("default command output")
    let fs = filesystem()
    match fs.create_directory("defaults"):
        error(_): return panic("default directory creation")
        ok(_): unit
    match fs.write_file("defaults/keep", "first".to_bytes()):
        error(_): return panic("default exclusive write")
        ok(_): unit
    let write = fs.write_file
    match write("defaults/keep", "second".to_bytes()):
        ok(_): return panic("omitted replacement overwrote file")
        error(_): unit
    match fs.copy_file("defaults/keep", "defaults/copied"):
        error(_): return panic("default file copy")
        ok(_): unit
    match fs.copy_tree("defaults", "default-tree"):
        error(_): return panic("default tree copy")
        ok(_): unit
    match fs.remove("defaults"):
        ok(_): return panic("omitted recursion removed tree")
        error(_): unit
    match fs.read_file("defaults/keep"):
        error(_): return panic("default retained file")
        ok(data):
            if data != "first".to_bytes(): return panic("default changed retained bytes")
    match fs.remove("defaults", recursive: true):
        error(_): return panic("explicit recursive removal")
        ok(_): unit
    let data = "compression defaults".to_bytes()
    let compressed = compress(data, "gzip").unwrap()
    if compressed != compress(data, "gzip", 6).unwrap(): return panic("default compression level")
    let encode = CompressionFormat.Gzip.compress
    if encode(data).unwrap() != compressed: return panic("bound default compression level")
    if decompress(compressed, "gzip").unwrap() != data: return panic("default compression round trip")
`, cli),
	} {
		path := filepath.Join(root, name)
		if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
			return "", err
		}
		if err := os.WriteFile(path, []byte(text), 0644); err != nil {
			return "", err
		}
	}
	return filepath.Join(root, "ms.toml"), nil
}

func checkLibrarySource(cli, manifest string, run func(string, ...string) (string, error)) error {
	for _, command := range []string{"check", "lint"} {
		_, err := run(cli, command, manifest)
		if err != nil {
			return err
		}
	}
	return nil
}

func checkLibraryNative(cli, manifest string, run func(string, ...string) (string, error)) error {
	if _, err := run(cli, "lock", manifest); err != nil {
		return err
	}
	data, err := run(cli, "test", manifest)
	if err != nil {
		return err
	}
	if !strings.Contains(data, "3 tests, 0 failed") {
		return fmt.Errorf("packaged library skipped tests: %s", data)
	}
	for _, command := range []string{"run", "build", "emit", "debug", "profile"} {
		_, err := run(cli, command, manifest)
		if err == nil || !strings.Contains(err.Error(), "ms.toml:2:1: resolution: library project has no executable entry") || !strings.Contains(err.Error(), "add entry =") {
			return fmt.Errorf("packaged %s library rejection: %v", command, err)
		}
	}
	return nil
}
