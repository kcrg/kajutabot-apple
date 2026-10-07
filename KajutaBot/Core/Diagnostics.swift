import Foundation
import Sentry

/// Only static, developer-authored events. Never pass URLs, tokens, queries or
/// server-provided error messages. Optional DSN is supplied by the build settings.
enum Diagnostics {
    static func bootstrap() {
        guard let dsn = Bundle.main.object(forInfoDictionaryKey: "KAJUTABOT_SENTRY_DSN") as? String,
              !dsn.isEmpty, !dsn.contains("$(") else { return }
        SentrySDK.start { options in
            options.dsn = dsn
            options.sendDefaultPii = false
            options.enableMemoryIntrospection = false
            options.enableNetworkBreadcrumbs = false
            options.enableNetworkTracking = false
            options.enableCaptureFailedRequests = false
            options.tracePropagationTargets = []
            options.enableAutoBreadcrumbTracking = false
            options.attachScreenshot = false
            options.attachViewHierarchy = false
            options.tracesSampleRate = 0
            options.beforeBreadcrumb = { breadcrumb in
                let category: String? = breadcrumb.category
                return category?.hasPrefix("kajutabot.") == true ? breadcrumb : nil
            }
        }
    }

    static func trace(_ label: StaticString, _ message: StaticString) { record(label, message, level: .debug) }
    static func debug(_ label: StaticString, _ message: StaticString) { record(label, message, level: .debug) }
    static func info(_ label: StaticString, _ message: StaticString) { record(label, message, level: .info) }
    static func warning(_ label: StaticString, _ message: StaticString) { record(label, message, level: .warning) }
    static func error(_ label: StaticString, _ message: StaticString) {
        record(label, message, level: .error)
        SentrySDK.capture(message: String(describing: message))
    }

    private static func record(_ label: StaticString, _ message: StaticString, level: SentryLevel) {
        let breadcrumb = Breadcrumb(level: level, category: "kajutabot." + String(describing: label))
        breadcrumb.message = String(describing: message)
        SentrySDK.addBreadcrumb(breadcrumb)
    }
}
