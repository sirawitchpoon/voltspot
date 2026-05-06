package pricing

import (
	"math"
	"testing"
)

func TestSessionCost(t *testing.T) {
	tests := []struct {
		name   string
		tariff Tariff
		kWh    float64
		want   int64
	}{
		{
			name:   "asoke 17.5kWh @ ฿7.50/kWh, no session fee",
			tariff: Tariff{PricePerKWhSatang: 750, SessionFeeSatang: 0},
			kWh:    17.5,
			want:   13125, // 750 * 17.5
		},
		{
			name:   "siam paragon: 12kWh @ ฿8.50 + ฿20 session fee",
			tariff: Tariff{PricePerKWhSatang: 850, SessionFeeSatang: 2000},
			kWh:    12.0,
			want:   12200, // 850*12 + 2000
		},
		{
			name:   "fractional with banker's rounding (round half to even)",
			tariff: Tariff{PricePerKWhSatang: 750, SessionFeeSatang: 0},
			kWh:    1.0 / 1500.0, // 0.000666... × 750 = 0.5 exactly
			want:   0,            // bank's rounding: 0.5 → 0 (nearest even)
		},
		{
			name:   "session fee only, zero energy",
			tariff: Tariff{PricePerKWhSatang: 750, SessionFeeSatang: 1000},
			kWh:    0,
			want:   1000,
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got, err := tc.tariff.SessionCost(tc.kWh)
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if got != tc.want {
				t.Errorf("SessionCost(%v, %v) = %d satang, want %d",
					tc.tariff, tc.kWh, got, tc.want)
			}
		})
	}
}

func TestSessionCostRejectsBadInput(t *testing.T) {
	tariff := Tariff{PricePerKWhSatang: 750, SessionFeeSatang: 0}
	for _, kWh := range []float64{-1, math.NaN(), math.Inf(1), math.Inf(-1)} {
		if _, err := tariff.SessionCost(kWh); err == nil {
			t.Errorf("expected error for kWh=%v", kWh)
		}
	}
}

func TestValidateRejectsNegativeTariffs(t *testing.T) {
	cases := []Tariff{
		{PricePerKWhSatang: -1, SessionFeeSatang: 0},
		{PricePerKWhSatang: 0, SessionFeeSatang: -1},
	}
	for _, c := range cases {
		if err := c.Validate(); err == nil {
			t.Errorf("expected error validating %v", c)
		}
	}
}

func TestEnergyKWh(t *testing.T) {
	got, err := EnergyKWh(1_000, 18_500)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	const want = 17.5
	if math.Abs(got-want) > 1e-9 {
		t.Errorf("EnergyKWh = %v, want %v", got, want)
	}

	if _, err := EnergyKWh(2_000, 1_000); err == nil {
		t.Error("expected error on backward meter")
	}
}
