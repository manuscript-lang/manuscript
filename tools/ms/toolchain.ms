// The pinned LLVM tools and lld the C build runs (`ms_build_object`, `ms_build_link`):
// which archive a platform gets (`toolchain/lld.lock`), the download, its SHA-256
// check, the unpacking and the cache. The cache is
// `<cache>/ms/<name>/<first 16 digits of the archive's SHA-256>/`, written once: files are staged in a directory
// beside it and renamed in, and `.ok` marks a finished directory, so builds running at
// once never see a partial file.
import (
	Bytes from "@std/bytes.ms",
	sha256 from "@std/crypto/crypto.ms",
	hex_encode from "@std/data/encoding.ms",
	uuid_v4 from "@std/data/uuid.ms",
	ArchiveEntry,
	ArchiveFormat,
	ArchiveOptions,
	CompressionFormat,
	compress,
	decompress,
	pack,
	unpack from "@std/io/archive.ms",
	FetchOptions, fetch from "@std/net/fetch.ms",
	environment from "@std/os/env.ms",
	chmod,
	create_directory,
	exists,
	remove,
	rename,
	temporary_directory,
	write_file from "@std/os/fs.ms",
	basename, join from "@std/os/path.ms",
	system_info from "@std/os/system.ms",
	expect_equal, expect_true from "@std/test/test.ms",
	seconds, sleep from "@std/time.ms",

	parse_https, proxy_for, proxy_get from "./proxy_get.ms",
)

// One downloadable archive: where it is and the digest it must have.
export type Pin:
	url: String
	sha256: String

// A download is tried this many times; a runner's DNS or network blip must not fail a
// build.
ATTEMPTS := 4
// The largest archive taken.
MAX_ARCHIVE := 268435456

// The archive of `kind` (`lld` or `llvm-tools`) that `lock` (the text of
// toolchain/lld.lock) names for `os` (`linux`, `darwin`, `windows`) and `arch`
// (`amd64`, `arm64`), or none when the platform has no release.
export fn lock_pin(lock: String, kind: String, os: String, arch: String) Pin?:
	var tag = ""
	var version = ""

	for line in lock.split("\n"):
		if line.starts_with("tag "): tag = line.slice(4, line.length()).trim()
		if line.starts_with("version "): version = line.slice(8, line.length()).trim()

	if tag == "" or version == "": return none

	asset := f"{kind}-{version}-{os}-{arch}.tar.gz"

	for line in lock.split("\n"):
		row := line.trim()
		if not row.ends_with(asset): continue

		parts := row.split(" ")
		if parts.length() < 2 or parts[parts.length() - 1] != asset: continue

		url := f"https://github.com/manuscript-lang/llvm-bundle/releases/download/{tag}/{asset}"
		return Pin(url: url, sha256: parts[0].clone())

	return none

// Where downloads are cached: `$XDG_CACHE_HOME`, else `~/.cache`, or `%LOCALAPPDATA%`
// on Windows; then `ms`.
export fn cache_root() String!:
	env := environment()?

	if system_info().os == "windows":
		if local := env.get("LOCALAPPDATA"): return ok(at(local.clone(), "ms"))
		return error(
			Error(
				"LOCALAPPDATA is not set; cannot place the tool cache",
				kind: "ENOENT",
			)
		)

	if xdg := env.get("XDG_CACHE_HOME"):
		if xdg != "": return ok(at(xdg.clone(), "ms"))
	if home := env.get("HOME"): return ok(at(at(home.clone(), ".cache"), "ms"))

	return error(Error("HOME is not set; cannot place the tool cache", kind: "ENOENT"))

// The body of `url`, retried with a growing pause when the connection fails or the
// server answers with an error that can pass (5xx, 429). `HTTPS_PROXY` (and `NO_PROXY`)
// route it through an HTTP proxy with proxy_get.ms.
export fn download(url: String) Bytes!:
	target := parse_https(url)?
	proxy := proxy_for(environment()?, target.host)
	var last = Error("no attempt was made", kind: "EIO")
	var pause = 1

	for attempt in 0..ATTEMPTS:
		if attempt > 0:
			sleep(seconds(pause)).wait()?
			pause *= 2

		if via := proxy:
			through := proxy_get(via, url, MAX_ARCHIVE)
			if through.is_ok(): return through

			last = through.err()
			continue

		sent := fetch(
			url,
			FetchOptions(
				timeout: seconds(120),
				max_response_bytes: MAX_ARCHIVE,
			),
		).wait()

		if sent.is_error():
			last = sent.err()
			continue

		response := sent.get()
		if response.ok(): return ok(response.body.clone())

		status := response.head.status
		last = Error(f"download of {url} answered {status}", kind: "EIO")
		if status < 500 and status != 429: break

	return error(last)

fn executable(name: String) String:
	if system_info().os == "windows": return f"{name}.exe"
	return name.clone()

// The path `part` inside `base`.
fn at(base: String, part: String) String:
	return join([base.clone(), part.clone()])

// The directory `<root>/<name>/<first 16 digits of sha>` holding `files` (each with
// `.exe` on Windows): fetched with
// `fetch_archive` and checked against `sha` when it is not there yet. Each file is taken from the `bin/` of the
// gzipped tar by its base name.
export fn ensure(
	root: String,
	name: String,
	sha: String,
	files: List[String],
	fetch_archive: fn() Bytes!
) String!:
	dir := join([root.clone(), name.clone(), sha.slice(0, 16)])
	var wanted = List[String]()
	for file in files: wanted.append(executable(file))
	if complete(dir, wanted)?: return ok(dir)

	stage := join([root.clone(), name.clone(), f".fetch-{uuid_v4()?}"])
	create_directory(stage, true)?

	installed := install(dir, stage, name, sha, wanted, fetch_archive)
	void remove(stage, true)
	if installed.is_error():
		return error(
			Error(
				f"cannot fetch {name} into {dir}: {installed.err().message}",
				kind: installed.err().kind,
			)
		)

	return ok(dir)

fn complete(dir: String, wanted: List[String]) Bool!:
	if not exists(at(dir, ".ok"))?: return ok(false)

	for file in wanted:
		if not exists(at(dir, file))?: return ok(false)
	return ok(true)

fn install(
	dir: String,
	stage: String,
	name: String,
	sha: String,
	wanted: List[String],
	fetch_archive: fn() Bytes!
) Void!:
	archive := fetch_archive()?
	got := hex_encode(sha256(archive))
	if got != sha:
		return error(
			Error(
				f"checksum {got} does not match the pinned {sha}",
				kind: "EBADMSG",
			)
		)

	tar := decompress(archive, CompressionFormat.Gzip)?
	entries := unpack(tar, ArchiveFormat.Tar)?

	for file in wanted:
		var found = false

		for entry in entries:
			if entry.directory or basename(entry.path) != file: continue

			target := at(stage, file)
			write_file(target, entry.data, replace: true).wait()?
			chmod(target, 0x1ed)?
			found = true
			break

		if not found: return error(
			Error(f"{file} is not in the archive", kind: "ENOENT")
		)

	create_directory(dir, true)?

	for file in wanted:
		// A concurrent build may have installed (and be running) the same file already.
		moved := rename(at(stage, file), at(dir, file))
		if moved.is_error() and not exists(at(dir, file))?: return error(moved.err())

	return write_file(at(dir, ".ok"), "", replace: true).wait()

// An archive holding `bin/<file>` for each name, as `ensure` reads it.
fn sample_archive(files: List[String]) Bytes!:
	var entries = List[ArchiveEntry]()
	for file in files:
		entries.append(
			ArchiveEntry(
				path: f"bin/{file}",
				data: f"#!/bin/sh\necho {file}\n".to_bytes(),
				directory: false,
			)
		)
	return compress(pack(entries, ArchiveFormat.Tar)?, CompressionFormat.Gzip)

LOCK := "# pinned\ntag llvm-1.2.3-r4\nversion 1.2.3\naaaa  lld-1.2.3-linux-amd64.tar.gz\nbbbb  llvm-tools-1.2.3-linux-amd64.tar.gz\ncccc  lld-1.2.3-darwin-arm64.tar.gz\n"

test "lock_pin names the archive and url of a platform":
	pin := lock_pin(LOCK, "lld", "linux", "amd64").get()
	expect_equal(pin.sha256, "aaaa")?
	expect_equal(
		pin.url,
		"https://github.com/manuscript-lang/llvm-bundle/releases/download/llvm-1.2.3-r4/lld-1.2.3-linux-amd64.tar.gz",
	)?

	other := lock_pin(LOCK, "llvm-tools", "linux", "amd64").get()
	expect_equal(other.sha256, "bbbb")?

test "lock_pin has nothing for a platform without a release":
	expect_true(lock_pin(LOCK, "lld", "windows", "arm64").is_none())?
	expect_true(lock_pin("version 1.2.3\n", "lld", "linux", "amd64").is_none())?

test "ensure fetches once, checks the digest and installs the files":
	root := at(temporary_directory("ms-toolchain-")?, "cache")
	archive := sample_archive(["opt", "llc"])?
	sha := hex_encode(sha256(archive))
	var downloads = 0

	dir := ensure(
		root.clone(),
		"llvm",
		sha,
		["opt", "llc"],
		fn() Bytes!:
			downloads += 1
			return ok(archive.clone())
	)?

	expect_equal(dir, join([root.clone(), "llvm", sha.slice(0, 16)]))?
	expect_true(exists(at(dir, executable("opt")))?)?
	expect_true(exists(at(dir, executable("llc")))?)?

	again := ensure(
		root.clone(),
		"llvm",
		sha,
		["opt", "llc"],
		fn() Bytes!:
			downloads += 1
			return ok(archive.clone())
	)?

	expect_equal(again, dir)?
	expect_equal(downloads, 1)?
	remove(root, true)?

test "ensure refuses an archive that does not match the pin":
	root := at(temporary_directory("ms-toolchain-")?, "cache")
	archive := sample_archive(["opt"])?
	wrong := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
	result := ensure(
		root.clone(),
		"llvm",
		wrong,
		["opt"],
		fn() Bytes!: return ok(archive.clone())
	)
	expect_true(result.is_error())?
	expect_true(result.err().message.contains("does not match the pinned"))?
	remove(root, true)?

test "ensure names a file the archive lacks":
	root := at(temporary_directory("ms-toolchain-")?, "cache")
	archive := sample_archive(["opt"])?
	sha := hex_encode(sha256(archive))
	result := ensure(
		root.clone(),
		"llvm",
		sha,
		["opt", "llc"],
		fn() Bytes!: return ok(archive.clone())
	)
	expect_true(result.is_error())?
	expect_true(result.err().message.contains("llc is not in the archive"))?
	remove(root, true)?
