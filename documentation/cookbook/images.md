+++
title = "Images"
weight = 11
+++

# Images

Decode, change and encode PNG, JPEG, BMP and PPM images without a native library.

## Build, encode, decode and resize

Save as `picture.ms`. An `Image` is a width, a height, a color mode and one flat list of bytes, so `set_pixel` and `pixel` take `(x, y)` and an `Rgba`. `new_image` starts black. `encode_image` returns the file bytes you write with `write_file`; `decode_image` detects the format from the bytes.

<!-- manuscript-example: {"mode":"run","stdout":"4x2 -> 2x1\n255 0 0\n"} -->
```manuscript
import (
    ColorMode,
    ImageFormat,
    Rgba,
    decode_image,
    encode_image,
    new_image
) from "@std/image/image.ms"

fn main() Void! {
    var picture = new_image(4, 2, ColorMode.Rgb)?
    picture.set_pixel(1, 0, Rgba(255, 0, 0, 255))

    png := encode_image(picture, ImageFormat.Png)?
    back := decode_image(png)?
    small := back.resize(2, 1)?
    print(f"{back.width}x{back.height} -> {small.width}x{small.height}")

    red := back.pixel(1, 0).get()
    print(f"{red.red} {red.green} {red.blue}")
}
```

- `crop`, `flip_horizontal`, `flip_vertical`, `rotate90`, `convert` (between gray, RGB and RGBA) and `resize` return a new image.
- Decoding untrusted files is safe: malformed data is an `EBADMSG` error, and `decode_image(bytes, max_pixels)` rejects a huge image before allocating it.
- `encode_jpeg(image, JpegOptions(...))` sets JPEG quality.
