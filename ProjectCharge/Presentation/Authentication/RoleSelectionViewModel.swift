import Foundation
import Observation

@MainActor
@Observable
final class RoleSelectionViewModel {
    private let session: AppSession

    init(session: AppSession) {
        self.session = session
    }

    func select(_ role: UserRole) {
        SelectRoleUseCase(session: session)(role)
    }
}
