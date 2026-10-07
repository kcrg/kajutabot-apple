import Foundation

protocol SessionStoring: Sendable {
    func load() throws -> UserSession?
    func save(_ session: UserSession) throws
    func clear() throws
}
