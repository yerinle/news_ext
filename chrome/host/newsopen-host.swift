//
//  newsopen-host.swift
//
//  Native messaging host for the Chrome extension, and a small CLI.
//
//  Chrome extensions cannot reach AppKit, so the extension hands a URL to this
//  process, which passes it to the system "Open in News" share service — the
//  only mechanism that resolves a publisher web URL to its Apple News+ article.
//
//  Protocol (Chrome native messaging): a 4-byte native-endian length prefix
//  followed by that many bytes of UTF-8 JSON, in both directions. sendNativeMessage
//  delivers exactly one message per launch, so we handle one and exit.
//
//  CLI usage:  newsopen-host --open <url>
//

import AppKit

// MARK: - Opening

final class Opener: NSObject, NSSharingServiceDelegate {
    private var service: NSSharingService?
    private var done: ((Bool, String?) -> Void)?
    private var finished = false

    /// Locates the News share extension. Matched by title because the service
    /// carries no stable public identifier; the loose match keeps this working
    /// on non-English systems, where the title is localized.
    static func newsService(for url: URL) -> NSSharingService? {
        let services = NSSharingService.sharingServices(forItems: [url])
        if let exact = services.first(where: { $0.title == "Open in News" }) {
            return exact
        }
        return services.first { $0.title.localizedCaseInsensitiveContains("News") }
    }

    func open(_ url: URL, completion: @escaping (Bool, String?) -> Void) {
        guard let svc = Opener.newsService(for: url) else {
            completion(false, "The “Open in News” share service is unavailable.")
            return
        }
        done = completion
        service = svc
        svc.delegate = self
        svc.perform(withItems: [url])

        // perform() is asynchronous; give it a ceiling so we can never hang.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.settle(true, nil)
        }
    }

    func sharingService(_ s: NSSharingService, didShareItems items: [Any]) {
        settle(true, nil)
    }

    func sharingService(_ s: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        settle(false, error.localizedDescription)
    }

    private func settle(_ ok: Bool, _ error: String?) {
        guard !finished else { return }
        finished = true
        done?(ok, error)
        done = nil
    }
}

// MARK: - Native messaging framing

func readExactly(_ count: Int) -> Data? {
    var data = Data()
    while data.count < count {
        guard let chunk = try? FileHandle.standardInput.read(upToCount: count - data.count),
              !chunk.isEmpty else { return nil }
        data.append(chunk)
    }
    return data
}

func writeMessage(_ object: [String: Any]) {
    guard let body = try? JSONSerialization.data(withJSONObject: object) else { return }
    var length = UInt32(body.count)
    var out = Data(bytes: &length, count: 4)
    out.append(body)
    FileHandle.standardOutput.write(out)
}

func respondAndExit(ok: Bool, error: String?) -> Never {
    var payload: [String: Any] = ["ok": ok]
    if let error { payload["error"] = error }
    writeMessage(payload)
    exit(ok ? 0 : 1)
}

// MARK: - Entry point

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let opener = Opener()

let args = CommandLine.arguments

// CLI mode: newsopen-host --open <url>
if args.count >= 3, args[1] == "--open" {
    guard let url = URL(string: args[2]), url.scheme == "http" || url.scheme == "https" else {
        FileHandle.standardError.write(Data("not an http(s) URL: \(args[2])\n".utf8))
        exit(2)
    }
    opener.open(url) { ok, error in
        if let error { FileHandle.standardError.write(Data("\(error)\n".utf8)) }
        exit(ok ? 0 : 1)
    }
    RunLoop.main.run(until: Date().addingTimeInterval(8))
    exit(0)
}

// Native messaging mode.
guard let header = readExactly(4) else { exit(0) }   // Chrome closed the pipe
let length = header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
guard length > 0, length < 1_000_000, let body = readExactly(Int(length)) else {
    respondAndExit(ok: false, error: "Malformed native message.")
}

guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
      (json["action"] as? String) == "open",
      let urlString = json["url"] as? String,
      let url = URL(string: urlString),
      url.scheme == "http" || url.scheme == "https" else {
    respondAndExit(ok: false, error: "Malformed request.")
}

opener.open(url) { ok, error in
    respondAndExit(ok: ok, error: error)
}
RunLoop.main.run(until: Date().addingTimeInterval(8))
respondAndExit(ok: true, error: nil)
