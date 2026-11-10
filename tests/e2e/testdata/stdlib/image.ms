import (
    decode_image,
    encode_image,
    encode_jpeg,
    new_image,
    ColorMode,
    ImageFormat,
    JpegOptions,
    Chroma,
    Rgba from "@std/image/image.ms",
    hex_decode from "@std/data/encoding.ms",
    vectors from "./image-png-vectors.ms",
    jpeg_vectors from "./image-jpeg-vectors.ms",
    expect_equal, fail from "@std/test/test.ms",
)

test "ppm round trip":
    var img = new_image(3, 2, ColorMode.Rgb).get()
    img.set_pixel(1, 1, Rgba(10, 20, 30))

    data := encode_image(img, ImageFormat.Ppm).get()
    back := decode_image(data).get()
    try expect_equal(back.width, 3)
    try expect_equal(back.pixels.length(), 18)
    try expect_equal(back.pixel(1, 1).get().green, 20)

test "bmp round trip":
    var img = new_image(5, 3, ColorMode.Rgba).get()
    img.set_pixel(4, 2, Rgba(1, 2, 3, 200))

    back := decode_image(encode_image(img, ImageFormat.Bmp).get()).get()
    try expect_equal(back.pixel(4, 2).get().alpha, 200)
    try expect_equal(back.pixel(0, 0).get().alpha, 255)

test "truncated rejected":
    data := encode_image(new_image(4, 4, ColorMode.Rgb).get(), ImageFormat.Ppm).get()
    cut := data.slice(0, data.length() - 1).get()
    try expect_equal(decode_image(cut).is_ok(), false)

test "png decodes every independent vector":
    for v in vectors():
        img := decode_image(hex_decode(v.png, none).get()).get()
        try expect_equal(img.width, v.width)
        try expect_equal(img.height, v.height)

        for y in 0..v.height:
            for x in 0..v.width:
                at := (y * v.width + x) * 4
                c := img.pixel(x, y).get()
                try expect_equal(
                    [c.red, c.green, c.blue, c.alpha], v.rgba.slice(at, at + 4).get()
                )

test "png encode decodes back":
    var img = new_image(7, 5, ColorMode.Rgba).get()
    for y in 0..5:
        for x in 0..7:
            img.set_pixel(x, y, Rgba(x * 30, y * 50, (x * y) % 256, 255 - x))

    back := decode_image(encode_image(img, ImageFormat.Png).get()).get()
    try expect_equal(back.pixels, img.pixels)

test "jpeg decodes libjpeg vectors within tolerance":
    for v in jpeg_vectors():
        img := decode_image(hex_decode(v.jpeg, none).get()).get()
        try expect_equal(img.width, v.width)
        try expect_equal(img.height, v.height)
        try expect_equal(img.channel_count(), v.channels)

        var worst = 0

        for i in 0..v.pixels.length():
            d := img.pixels[i].to_int() - v.pixels[i]
            a := if d < 0: 0 - d else: d
            if a > worst: worst = a

        if worst > v.tolerance: try fail("{v.name}: max error {worst} > {v.tolerance}")

test "jpeg encode round trips close to the source":
    var img = new_image(37, 29, ColorMode.Rgb).get()
    for y in 0..29:
        for x in 0..37:
            img.set_pixel(x, y, Rgba(x * 6, y * 8, 128 + (x - y) * 2))

    for chroma in [Chroma.Full, Chroma.Quarter]:
        for interval in [0, 3]:
            data := encode_jpeg(
                img,
                JpegOptions(
                    quality: 95, chroma: chroma, restart_interval: interval
                )
            ).get()
            back := decode_image(data).get()
            try expect_equal(back.width, 37)

            var worst = 0

            for i in 0..img.pixels.length():
                d := img.pixels[i].to_int() - back.pixels[i].to_int()
                a := if d < 0: 0 - d else: d
                if a > worst: worst = a

            if worst > 16: try fail("worst error {worst} for interval {interval}")

test "jpeg gray round trip and alpha rejection":
    var img = new_image(9, 9, ColorMode.Gray).get()
    for i in 0..9:
        img.set_pixel(i, i, Rgba(250, 250, 250))

    back := decode_image(encode_jpeg(img, JpegOptions(quality: 100)).get()).get()
    try expect_equal(back.channel_count(), 1)
    try expect_equal(encode_jpeg(new_image(2, 2, ColorMode.Rgba).get()).is_ok(), false)
