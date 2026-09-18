//
//  SafariWebExtensionHandler.swift
//  Open in News Extension
//

import SafariServices
import AppKit
import os.log

private let log = OSLog(subsystem: "com.yinka.NewsOpen", category: "handler")

/// Receives a URL from the web extension and hands it to the system
/// "Open in News" share service, which is the only mechanism that actually
/// resolves a publisher web URL to its Apple News+ article. (The applenews://
/// and applenewss:// URL schemes merely launch the app on the Today screen.)
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling, NSSharingServiceDelegate {

    private var extensionContext: NSExtensionContext?
    private var service: NSSharingService?   // held so it outlives beginRequest
    private var finished = false

    func beginRequest(with context: NSExtensionContext) {
        self.extensionContext = context

        let request = context.inputItems.first as? NSExtensionItem
        let message: Any?
        if #available(macOS 11.0, *) {
            message = request?.userInfo?[SFExtensionMessageKey]
        } else {
            message = request?.userInfo?["message"]
        }

        guard let payload = message as? [String: Any],
              (payload["action"] as? String) == "open",
              let urlString = payload["url"] as? String,
              let url = URL(string: urlString),
              url.scheme == "http" || url.scheme == "https" else {
            finish(["ok": false, "error": "Malformed request."])
            return
        }

        guard let newsService = Self.openInNewsService(for: url) else {
            os_log(.error, log: log, "Open in News share service not found")
            finish(["ok": false, "error": "The “Open in News” share service is unavailable."])
            return
        }

        os_log(.default, log: log, "Handing off to News: %{public}@", url.absoluteString)
        service = newsService
        newsService.delegate = self
        newsService.perform(withItems: [url])

        // perform() is asynchronous and the extension may be torn down as soon as
        // the request completes, so hold the request open until the delegate
        // reports back — with a ceiling so we can never hang.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.finish(["ok": true, "note": "completed without delegate callback"])
        }
    }

    /// Locates the News share extension. Matched by title because the service
    /// carries no stable public identifier; the loose match keeps this working
    /// on non-English systems, where the title is localized.
    private static func openInNewsService(for url: URL) -> NSSharingService? {
        let services = NSSharingService.sharingServices(forItems: [url])
        if let exact = services.first(where: { $0.title == "Open in News" }) {
            return exact
        }
        return services.first { $0.title.localizedCaseInsensitiveContains("News") }
    }

    // MARK: NSSharingServiceDelegate

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        // Note: News reports success even when it has no article for the URL and
        // simply shows the Today screen. There is no signal to distinguish the
        // two, which is why the extension never closes the browser tab.
        finish(["ok": true])
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        os_log(.error, log: log, "Share failed: %{public}@", error.localizedDescription)
        finish(["ok": false, "error": error.localizedDescription])
    }

    // MARK: -

    private func finish(_ payload: [String: Any]) {
        guard !finished else { return }
        finished = true

        let response = NSExtensionItem()
        if #available(macOS 11.0, *) {
            response.userInfo = [SFExtensionMessageKey: payload]
        } else {
            response.userInfo = ["message": payload]
        }
        extensionContext?.completeRequest(returningItems: [response], completionHandler: nil)
        extensionContext = nil
    }
}
