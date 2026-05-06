package server

import "strconv"

// scanFloatStrconv parses s as a float64 using strconv. Returns the
// number of values stored (1 on success, 0 on failure) so the
// signature matches our internal scanFloat helper.
func scanFloatStrconv(s string, out *float64) (int, error) {
	v, err := strconv.ParseFloat(s, 64)
	if err != nil {
		return 0, err
	}
	*out = v
	return 1, nil
}
