module generic_pool

// align_forward returns the first value at or after value that is divisible by
// alignment. Callers validate that alignment is non-zero before using it.
fn align_forward(value u64, alignment u64) ?u64 {
	remainder := value % alignment
	if remainder == 0 {
		return value
	}
	padding := alignment - remainder
	if value > max_u64 - padding {
		return none
	}
	return value + padding
}
