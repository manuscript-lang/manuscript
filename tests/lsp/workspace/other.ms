import double from "./shapes.ms"

export fn quad(value Int) Int {
	return double(double(value))
}
