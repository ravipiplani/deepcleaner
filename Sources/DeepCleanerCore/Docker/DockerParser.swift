import Foundation

/// Turns `docker system df -v --format json` output into reviewable resources.
public enum DockerParser {
    struct SystemDF: Decodable {
        var Images: [Image]?
        var Containers: [Container]?
        var Volumes: [Volume]?
        var BuildCache: [BuildRecord]?
    }

    struct Image: Decodable {
        var ID: String
        var Repository: String?
        var Tag: String?
        var Containers: String?
        var CreatedAt: String?
        var Size: String?
        var SharedSize: String?
        var UniqueSize: String?
    }

    struct Container: Decodable {
        var ID: String
        var Names: String?
        var Image: String?
        var State: String?
        var Status: String?
        var CreatedAt: String?
        var Size: String?
    }

    struct Volume: Decodable {
        var Name: String
        var Links: String?
        var Size: String?
        var Labels: String?
    }

    struct BuildRecord: Decodable {
        var InUse: String?
        var Size: String?
        var LastUsedAt: String?
    }

    public static func parseSystemDF(_ data: Data) throws -> [DockerResource] {
        let df = try JSONDecoder().decode(SystemDF.self, from: data)
        return containers(df.Containers ?? []) + images(df.Images ?? []) + volumes(df.Volumes ?? [])
            + buildCache(df.BuildCache ?? [])
    }

    static func images(_ rows: [Image]) -> [DockerResource] {
        // An image with several tags appears once per tag; they share one set of layers.
        var order: [String] = []
        var byID: [String: [Image]] = [:]
        for row in rows {
            if byID[row.ID] == nil { order.append(row.ID) }
            byID[row.ID, default: []].append(row)
        }
        return order.map { id in
            let rows = byID[id]!
            let first = rows[0]
            let tags = rows.compactMap { row -> String? in
                guard let repo = row.Repository, isSet(repo) else { return nil }
                guard let tag = row.Tag, isSet(tag) else { return repo }
                return "\(repo):\(tag)"
            }
            let short = shortID(id)
            let users = Int(first.Containers ?? "") ?? 0
            let unique = parseSize(first.UniqueSize)
            let total = parseSize(first.Size)
            let shared = parseSize(first.SharedSize)
            var detail = short
            if total > 0 { detail += " · \(formatted(total)) total" }
            if shared >= 1_000_000 { detail += ", \(formatted(shared)) shared with other images" }
            return DockerResource(
                kind: .image, key: id, refs: tags.isEmpty ? [id] : tags,
                name: tags.isEmpty ? "Untagged image" : tags.joined(separator: ", "),
                detail: detail,
                size: unique > 0 || shared > 0 ? unique : total,
                created: parseDate(first.CreatedAt),
                blockedReason: users > 0 ? "Used by \(plural(users, "container"))" : nil,
                selectedByDefault: tags.isEmpty
            )
        }
    }

    static func containers(_ rows: [Container]) -> [DockerResource] {
        rows.map { row in
            let state = (row.State ?? "").lowercased()
            let active = ["running", "paused", "restarting"].contains(state)
            let detail = [row.Image, row.Status].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            return DockerResource(
                kind: .container, key: row.ID, refs: [row.ID],
                name: row.Names.flatMap { $0.isEmpty ? nil : $0 } ?? shortID(row.ID),
                detail: detail,
                size: parseSize(row.Size),
                created: parseDate(row.CreatedAt),
                blockedReason: active ? "\(state.capitalized) — stop it first" : nil
            )
        }
    }

    static func volumes(_ rows: [Volume]) -> [DockerResource] {
        rows.map { row in
            let labels = parseLabels(row.Labels)
            let anonymous = labels["com.docker.volume.anonymous"] != nil || isHexID(row.Name)
            let users = Int(row.Links ?? "") ?? 0
            var detail = anonymous ? "Anonymous · \(String(row.Name.prefix(12)))" : "Named volume"
            if let builder = buildxBuilder(row.Name) {
                detail = "Build cache for buildx builder “\(builder)” · rebuilt on next build"
            }
            if let project = labels["com.docker.compose.project"] { detail += " · Compose project \(project)" }
            return DockerResource(
                kind: .volume, key: row.Name, refs: [row.Name],
                name: anonymous ? "Anonymous volume" : row.Name,
                detail: detail,
                size: parseSize(row.Size),
                blockedReason: users > 0 ? "Used by \(plural(users, "container"))" : nil
            )
        }
    }

    /// The CLI can only prune build cache wholesale, so it is offered as a single item.
    static func buildCache(_ rows: [BuildRecord]) -> [DockerResource] {
        guard !rows.isEmpty else { return [] }
        let idle = rows.filter { $0.InUse?.lowercased() != "true" }
        let size = idle.reduce(Int64(0)) { $0 + parseSize($1.Size) }
        let lastUsed = rows.compactMap { parseDate($0.LastUsedAt) }.max()
        return [DockerResource(
            kind: .buildCache, key: "all", refs: [],
            name: "Build cache",
            detail: "\(plural(rows.count, "record")) · rebuilt automatically the next time you build",
            size: size,
            created: lastUsed,
            blockedReason: idle.isEmpty ? "In use by a running build" : nil,
            selectedByDefault: true
        )]
    }

    // MARK: - Field parsing

    /// Parses Docker's human-readable sizes ("1.28GB", "24.32kB", "0B"). Docker uses decimal units.
    public static func parseSize(_ text: String?) -> Int64 {
        guard let text else { return 0 }
        let scanner = Scanner(string: text.trimmingCharacters(in: .whitespaces))
        guard let value = scanner.scanDouble() else { return 0 }
        let unit = (scanner.scanCharacters(from: .letters) ?? "B").lowercased()
        let multipliers: [String: Double] = [
            "b": 1, "kb": 1e3, "mb": 1e6, "gb": 1e9, "tb": 1e12, "pb": 1e15,
            "kib": 1_024, "mib": 1_048_576, "gib": 1_073_741_824, "tib": 1_099_511_627_776,
        ]
        guard let multiplier = multipliers[unit] else { return 0 }
        return Int64((value * multiplier).rounded())
    }

    /// Parses "2026-11-06 11:37:32 +0530 IST" and "2026-10-16 07:16:53.726917719 +0000 UTC".
    public static func parseDate(_ text: String?) -> Date? {
        guard let text else { return nil }
        let parts = text.split(separator: " ")
        guard parts.count >= 3 else { return nil }
        let time = parts[1].split(separator: ".")[0]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter.date(from: "\(parts[0]) \(time) \(parts[2])")
    }

    static func parseLabels(_ text: String?) -> [String: String] {
        guard let text, !text.isEmpty else { return [:] }
        var labels: [String: String] = [:]
        for pair in text.split(separator: ",") {
            let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            labels[String(kv[0])] = kv.count > 1 ? String(kv[1]) : ""
        }
        return labels
    }

    /// `docker buildx create` keeps each builder's cache in a volume named `buildx_buildkit_<name>0_state`.
    static func buildxBuilder(_ volume: String) -> String? {
        guard volume.hasPrefix("buildx_buildkit_"), volume.hasSuffix("_state") else { return nil }
        var name = volume.dropFirst("buildx_buildkit_".count).dropLast("_state".count)
        if name.last?.isNumber == true { name = name.dropLast() }
        return name.isEmpty ? nil : String(name)
    }

    static func isSet(_ value: String) -> Bool { !value.isEmpty && value != "<none>" }

    static func isHexID(_ name: String) -> Bool {
        name.count == 64 && name.allSatisfy(\.isHexDigit)
    }

    static func shortID(_ id: String) -> String {
        let bare = id.hasPrefix("sha256:") ? String(id.dropFirst(7)) : id
        return String(bare.prefix(12))
    }

    static func plural(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }

    static func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
