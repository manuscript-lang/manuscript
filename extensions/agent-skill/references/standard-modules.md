# Standard modules

Every standard module and the names it exports, from the declarations. Import with `import name, other from "@std/path/file.ms"`. The prelude (String, List, Map, Set, Optional, Result, Int, Float, Error, `print`) needs no import. `ms search_symbol <name>` prints a name's signature and import line.

Pick the module by task: text and parsing (`@std/text`, `@std/regex.ms`, `@std/data/json.ms`, `csv.ms`, `toml.ms`), files and processes (`@std/os`), streams and pipes (`@std/io`), promises (`@std/concurrency`), servers and clients (`@std/net`), time (`@std/time.ms`), math and randomness (`@std/math`, `@std/random.ms`), tests (`@std/test`), terminal programs (`@std/cli`).

```manuscript
import parse, stringify from "@std/data/json.ms"
import read_file from "@std/os/fs.ms"
import expect_equal from "@std/test/test.ms"
```

<!-- modules:start -->
- `@std/bytes.ms`: Bytes, BytesBuilder, VarintRead, join, values
- `@std/cli/command.ms`: Arg, Command, Flag, FlagKind, Matches, Parsed, command
- `@std/cli/screen.ms`: Screen, new_screen
- `@std/cli/style.ms`: Color, Style, paint, strip_ansi, style_start, styled, truncate_text, visible_width, wrap_text
- `@std/cli/table.ms`: Align, Table
- `@std/cli/terminal.ms`: EraseRegion, NativeRawTerminal, RawHandle, RawTerminal, TerminalCapabilities, TerminalDecoder, TerminalEvent, TerminalSize, raw_mode, terminal_capabilities, terminal_decoder, terminal_size
- `@std/collections/bitset.ms`: BitSet
- `@std/collections/collections.ms`: List, ListEntry, Map, MapEntry, Numeric, Pair, Partition, RangeOptions, SearchResult, Set, filled, flatten, map_from_entries, range_by
- `@std/collections/deque.ms`: Deque
- `@std/collections/itertools.ms`: Run, accumulate, combinations, cycle, group_runs, pairwise, permutations, product, zip_longest
- `@std/collections/queue.ms`: HeapEntry, PriorityQueue, Queue
- `@std/collections/sorted.ms`: SortedEntry, SortedMap, SortedRef, SortedSet
- `@std/concurrency/promise.ms`: Cancel, Placement, Promise, PromiseOptions, Signal, adopt, caller_frame, cancel_switch, complete, deferred, promise, promise_when_idle, set_options, wait_all, wait_first
- `@std/concurrency/resilience.ms`: CircuitBreaker, CircuitError, RateLimiter, RetryPolicy, Throttle, map_concurrent, rate_limiter, retry
- `@std/core.ms`: Clonable, Closeable, Comparable, Data, Equal, Error, Hashable, Iterator, Optional, Result, Stringable, Writable, join_errors, ok_or, panic, print, wrap_error
- `@std/crypto/blake2.ms`: blake2b, blake2s
- `@std/crypto/chacha20poly1305.ms`: chacha20, chacha20poly1305_open, chacha20poly1305_seal, poly1305
- `@std/crypto/crypto.ms`: Curve, HashAlgorithm, Hasher, NativeHasher, aes_cbc_decrypt, aes_cbc_encrypt, aes_ctr, constant_time_equal, constant_time_less_or_equal, constant_time_select, derive_key, digest, ecdh_shared_secret, ecdsa_generate, ecdsa_sign, ecdsa_verify, open, public_key, public_key_der, rsa_decrypt, rsa_encrypt, rsa_generate, rsa_sign, rsa_sign_pss, rsa_verify, rsa_verify_pss, seal, sha256, sha384, sha512, sign, verify, xor_bytes
- `@std/crypto/hash.ms`: Crc64, Crc64Polynomial, MapHash, crc64, crc64_of, fnv1_32, fnv1_64, fnv1a32, fnv1a64, random_seed
- `@std/data/checksum.ms`: Adler32, Crc32, adler32, adler32_of, crc32, crc32_of
- `@std/data/config.ms`: parse_dotenv, parse_ini
- `@std/data/csv.ms`: CsvOptions, csv_rows, csv_writer, each_cell, parse, stringify
- `@std/data/diff.ms`: CloseMatchesOptions, UnifiedDiffOptions, close_matches, edit_distance, similarity_ratio, unified_diff
- `@std/data/encoding.ms`: Base32Options, ascii85_decode, ascii85_encode, ascii_decode, ascii_encode, base32_decode, base32_encode, base64_decode, base64_encode, hex_decode, hex_encode, latin1_decode, latin1_encode, utf16_decode, utf16_encode
- `@std/data/encoding_stream.ms`: base64_decoded, base64_encoded, hex_decoded, hex_encoded
- `@std/data/histogram.ms`: Histogram, histogram
- `@std/data/html.ms`: HtmlAttribute, HtmlNode, HtmlOptions, escape, parse, unescape
- `@std/data/json.ms`: JsonEncode, JsonOptions, JsonValue, StringifyOptions, json_reader, json_writer, parse, stringify
- `@std/data/jwt.ms`: JwtAlgorithm, JwtCheck, sign_token, verify_token
- `@std/data/pem.ms`: PemBlock, encode_all, encode_block, parse
- `@std/data/quote.ms`: quote_text
- `@std/data/semver.ms`: Version, parse
- `@std/data/toml.ms`: TomlOptions, TomlValue, parse, stringify
- `@std/data/utf8.ms`: Utf8Error, Utf8Scalar, decode_first, decode_last, is_valid
- `@std/data/uuid.ms`: namespace_dns, namespace_oid, namespace_url, namespace_x500, uuid_v4, uuid_v5, uuid_v7, uuid_version
- `@std/data/xml.ms`: XmlAttribute, XmlNode, escape_attribute, escape_text, parse, stringify
- `@std/data/yaml.ms`: YamlOptions, YamlValue, parse, parse_all, stringify
- `@std/image/bmp.ms`: decode_bmp, encode_bmp
- `@std/image/codec.ms`: Raster, bad, byte, max_of, min_of, pixel_count, too_big, unsupported, zeroed
- `@std/image/image.ms`: Chroma, ColorMode, Image, ImageFormat, JpegOptions, Rect, Resampling, Rgba, color_channels, decode_image, detect_image_format, encode_image, encode_jpeg, new_image
- `@std/image/jpeg.ms`: decode_jpeg
- `@std/image/jpeg_encode.ms`: jpeg_encode
- `@std/image/jpeg_tables.ms`: jpeg_clamp, jpeg_dct_matrix, jpeg_zeros, jpeg_zigzag
- `@std/image/png.ms`: decode_png, encode_png
- `@std/image/ppm.ms`: decode_ppm, encode_ppm
- `@std/io/archive.ms`: ArchiveEntry, ArchiveFormat, ArchiveOptions, CompressOptions, CompressionFormat, NativeDecoder, NativeEncoder, compress, compressed, decompress, decompressed, pack, tar_entries, unpack
- `@std/io/forward.ms`: forward
- `@std/io/io.ms`: DescriptorSink, DescriptorSource, Pipe, ReadStream, Sink, Source, StdStream, Transform, WriteStream, pipe, redirect_to_null, stderr, stderr_bytes, stdin, stdout, stdout_bytes, through
- `@std/io/steps.ms`: filter, lines, map, take
- `@std/io/streams.ms`: collect, copy, fold, from_bytes, from_list, read_all
- `@std/log.ms`: LogLevel, Logger, LoggerOptions, Transport, create, file_transport, handle_transport, rotating_file_transport, stdout_transport
- `@std/math/big.ms`: BigFloat, BigRat, big_float_of_big_int, big_float_of_float, big_float_of_int, big_float_of_rat, max_big_float_precision, parse_big_float, parse_rat, rat, rat_of_big_int, rat_of_binary, rat_of_float, rat_of_int
- `@std/math/complex.ms`: Complex, PolarParts, complex, complex_polar, imaginary_unit
- `@std/math/decimal.ms`: Decimal, RoundingMode, parse_decimal
- `@std/math/math.ms`: BigInt, BinaryFloatParts, DivMod, FloatParts, WideProduct, WordDifference, WordDivision, WordSum, acos, acosh, add_with_carry, asin, asinh, atan, atan2, atanh, big_int_of_int, binomial, bit_and, bit_not, bit_or, bit_xor, cbrt, ceil, copy_sign, cos, cosh, count_ones, divide_wide, divmod, e, epsilon, exp, exp2, expm1, factorial, floor, fma, frexp, gcd, hypot, ieee_remainder, infinity, is_integer, is_safe_integer, isqrt, lcm, ldexp, leading_zeros, ln10, ln2, log, log10, log10e, log1p, log2, log2e, max, max_float, max_int, max_safe_integer, min, min_float, min_int, min_safe_integer, modf, multiply_wide, nan, next_after, parse_big_int, parse_float, parse_int, pi, pow, pow_int, remainder, remainder_wide, reverse_bits, reverse_bytes, rotate_left, rotate_right, round, round_to_even, shift_left, shift_right, shift_right_unsigned, sign_bit, sin, sinh, sqrt, sqrt2, sqrt_half, subtract_with_borrow, tan, tanh, trailing_zeros, truncate, wrapping_add, wrapping_multiply, wrapping_subtract
- `@std/math/statistics.ms`: BinCounts, Regression, bin_counts, correlation, linear_regression, mean, median, mode, percentile, population_stdev, population_variance, quantiles, stdev, variance
- `@std/net/fetch.ms`: FetchBody, FetchOptions, FetchResponse, Fetcher, FetcherOptions, fetch, fetcher, json_body
- `@std/net/http.ms`: ClientResponse, HttpClient, HttpClientOptions, HttpExchange, HttpHeaders, HttpMethod, HttpRequest, HttpResponse, HttpResponseMetadata, HttpServer, HttpServerOptions, NativeAccepted, NativeExchange, NativeHttpClient, NativeResponseBody, NativeServing, NativeWorker, NativeWorkerSpec, RawResponse, StreamingResponse, buffered, headers, json, native_handler, read_body, redirect, reply, text, upgrade
- `@std/net/ip.ms`: Cidr, DnsKind, DnsRecord, IpAddress, IpFamily, contains_ip, parse_cidr, parse_ip
- `@std/net/mail.ms`: Address, Message, decode_words, parse_address, parse_address_list, parse_message
- `@std/net/mime.ms`: HeaderField, Headers, MediaType, Part, encode_multipart, extension_for_media_type, form_part, format_media_type, media_type_for_extension, multipart_boundary, multipart_parts, parse_headers, parse_media_type, parse_multipart
- `@std/net/net.ms`: Connection, ConnectionInfo, Datagram, DatagramSocket, DnsOptions, Listener, NativeConnection, NativeDatagramSocket, NativeListener, NativeNetwork, Network, PendingConnection, RequestOptions, accept_tls, bind_datagram, connect, connect_unix, http_client, listen, listen_tls, listen_unix, lookup, request, resolve_dns, restrict, serve, start_tls, web_socket, with_resolver
- `@std/net/router.ms`: Route, RouteParams, Router, Segment, access_log, request_id, with_request_headers
- `@std/net/sse.ms`: SseEvent, SseLimits, sse_events
- `@std/net/tls.ms`: CertificateInfo, TlsInfo, TlsOptions, parse_certificates, verify_certificates
- `@std/net/url.ms`: QueryEntry, Url, decode_component, encode_component, format, format_query, parse, parse_query, resolve
- `@std/net/websocket.ms`: NativeWebSocket, RawWebSocketMessage, WebSocket, WebSocketKind, WebSocketMessage, WebSocketOptions, WebSocketWire, web_socket_from
- `@std/os/env.ms`: arguments, change_directory, environment, home_directory, load_environment, set_environment, which, working_directory
- `@std/os/fs.ms`: CloneMode, CopyOptions, Directory, DirectoryEntry, FileEvent, FileHandle, FileInfo, FileKind, FileSystemInfo, GlobOptions, NativeDirectory, NativeFile, NativeTemporary, NativeWatcher, OpenMode, OpenOptions, PathEntry, RawWatcher, Seek, TemporaryDirectory, WatchOptions, access, append_file, canonicalize, chmod, chown, copy, create_directory, create_hard_link, create_symlink, exists, glob, list, move, open, open_directory, read_file, read_symlink, remove, rename, set_times, stat, stat_filesystem, temporary, temporary_directory, temporary_root, truncate, watch, write_atomic, write_file
- `@std/os/path.ms`: Glob, PathOperations, PathParts, basename, basename_without, compile_glob, delimiter, dirname, extension, format, is_absolute, join, matches_glob, normalize, parse, posix, relative, resolve, separator, stem, to_namespaced_path, win32, with_extension
- `@std/os/process.ms`: CommandOutput, Commands, CpuUsage, IdentityKind, NativeSignals, NativeSubprocess, ProcessInfo, ResourceUsage, RunOptions, SpawnOptions, Stdio, Signal, Subprocess, cpu_usage, get_priority, groups, initialize_groups, kill, process_info, replace, resource_usage, run, send_signal, set_groups, set_identity, set_priority, set_title, spawn, title, watch_signals
- `@std/os/system.ms`: CpuInfo, Endianness, MemoryUsage, NetworkInterface, Os, RuntimeCounts, SystemInfo, SystemMetrics, UserInfo, available_memory, constants, constrained_memory, cpus, dev_null, end_of_line, endianness, hostname, machine, memory_usage, metrics, network_interfaces, os, os_release, os_version, runtime_counts, system_info, uptime, user_info
- `@std/os/tree.ms`: EmbeddedTree, FileTree, HostTree, MemoryTree, WalkEntry, embedded_tree, host_tree, memory_tree, msstd_embed_bytes, walk
- `@std/random.ms`: SeededRandom, choice, float, random_bytes, sample, secure_int, seeded, shuffle, token, ulid, weighted_choice
- `@std/regex.ms`: Regex, RegexSpan, compile
- `@std/string.ms`: NormalizationForm, SplitParts, from_scalars
- `@std/test/bench.ms`: run_bench_block, run_bench_fixture
- `@std/test/boundary.ms`: finite_float_boundaries, float_boundaries, int_boundaries
- `@std/test/golden.ms`: expect_golden, expect_golden_bytes
- `@std/test/iotest.ms`: check_reader, fail_after, fail_writer_after, one_byte
- `@std/test/property.ms`: Drawn, Gen, PropertyOptions, Settings, Source, bools, check, constant, draw, element_of, floats, ints, lists, one_of, optionals, pairs, settings, source, strings
- `@std/test/test.ms`: TestHooks, caller_site, catch_fault, expect_close, expect_contains, expect_equal, expect_error, expect_false, expect_fault, expect_none, expect_not_equal, expect_ok, expect_some, expect_true, fail, repr, skip
- `@std/text.ms`: parse_bool, quote, quote_ascii, scalars, unquote
- `@std/text/template.ms`: RenderOptions, Template, TemplateBranch, TemplateExpr, TemplateNode, compile, render, render_to, to_data
- `@std/time.ms`: Date, Deadline, Duration, Instant, Timestamp, deadline_after, from_calendar, hours, local_zone, microseconds, milliseconds, minutes, monotonic, nanoseconds, now, parse_duration, parse_timestamp, seconds, sleep, ticker, timestamp
- `@std/unicode.ms`: is_alphabetic, is_alphanumeric, is_ascii, is_control, is_digit, is_lowercase, is_mark, is_numeric, is_punctuation, is_symbol, is_uppercase, is_whitespace
<!-- modules:end -->

Timing: `start := monotonic()` then `monotonic().difference(start).to_milliseconds()`, with `monotonic` from `@std/time.ms` (the function reaches `std.clock.read`). Padding: `s.pad_start(width, " ")` and `pad_end` exist; do not hand-write them. A type's `fn to_json() JsonValue` is its JSON encoder; a `to_json` with any other signature is an ordinary method. Stacked `// ms: allow_effect` lines above one function are allowed.
