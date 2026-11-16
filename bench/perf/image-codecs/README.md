# Image codec speed

`main.ms` builds a 2048 by 2048 RGB image from a fixed formula and times `encode_image` (PNG),
`decode_image` (PNG), `encode_jpeg` and `decode_image` (JPEG). `main.go` does the same with Go's
`image/png` and `image/jpeg` (JPEG quality 75). `ms build bench/perf/image-codecs/main.ms -o /tmp/ic`;
`go build` in the directory after `go mod init x`. Compare speed with Go only.

## 2026-11-16, `main` 724c8dda, Linux x86-64

JPEG decode was quadratic in the image size. `jpeg_block(data, var bits, var comps[c], ...)` passes a
list element as `var` beside another `var` argument, and the lowering moved an element out of its
place in place only when the call had exactly one `var` argument. With two it copied the whole
`JpegComponent` (its coefficient list is the size of the image) into the callee and back for every
block: 3072 copies of 1.5 MB for a 256 by 256 image, 31% of the instructions in `memcpy`.
`Lowerer::lone_place_var` (`crates/ms-lower/src/call.rs`) now moves the element in place when it is
the only field or element place among the `var` arguments and the others are different locals.

| Size, step | Before | After | Go 1.24.7 (2048 only) |
| --- | --- | --- | --- |
| JPEG decode 256 by 256 | 39 ms | 22 ms | |
| JPEG decode 512 by 512 | 799 ms | 154 ms | |
| JPEG decode 2048 by 2048 | did not finish in 10 minutes | 1902 ms | 96 ms |
| JPEG encode 2048 by 2048 | | 2382 ms | 183 ms |
| PNG encode 2048 by 2048 | | 544 ms | 355 ms |
| PNG decode 2048 by 2048 | | 145 ms | 83 ms |

What is left in JPEG is per-element work in `jpeg_plane` and `jpeg_forward` (about a million
`msrt_free` calls each in the 256 by 256 profile), a separate change.
