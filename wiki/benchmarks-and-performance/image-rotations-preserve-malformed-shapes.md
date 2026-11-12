[Wiki](../index.md) › [Benchmarks and performance](index.md)

# Image rotations preserve malformed shapes

`Image.rotate180` and `rotate270` copy valid pixel buffers directly instead of
making two or three full-buffer passes. Keep channels in their original
order: reversing the byte buffer also reverses the channels within each pixel.

`Image` fields are public. Validate a complete positive shape using division and
remainder before the fast path, without multiplying unchecked dimensions. Retain
the original compositions for malformed shapes: even an empty shape can reach an
overflow check in the old vertical flip. Short and extra buffers are controls too.

Verify with the `e2e/stdlib/image-rotations` conformance fixture and
[`bench/perf/image-rotations`](../../bench/perf/image-rotations/README.md).
Measure tiny images and every channel count, and select benchmark functions before
starting the timer so dispatch order cannot manufacture a small-image win.
