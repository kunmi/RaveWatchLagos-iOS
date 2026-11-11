import Foundation
import UIKit

/// Bug reports, ported from `lib/services/bug_report.dart`.
///
/// Settings keeps two separate doors: "Send feedback" (a plain mailto)
/// and "Report a bug" — a bug report needs facts, not impressions, so
/// the composed email carries the app version, phone and OS version
/// plus prompts (What happened / What did you expect / Which event).
/// If gathering the details fails, the report still opens, marked
/// "unknown". On iOS the diagnostics say iPhone / iOS version instead
/// of the Android phone / Android version.
enum BugReport {
    static let reportEmail = "ravewatchlagos@gmail.com"
    static let feedbackSubject = "RaveWatchLagos feedback"

    struct Diagnostics {
        let appVersion: String
        let deviceModel: String
        let osVersion: String
    }

    static func gatherDiagnostics() -> Diagnostics {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info?["CFBundleVersion"] as? String ?? "unknown"
        return Diagnostics(
            appVersion: "\(version) (\(build))",
            deviceModel: UIDevice.current.model,
            osVersion: "iOS \(UIDevice.current.systemVersion)"
        )
    }

    /// The bug-report mailto, with prompts + a diagnostics block.
    static func bugReportMailto(_ diagnostics: Diagnostics) -> URL? {
        let subject = "Bug report — \(diagnostics.appVersion)"
        let body = """
        What happened?

        What did you expect?

        Which event?


        ---
        App version: \(diagnostics.appVersion)
        Phone model: \(diagnostics.deviceModel)
        iOS version: \(diagnostics.osVersion)
        """
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = reportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url
    }

    static func feedbackMailto() -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = reportEmail
        components.queryItems = [URLQueryItem(name: "subject", value: feedbackSubject)]
        return components.url
    }
}
