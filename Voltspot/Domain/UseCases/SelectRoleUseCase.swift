import Foundation

@MainActor
struct SelectRoleUseCase {
    let session: AppSession

    func callAsFunction(_ role: UserRole) {
        session.applyRole(role)
    }
}
