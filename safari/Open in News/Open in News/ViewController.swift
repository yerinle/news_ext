//
//  ViewController.swift
//  Open in News
//
//  Created by Yinka Erinle on 18/09/2026.
//

import Cocoa
import SafariServices
import WebKit

let extensionBundleIdentifier = "com.yinka.NewsOpen.Extension"

class ViewController: NSViewController, WKNavigationDelegate, WKScriptMessageHandler {

    @IBOutlet var webView: WKWebView!

    override func viewDidLoad() {
        super.viewDidLoad()

        self.webView.navigationDelegate = self

        self.webView.configuration.userContentController.add(self, name: "controller")

        self.webView.loadFileURL(Bundle.main.url(forResource: "Main", withExtension: "html")!, allowingReadAccessTo: Bundle.main.resourceURL!)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: extensionBundleIdentifier) { (state, error) in
            guard let state = state, error == nil else {
                // Insert code to inform the user that something went wrong.
                return
            }

            DispatchQueue.main.async {
                var useSettings = false
                if #available(macOS 13, *) { useSettings = true }
                webView.evaluateJavaScript("show(\(state.isEnabled), \(useSettings))") { _, _ in
                    self.fitWindowToContent()
                }
            }
        }
    }

    /// Grow the window to whatever the page actually renders. The body text
    /// changes with the extension's state and with Safari's naming ("Settings"
    /// on macOS 13+, "Preferences" before), and a fixed window sized for one
    /// wording leaves the button below the fold on another — unreachable,
    /// because the window is not scrolled to it.
    private func fitWindowToContent() {
        webView.evaluateJavaScript("document.documentElement.scrollHeight") { [weak self] result, _ in
            guard let self,
                  let height = (result as? NSNumber)?.doubleValue,
                  let window = self.view.window else { return }

            var size = window.contentLayoutRect.size
            guard height > size.height else { return }
            size.height = CGFloat(height)

            // Keep the title bar where it is rather than letting the window
            // grow downwards off the bottom of the screen.
            let top = window.frame.maxY
            window.setContentSize(size)
            window.setFrameTopLeftPoint(NSPoint(x: window.frame.origin.x, y: top))
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if (message.body as! String != "open-preferences") {
            return;
        }

        SFSafariApplication.showPreferencesForExtension(withIdentifier: extensionBundleIdentifier) { error in
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
        }
    }

}
