// Package pricing computes session cost in integer satang (1 baht =
// 100 satang). Money MUST stay integer through every layer — no
// Float64 — to preserve the CLAUDE.md invariant on the iOS side.
package pricing

import (
	"errors"
	"math"
)

// Tariff is the pricing input for a single session. Mirrors the
// Tariff struct on the iOS side (Domain/Entities/Tariff.swift).
type Tariff struct {
	PricePerKWhSatang int64
	SessionFeeSatang  int64
}

// Validate checks the tariff is non-negative. Negative pricing would
// silently flip the sign of cost via the multiplication below — better
// to fail fast at the boundary than discover credit-style invoices in
// production.
func (t Tariff) Validate() error {
	if t.PricePerKWhSatang < 0 {
		return errors.New("pricing: pricePerKWhSatang cannot be negative")
	}
	if t.SessionFeeSatang < 0 {
		return errors.New("pricing: sessionFeeSatang cannot be negative")
	}
	return nil
}

// SessionCost computes the total cost of a session in integer satang:
//
//   cost = sessionFeeSatang + round(pricePerKWhSatang × kWh)
//
// kWh comes from (meterStop - meterStart) / 1000 — Wh on the wire,
// kWh in this calculation. We accept it as float64 because the
// division rarely lands on an integer (think 17.243 kWh) but the
// final satang figure rounds half-to-even to keep aggregate revenue
// fair across many sessions (banker's rounding).
//
// Returns an error if kWh is negative (clock skew or meter rollover)
// or NaN/Inf — caller should treat these as session faults.
func (t Tariff) SessionCost(kWh float64) (int64, error) {
	if math.IsNaN(kWh) || math.IsInf(kWh, 0) {
		return 0, errors.New("pricing: kWh is NaN or Inf")
	}
	if kWh < 0 {
		return 0, errors.New("pricing: kWh cannot be negative")
	}
	if err := t.Validate(); err != nil {
		return 0, err
	}

	// Use math.RoundToEven for banker's rounding. Multiplication is
	// done in float64 because pricePerKWhSatang is already a small
	// integer (~100s) and kWh is small enough that we won't lose
	// precision below the satang scale.
	energyCost := math.RoundToEven(float64(t.PricePerKWhSatang) * kWh)

	return t.SessionFeeSatang + int64(energyCost), nil
}

// EnergyKWh converts meter readings (Wh) to fractional kWh. Returns
// an error if the meter rolled backwards.
func EnergyKWh(meterStartWh, meterStopWh int) (float64, error) {
	if meterStopWh < meterStartWh {
		return 0, errors.New("pricing: meterStop is less than meterStart")
	}
	return float64(meterStopWh-meterStartWh) / 1000, nil
}
