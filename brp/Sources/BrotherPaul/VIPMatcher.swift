import Foundation

/// Pure VIP-sender check used by GmailFetcher (matches against `from`) and
/// OutlookFetcher (matches against sender + subject). Empty vipSenders never
/// matches; empty entries inside vipSenders are skipped (so an accidental
/// blank in config doesn't behave like a wildcard).
enum VIPMatcher {

    static func isVIP(haystacks: [String], vipSenders: [String]) -> Bool {
        for vip in vipSenders {
            let v = vip.lowercased()
            guard !v.isEmpty else { continue }
            for haystack in haystacks {
                if haystack.lowercased().contains(v) { return true }
            }
        }
        return false
    }
}
