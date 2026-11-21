import Decimal from "@std/math/decimal.ms"

fn exact() Decimal:
	return 1.5d

fn small() Decimal:
	return 1e-6176d

fn zero() Decimal:
	return 0e99999d

fn too_many_digits() Decimal:
	return 1234567890123456789012345678901234567d

fn too_small() Decimal:
	return 1e-6177d

fn too_large() Decimal:
	return 1e6145d
