# Deque rotation directions

Times rotations after constructing the deque, then checks its final front and length. Arguments are population, signed rotation count and repetitions. The program prints elapsed nanoseconds. Keep population × repetitions below the Int limit used by the expected-position calculation.

```sh
MS_BACKEND=cranelift ms build bench/perf/deque-rotation/main.ms --build-type Release -o /tmp/deque-rotation
/tmp/deque-rotation 8192 8191 1000
/tmp/deque-rotation 8191 8190 1000
/tmp/deque-rotation 8192 1 5000000
/tmp/deque-rotation 8192 -1 5000000
/tmp/deque-rotation 8192 -8191 5000000
/tmp/deque-rotation 8192 4096 1000
/tmp/deque-rotation 0 1 5000000
/tmp/deque-rotation 1 1 5000000
```

Compare matching baseline and candidate builds in alternating order over at least 21 pairs, pinned to one CPU where supported. The power-of-two population fills the ring; one less leaves a partial ring. Retain unit-direction, negative near-whole, half-turn, empty and singleton controls. Small timing differences can be layout or scheduler noise: confirm them using both implementations in one process before interpreting them as regressions.
