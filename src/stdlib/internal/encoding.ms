import Bytes from "@std/bytes.ms"

export extern fn msstd_encoding_ascii85_encode(data: Bytes) move String

export extern fn msstd_encoding_ascii85_decode(
	text: String,
	max_bytes: Int?,
) move Bytes!

export extern fn msstd_encoding_base64_encode_unpadded(
	data: Bytes,
	url_safe: Bool,
) move String

export extern fn msstd_encoding_base64_decode(
	text: String,
	url_safe: Bool,
	max_bytes: Int?,
) move Bytes!

export extern fn msstd_encoding_base64_decode_unpadded(
	text: String,
	url_safe: Bool,
	max_bytes: Int?,
) move Bytes!

export extern fn msstd_encoding_base32_encode(
	data: Bytes,
	hex_alphabet: Bool,
	padded: Bool,
) move String

export extern fn msstd_encoding_base32_decode(
	text: String,
	hex_alphabet: Bool,
	padded: Bool,
	max_bytes: Int?,
) move Bytes!

export extern fn msstd_encoding_hex_encode(data: Bytes) move String

export extern fn msstd_encoding_hex_decode(text: String, max_bytes: Int?) move Bytes!
