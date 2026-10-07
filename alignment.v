// Shared alignment arithmetic for the range, linear, ring, and buddy allocators.
// Returns no offset when rounding would overflow; callers reject zero alignment.
module memory

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
