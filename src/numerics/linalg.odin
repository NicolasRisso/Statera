package numerics

// Inverts the n×n row-major matrix `a` in place (Gauss–Jordan with partial pivoting).
// Returns false if the matrix is singular to working precision.
invert :: proc(a: []f64, n: int) -> bool {
	inv := make([]f64, n * n, context.temp_allocator)
	for i in 0 ..< n { inv[i * n + i] = 1 }
	m := make([]f64, n * n, context.temp_allocator)
	copy(m, a)
	for col in 0 ..< n {
		pivot := col
		for r in col + 1 ..< n {
			if abs(m[r * n + col]) > abs(m[pivot * n + col]) { pivot = r }
		}
		if abs(m[pivot * n + col]) < 1e-300 { return false }
		if pivot != col {
			for k in 0 ..< n {
				m[col * n + k], m[pivot * n + k] = m[pivot * n + k], m[col * n + k]
				inv[col * n + k], inv[pivot * n + k] = inv[pivot * n + k], inv[col * n + k]
			}
		}
		d := m[col * n + col]
		for k in 0 ..< n {
			m[col * n + k] /= d
			inv[col * n + k] /= d
		}
		for r in 0 ..< n {
			if r == col { continue }
			f := m[r * n + col]
			if f == 0 { continue }
			for k in 0 ..< n {
				m[r * n + k] -= f * m[col * n + k]
				inv[r * n + k] -= f * inv[col * n + k]
			}
		}
	}
	copy(a, inv)
	return true
}
