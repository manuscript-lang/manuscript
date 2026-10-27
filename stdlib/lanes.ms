# Eight `Float32` values operated on together with one vector instruction (SIMD).
#
# Internal to the standard library: `@std/vec.ms` builds its numeric kernels on `Lanes`, and
# programs call those kernels instead. A `Lanes` lives in vector registers; it is created, combined
# and reduced only through the `msrt_lanes_*` natives that `@std/vec.ms` declares, and it is never
# stored in a list, record or map.
export type Lanes: ...
