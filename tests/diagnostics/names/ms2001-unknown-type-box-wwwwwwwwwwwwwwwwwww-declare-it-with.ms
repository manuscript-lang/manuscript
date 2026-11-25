// conform: tags=diagnostics
// conform: phase=check
fn map_box[T, U_wwwwwwwwwwww](
	b_wwwwwwwwwwwwwwwwwwwwwwww Box_wwwwwwwwwwwwwwwwwww[T],
	f_wwwwwwwwwww fn(T) U_wwwwwwwwwwww
) Box_wwwwwwwwwwwwwwwwwww[U_wwwwwwwwwwww] {
	return b_wwwwwwwwwwwwwwwwwwwwwwww
}
// expect-error: MS2001 4:32 unknown type Box_wwwwwwwwwwwwwwwwwww; declare it with 'type Box_wwwwwwwwwwwwwwwwwww:' / 'enum Box_wwwwwwwwwwwwwwwwwww:' / 'interface Box_wwwwwwwwwwwwwwwwwww:', declare it as a type parameter, or import it
// expect-error: MS2001 6:3 unknown type Box_wwwwwwwwwwwwwwwwwww; declare it with 'type Box_wwwwwwwwwwwwwwwwwww:' / 'enum Box_wwwwwwwwwwwwwwwwwww:' / 'interface Box_wwwwwwwwwwwwwwwwwww:', declare it as a type parameter, or import it
