/**
 * Currency helpers — mirror
 * `Voltspot/Voltspot/Core/Localization/CurrencyFormatter.swift`.
 *
 * Money is integer satang (CLAUDE.md invariant). Convert to baht ONLY
 * for display, and prefer `Intl.NumberFormat` with currency style so
 * Thai locale conventions stay correct (฿ prefix, decimal comma in
 * some locales, etc.).
 *
 * Why not store baht as a `number`: floating-point drift on
 * accumulators. 1 baht + 0.1 baht * 100 sessions = 11.000000000000002
 * baht in JS. Integer satang accumulation is exact.
 */

const BAHT = new Intl.NumberFormat('en-TH', {
  style: 'currency',
  currency: 'THB',
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
});

export function satangToBaht(satang: number): string {
  return BAHT.format(satang / 100);
}

/** kWh formatter — one decimal place, like the iOS '%.1f kWh'. */
export function kWh(value: number): string {
  return `${value.toFixed(1)} kWh`;
}

/** Compact integer with locale grouping ("1,234"). */
export function compactInt(value: number): string {
  return value.toLocaleString('en-US');
}
