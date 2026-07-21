import Foundation

// the app <-> website pairing table. apple's tokens are opaque so the app can
// never read WHICH app the user picked — but the shield extension is handed the
// shielded app's real name/bundle id when it renders, and that's enough to match
// against this catalog and auto-block the matching site.
struct Platform: Identifiable, Hashable {
    let id: String
    let name: String
    let bundleIDs: [String]
    let domains: [String]

    static let all: [Platform] = [
        Platform(id: "instagram", name: "Instagram", bundleIDs: ["com.burbn.instagram"], domains: ["instagram.com"]),
        Platform(id: "tiktok", name: "TikTok", bundleIDs: ["com.zhiliaoapp.musically"], domains: ["tiktok.com"]),
        Platform(id: "x", name: "X", bundleIDs: ["com.atebits.Tweetie2"], domains: ["x.com", "twitter.com"]),
        Platform(id: "youtube", name: "YouTube", bundleIDs: ["com.google.ios.youtube"], domains: ["youtube.com", "youtu.be"]),
        Platform(id: "reddit", name: "Reddit", bundleIDs: ["com.reddit.Reddit"], domains: ["reddit.com"]),
        Platform(id: "snapchat", name: "Snapchat", bundleIDs: ["com.toyopagroup.picaboo"], domains: ["snapchat.com"]),
        Platform(id: "facebook", name: "Facebook", bundleIDs: ["com.facebook.Facebook"], domains: ["facebook.com"]),
        Platform(id: "threads", name: "Threads", bundleIDs: ["com.burbn.barcelona"], domains: ["threads.com", "threads.net"]),
        Platform(id: "pinterest", name: "Pinterest", bundleIDs: ["pinterest"], domains: ["pinterest.com"]),
        Platform(id: "linkedin", name: "LinkedIn", bundleIDs: ["com.linkedin.LinkedIn"], domains: ["linkedin.com"]),
        Platform(id: "twitch", name: "Twitch", bundleIDs: ["tv.twitch"], domains: ["twitch.tv"]),
        Platform(id: "discord", name: "Discord", bundleIDs: ["com.hammerandchisel.discord"], domains: ["discord.com"]),
        Platform(id: "tumblr", name: "Tumblr", bundleIDs: ["com.tumblr.tumblr"], domains: ["tumblr.com"]),
        Platform(id: "messenger", name: "Messenger", bundleIDs: ["com.facebook.Messenger"], domains: ["messenger.com"]),
        Platform(id: "whatsapp", name: "WhatsApp", bundleIDs: ["net.whatsapp.WhatsApp"], domains: ["web.whatsapp.com"]),
        Platform(id: "telegram", name: "Telegram", bundleIDs: ["ph.telegra.Telegraph"], domains: ["web.telegram.org"]),
        Platform(id: "bereal", name: "BeReal", bundleIDs: ["AlexisBarreyat.BeReal"], domains: ["bereal.com"]),
        Platform(id: "netflix", name: "Netflix", bundleIDs: ["com.netflix.Netflix"], domains: ["netflix.com"])
    ]

    static func byID(_ id: String) -> Platform? {
        all.first { $0.id == id }
    }

    // display names can carry aliases ("Twitter" for X) that bundle ids can't
    private static let nameAliases: [String: String] = ["twitter": "x"]

    static func match(bundleID: String?, name: String?) -> Platform? {
        if let bundleID, let hit = all.first(where: { $0.bundleIDs.contains(bundleID) }) {
            return hit
        }
        guard let name = name?.lowercased(), !name.isEmpty else { return nil }
        if let aliased = nameAliases[name] { return byID(aliased) }
        return all.first { $0.name.lowercased() == name }
    }
}
