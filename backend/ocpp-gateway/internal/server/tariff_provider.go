package server

import (
	"context"

	"github.com/sirawitchpoon/voltspot/backend/ocpp-gateway/internal/firestore"
	"github.com/sirawitchpoon/voltspot/backend/ocpp-gateway/internal/pricing"
)

// FirestoreTariffProvider is the default PricingProvider — looks up
// the station document and returns its tariff.
//
// Cache note: Firestore reads are billed per document. For chargers
// that fire StartTransaction back-to-back, an in-memory LRU around
// this would cut reads but adds a staleness window when partners
// edit pricing. Defer until profiling shows it's a hot path.
type FirestoreTariffProvider struct {
	Writer *firestore.Writer
}

func (p *FirestoreTariffProvider) Tariff(ctx context.Context, stationID string) (pricing.Tariff, error) {
	st, err := p.Writer.Station(ctx, stationID)
	if err != nil {
		return pricing.Tariff{}, err
	}
	t := pricing.Tariff{
		PricePerKWhSatang: st.PricePerKWhSatang,
		SessionFeeSatang:  st.SessionFeeSatang,
	}
	if err := t.Validate(); err != nil {
		return pricing.Tariff{}, err
	}
	return t, nil
}
