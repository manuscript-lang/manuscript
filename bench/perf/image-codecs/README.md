# Image codec speed

`main.ms` builds a 2048 by 2048 RGB image from a fixed formula and times `encode_image` (PNG),
`decode_image` (PNG), `encode_jpeg` and `decode_image` (JPEG). `main.go` does the same with Go's
`image/png` and `image/jpeg` (JPEG quality 75). `ms build bench/perf/image-codecs/main.ms -o /tmp/ic`;
`go build` in the directory after `go mod init x`. Compare speed with Go only.

## 2026-11-16, `main` 724c8dda, Linux x86-64

JPEG decode was quadratic in the image size. `jpeg_block(data, bits, comps[c], ...)` passes a
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

## 2026-11-16, constant lists read from static data (#4199)

A reference to a constant list of scalars is a borrowed view of static data (`list.const.view`,
`design/proposals/constant-list-view.md`) instead of a call that allocates, copies and frees a list on
every read. Best of 3, same machine, `main` 2b8a689e against this change:

| Step (2048 by 2048) | Before | After | Go 1.24.7 |
| --- | --- | --- | --- |
| JPEG decode | 1784 ms | 441 ms | 96 ms |
| JPEG encode | 2302 ms | 326 ms | 183 ms |

## 2026-11-16, per-pixel lists and per-element branches out of the codecs

`main` 2b8a689e plus #4202 against this change. Instruction counts are callgrind on a 512 by 512
image (`/tmp` copy of `main.ms` with `w` and `h` set to 512); wall times are the median of 6 runs
at 2048 by 2048 on a shared, noisy VM, so read them as a rough guide.

- JPEG decode built a four-element list and a three-element list for every pixel and called a
  general sampler with eight arguments per component. It now fills one row per component
  (`jpeg_fill_row`: a copy for full-resolution components, a specialised 2:1 triangle filter for
  4:2:0, the old sampler for other ratios) and converts with scalar helpers.
- PNG encode tested the filter type inside the per-byte loop. `filter_with` has one loop per type.

| Step | Instructions before | After | Wall before | Wall after | Go 1.24.7 |
| --- | --- | --- | --- | --- | --- |
| Whole program, 512 by 512 | 1061 M | 774 M | | | |
| JPEG decode (sampling and color) | 183 M | 62 M | 673 ms | 343 ms | 96 ms |
| PNG encode (`filter_row`) | 248 M | 168 M | 675 ms | 490 ms | 355 ms |

JPEG encode (`jpeg_forward`, 117 M) and the IDCT (`jpeg_plane`, 75 M) are unchanged: the 8 by 8
transform is a scalar matrix product on checked `Int` arithmetic. Skipping zero rows saved
nothing here because this image is noise, so it was not kept.

## 2026-11-16, 8 by 8 transforms use the matrix symmetry

`jpeg_dct_matrix` is exactly symmetric: row 7 - k is row k with the odd columns negated. A
sum over eight inputs is therefore a sum over four sums (even columns) or four differences (odd
columns) of mirrored inputs, and the decoder gets outputs k and 7 - k from one even and one odd
part. Half the multiplications, the same integers: the encoded size and the decoded checksum of
odd-sized images in both chroma modes are unchanged, and `image.ms` and `image-fuzz.ms` pass.

Callgrind, 512 by 512, after #4223:

| Function | Before | After |
| --- | --- | --- |
| `jpeg_plane` (inverse transform) | 75 M | 42 M |
| `jpeg_forward` (forward transform and quantization) | 117 M | 78 M |
| Whole program | 774 M | 696 M |

Wall time at 2048 by 2048 is noisy on this VM; the median of 5 went from 344 to about 285 ms for
JPEG encode and from 303 to about 270 ms for decode (Go 183 and 96 ms). What is left per block is
checked `Int` arithmetic and bounds checks on 64-element lists. A trial that computed the PNG
filter costs first and wrote only the winner was slower (231 M against 168 M for `filter_with`:
six passes instead of five plus the `emit` branch) and was dropped.
