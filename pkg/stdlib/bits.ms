# Returns the bitwise AND of two integers.
export fn bit_and(left: Int, right: Int) Int:

# Returns the bitwise OR of two integers.
export fn bit_or(left: Int, right: Int) Int:

# Returns the bitwise exclusive OR of two integers.
export fn bit_xor(left: Int, right: Int) Int:

# Returns the bitwise complement, so every bit of the two's-complement value flips.
export fn bit_not(value: Int) Int:

# Shifts bits toward the high end, discarding bits shifted out; `count` must be 0 through 63 or the call faults.
export fn shift_left(value: Int, count: Int) Int:

# Shifts bits toward the low end, filling with the sign bit (JavaScript `>>`); `count` must be 0 through 63 or the call faults.
export fn shift_right(value: Int, count: Int) Int:

# Shifts bits toward the low end, filling with zeros (JavaScript `>>>`); `count` must be 0 through 63 or the call faults.
export fn shift_right_unsigned(value: Int, count: Int) Int:

# Rotates the 64-bit pattern toward the high end; any `count` is reduced modulo 64.
export fn rotate_left(value: Int, count: Int) Int:

# Rotates the 64-bit pattern toward the low end; any `count` is reduced modulo 64.
export fn rotate_right(value: Int, count: Int) Int:

# Counts the set bits in the 64-bit pattern.
export fn count_ones(value: Int) Int:

# Counts the zero bits above the highest set bit; zero has 64.
export fn leading_zeros(value: Int) Int:

# Counts the zero bits below the lowest set bit; zero has 64.
export fn trailing_zeros(value: Int) Int:

# Adds with two's-complement wraparound instead of faulting on overflow.
export fn wrapping_add(left: Int, right: Int) Int:

# Subtracts with two's-complement wraparound instead of faulting on overflow.
export fn wrapping_subtract(left: Int, right: Int) Int:

# Multiplies with two's-complement wraparound instead of faulting on overflow (JavaScript `Math.imul` at 64 bits).
export fn wrapping_multiply(left: Int, right: Int) Int:
