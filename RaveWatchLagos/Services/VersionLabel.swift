import Foundation

/// Version label, ported from `lib/widgets/version_label.dart`.
///
/// "0.9.0" → "Version 9.0"; "0.8.9" → "Version 8.9";
/// "1.0.0" → "Version 1.0"; "2.0.0" → "Version 2.0 Beta";
/// anything else shown as-is.
///
/// Beta branding is a rule, not a list: every package version on the
/// 2.0+ line is Beta, judged on the RAW package version. The 0.x
/// packages display publicly as 8.x/9.x but predate the branding, as
/// do the 1.x packages — those stay plain.
///
/// This build is 5.0.8 (build 97) — the same as the Android app —
/// so the label reads "Version 5.0.8 Beta".
enum VersionLabel {
    static func formatVersionLabel(_ version: String) -> String {
        let v = version.trimmingCharacters(in: .whitespaces)
        let display: String
        if v.hasPrefix("0.") {
            display = String(v.dropFirst(2))
        } else {
            let parts = v.split(separator: ".")
            if parts.count == 3 && parts[2] == "0" {
                display = "\(parts[0]).\(parts[1])"
            } else {
                display = v
            }
        }
        let rawMajor = Int(v.split(separator: ".").first ?? "0") ?? 0
        return rawMajor >= 2 ? "Version \(display) Beta" : "Version \(display)"
    }

    /// The label for this build, from the bundle's real version —
    /// never a hardcoded string.
    static var current: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "5.0.8"
        return formatVersionLabel(version)
    }

    /// "5.0.8 (97)" — the raw version + build, for diagnostics.
    static var raw: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "5.0.8"
        let build = info?["CFBundleVersion"] as? String ?? "97"
        return "\(version) (\(build))"
    }
}
