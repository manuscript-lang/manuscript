# Deque rotation uses the shorter signed remainder

Reduce the rotation count modulo the current length before choosing direction. A positive remainder greater than half the length can subtract the length and move backward; a negative remainder below minus half can add the length and move forward. This bounds work by the shorter route for both signs, rather than fixing one direction while retaining a near-whole-turn slowdown in the other.

Do not negate the original count: Int.min is valid. Exact half-turn ties retain their original direction. Use the existing pop/push moves so payload ownership remains unchanged; ring offsets are internal state, while logical order, length and subsequent mutations must agree.

Validate empty, singleton, full, partial and wrapped rings with signed boundary counts and nested optional payloads. The [rotation benchmark](../../bench/perf/deque-rotation/README.md) includes near-whole-turn improvements and ordinary unit/half-turn controls.
