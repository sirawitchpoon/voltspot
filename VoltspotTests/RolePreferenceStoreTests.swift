import XCTest
@testable import Voltspot

final class RolePreferenceStoreTests: XCTestCase {

    private func makeIsolatedDefaults() -> UserDefaults {
        let suite = "RolePreferenceStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testRoundTripConsumer() {
        let store = RolePreferenceStore(defaults: makeIsolatedDefaults())
        XCTAssertNil(store.loadRole())

        store.saveRole(.consumer)
        XCTAssertEqual(store.loadRole(), .consumer)
    }

    func testOverwriteSwitchesRole() {
        let store = RolePreferenceStore(defaults: makeIsolatedDefaults())
        store.saveRole(.consumer)
        store.saveRole(.partner)
        XCTAssertEqual(store.loadRole(), .partner)
    }

    func testClearRoleRemovesValue() {
        let store = RolePreferenceStore(defaults: makeIsolatedDefaults())
        store.saveRole(.partner)
        store.clearRole()
        XCTAssertNil(store.loadRole())
    }
}
