import Entropy from "@std/os/random.ms"

export extern fn msstd_random_draw_int(
    entropy: Entropy,
    min: Int,
    max_exclusive: Int?
) Int!

export extern fn msstd_random_draw_uuid(entropy: Entropy) String!

export extern fn msstd_random_draw_float(entropy: Entropy) Float!

export extern fn msstd_random_draw_shuffle[T](
    entropy: Entropy,
    values: List[T]
) List[T]!

export extern fn msstd_random_draw_choice[T](entropy: Entropy, values: List[T]) T?!

export extern fn msstd_random_entropy() Entropy
