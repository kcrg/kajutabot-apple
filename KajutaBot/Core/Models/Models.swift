import Foundation

enum SearchSourceOption: String, CaseIterable, Identifiable, Sendable {
    case youtube = "YouTube"
    case soundCloud = "SoundCloud"
    case database = "Database"

    var id: String { rawValue }
    var displayName: LocalizedStringResource {
        switch self {
        case .youtube: .searchSourceYouTube
        case .soundCloud: .searchSourceSoundCloud
        case .database: .searchSourceDatabase
        }
    }
}

