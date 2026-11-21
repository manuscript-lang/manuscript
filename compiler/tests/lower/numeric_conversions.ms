fn widen_byte(b: UInt8) Int:
	return b.to_int()

fn widen_short(b: Int16) Int:
	return b.to_int()

fn narrow_wide(b: UInt16) UInt8?:
	return b.to_uint8()

fn narrow_int(n: Int32) Int8?:
	return n.to_int8()

fn int_as_float(n: Int) Float:
	return n.to_float()

fn small_as_float(n: Int8) Float32:
	return n.to_float32()

fn float32_widen(f: Float32) Float:
	return f.to_float()

fn use(n: Int16, m: UInt8) Int:
	return n.to_int() + m.to_int()

fn main() Int:
	small: Int16 := -3
	byte: UInt8 := 7
	wide: UInt16 := 300
	narrow: Int32 := 100
	tiny: Int8 := 2
	f: Float32 := 1.5
	a := widen_byte(byte) + widen_short(small) + use(small, byte)
	if narrow_wide(wide).is_none() and narrow_int(narrow).is_some():
		return (
			a
			+ int_as_float(4).to_string().length()
			+ small_as_float(tiny).to_string().length()
			+ float32_widen(f).to_string().length()
		)

	return a
