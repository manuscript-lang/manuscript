import Bytes from "@std/bytes.ms"

export extern fn msstd_encoding_base64_encode_unpadded(data Bytes, url_safe Bool) String

export extern fn msstd_encoding_base64_decode(
	text String,
	url_safe Bool,
	max_bytes Int?,
) Bytes!

export extern fn msstd_encoding_base64_decode_unpadded(
	text String,
	url_safe Bool,
	max_bytes Int?,
) Bytes!
