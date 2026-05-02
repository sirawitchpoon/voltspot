import CoreLocation
import Foundation

/// Minimal geohash encoder + bounding-prefix helper sized for Firestore
/// "stations near a point" queries.
///
/// Approach: encode every station's (lat, lng) to a 9-character base-32
/// geohash and store it on the document. To query a circle, compute the
/// shortest common prefix of the bounding box corners and run a single
/// range query (`geohash >= start && geohash < end`). Client-side filters
/// with great-circle distance to drop the rectangular slack.
///
/// Trade-off: when the search circle straddles a geohash cell boundary the
/// common prefix can shrink and we over-fetch up to 32× the area. Cheaper
/// in code than emitting the full 9-cell neighbour set, and acceptable at
/// MVP scale. Revisit if read costs become a hot spot.
enum Geohash {
    private static let base32: [Character] = Array("0123456789bcdefghjkmnpqrstuvwxyz")

    static func encode(latitude: Double, longitude: Double, precision: Int = 9) -> String {
        precondition(precision > 0)
        var minLat = -90.0, maxLat = 90.0
        var minLng = -180.0, maxLng = 180.0
        var hash = ""
        var bits = 0
        var ch = 0
        var evenBit = true

        while hash.count < precision {
            if evenBit {
                let mid = (minLng + maxLng) / 2
                if longitude >= mid {
                    ch = (ch << 1) | 1
                    minLng = mid
                } else {
                    ch <<= 1
                    maxLng = mid
                }
            } else {
                let mid = (minLat + maxLat) / 2
                if latitude >= mid {
                    ch = (ch << 1) | 1
                    minLat = mid
                } else {
                    ch <<= 1
                    maxLat = mid
                }
            }
            evenBit.toggle()
            bits += 1
            if bits == 5 {
                hash.append(base32[ch])
                bits = 0
                ch = 0
            }
        }
        return hash
    }

    /// Returns a `[start, end)` geohash prefix range that covers the lat/lng
    /// bounding box of a circle. Suitable for Firestore:
    /// `whereField("geohash", isGreaterThanOrEqualTo: start)`
    /// `whereField("geohash", isLessThan: end)`
    static func boundingRange(
        center: CLLocationCoordinate2D,
        radiusKm: Double,
        precision: Int = 9
    ) -> (start: String, end: String) {
        let kmPerDegLat = 111.0
        let cosLat = max(cos(center.latitude * .pi / 180), 0.0001)
        let dLat = radiusKm / kmPerDegLat
        let dLng = radiusKm / (kmPerDegLat * cosLat)

        let neHash = encode(
            latitude: center.latitude + dLat,
            longitude: center.longitude + dLng,
            precision: precision
        )
        let swHash = encode(
            latitude: center.latitude - dLat,
            longitude: center.longitude - dLng,
            precision: precision
        )
        let prefix = commonPrefix(neHash, swHash)
        if prefix.isEmpty {
            return ("", "~")
        }
        return (prefix, prefix + "~")
    }

    private static func commonPrefix(_ a: String, _ b: String) -> String {
        var out = ""
        for (ca, cb) in zip(a, b) {
            if ca != cb { break }
            out.append(ca)
        }
        return out
    }
}
