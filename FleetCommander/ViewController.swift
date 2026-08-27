import UIKit
import WebKit
import Photos

final class ViewController: UIViewController {
    private var webView: WKWebView!
    private let connectionView = ConnectionView()
    private let connectedBar = ConnectedBarView()
    private let networkScanner = NetworkScanner()
    private var loadingTimer: Timer?
    private var currentAddress: String?
    private var currentPort: Int = AddressValidator.defaultPort
    private var lastAction: ConnectionAction = .discover
    private var downloadAlert: UIAlertController?
    private var downloadProgressLabel: UILabel?

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    private enum ConnectionAction {
        case discover
        case connect(address: String, port: Int)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = AppTheme.background
        AppTheme.apply()
        setupWebView()
        setupConnectionView()
        setupConnectedBar()
        networkScanner.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(appBecameActive), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if webView.url == nil || webView.url?.absoluteString == "about:blank" {
            connectionView.showHome()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        loadingTimer?.invalidate()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        view.endEditing(true)
    }

    private func setupWebView() {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.preferredContentMode = .mobile
        configuration.allowsInlineMediaPlayback = true

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.backgroundColor = AppTheme.background
        webView.isOpaque = true
        webView.navigationDelegate = self
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = false
        webView.scrollView.backgroundColor = AppTheme.background
        webView.allowsBackForwardNavigationGestures = false
        webView.setContentHuggingPriority(.defaultLow, for: .vertical)
        webView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    }

    private func setupConnectionView() {
        connectionView.translatesAutoresizingMaskIntoConstraints = false
        connectionView.delegate = self
        view.addSubview(connectionView)
        NSLayoutConstraint.activate([
            connectionView.topAnchor.constraint(equalTo: view.topAnchor),
            connectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            connectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            connectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    private func setupConnectedBar() {
        connectedBar.isHidden = true
        connectedBar.onRefresh = { [weak self] in self?.webView.reload() }
        connectedBar.onAddressTap = { [weak self] in self?.presentDeviceActions() }

        let chromeStack = UIStackView(arrangedSubviews: [connectedBar, webView])
        chromeStack.axis = .vertical
        chromeStack.spacing = 0
        chromeStack.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(chromeStack, at: 0)
        NSLayoutConstraint.activate([
            chromeStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            chromeStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            chromeStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            chromeStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)
        ])
    }

    private func connect(to address: String, port: Int, fromDiscovery: Bool) {
        lastAction = fromDiscovery ? .discover : .connect(address: address, port: port)
        currentAddress = address
        currentPort = port
        connectionView.prefill(address: address, port: port)
        connectionView.isHidden = false
        connectedBar.isHidden = true
        connectionView.showConnecting(address: address, port: port)
        loadWebPage(with: address, port: port)
    }

    private func returnHome() {
        loadingTimer?.invalidate()
        networkScanner.cancel()
        webView.stopLoading()
        webView.load(URLRequest(url: URL(string: "about:blank")!))
        connectedBar.isHidden = true
        connectionView.isHidden = false
        connectionView.showHome()
    }

    private func presentDeviceActions() {
        let sheet = UIAlertController(title: currentHostTitle, message: "You're connected to The Pond.", preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Refresh", style: .default) { [weak self] _ in
            self?.webView.reload()
        })
        sheet.addAction(UIAlertAction(title: "Disconnect", style: .default) { [weak self] _ in
            self?.returnHome()
        })
        sheet.addAction(UIAlertAction(title: "Forget this device", style: .destructive) { [weak self] _ in
            ConnectionStore.clear()
            self?.returnHome()
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = connectedBar
            popover.sourceRect = connectedBar.bounds
        }
        present(sheet, animated: true)
    }

    private var currentHostTitle: String {
        guard let address = currentAddress else { return "Device" }
        return "\(address):\(currentPort)"
    }

    @objc private func appBecameActive() {
        guard connectionView.isHidden,
              let url = webView.url,
              url.absoluteString != "about:blank" else { return }
        webView.reload()
    }
}

extension ViewController: ConnectionViewDelegate {
    func connectionViewDidReconnect(_ view: ConnectionView) {
        guard let saved = ConnectionStore.savedConnection else { return }
        connect(to: saved.address, port: saved.port, fromDiscovery: false)
    }

    func connectionViewDidStartDiscovery(_ view: ConnectionView) {
        lastAction = .discover
        connectionView.showSearching(status: "Searching this network")
        networkScanner.startNetworkScan()
    }

    func connectionViewDidConnect(_ view: ConnectionView, address: String, port: Int) {
        connect(to: address, port: port, fromDiscovery: false)
    }

    func connectionView(_ view: ConnectionView, didSelect device: DiscoveredDevice) {
        connect(to: device.address, port: device.port, fromDiscovery: true)
    }

    func connectionViewDidCancel(_ view: ConnectionView) {
        loadingTimer?.invalidate()
        networkScanner.cancel()
        webView.stopLoading()
        connectionView.showHome()
    }

    func connectionViewDidRetryDiscovery(_ view: ConnectionView) {
        switch lastAction {
        case .discover:
            connectionViewDidStartDiscovery(view)
        case .connect(let address, let port):
            connect(to: address, port: port, fromDiscovery: false)
        }
    }
}

extension ViewController: NetworkScannerDelegate {
    func showRetryButton() {
        DispatchQueue.main.async {
            self.connectionView.showFailed(
                title: "No Pond found",
                message: "Make sure this phone and your comma device are on the same Wi-Fi, and The Pond is running."
            )
        }
    }

    func appendLogMessage(_ message: String) {
        DispatchQueue.main.async {
            self.connectionView.appendLog(message)
        }
    }

    func updateLogView() {}

    func networkScanner(_ scanner: NetworkScanner, didDiscover devices: [DiscoveredDevice], ignoredOpenPorts: Int) {
        DispatchQueue.main.async {
            if devices.isEmpty {
                let extra = ignoredOpenPorts > 0
                    ? " Found \(ignoredOpenPorts) other device\(ignoredOpenPorts == 1 ? "" : "s") on port 8082 that weren’t The Pond."
                    : ""
                self.connectionView.showFailed(
                    title: "No Pond found",
                    message: "Make sure this phone and your comma device are on the same Wi-Fi, and The Pond is running.\(extra)"
                )
                return
            }
            if devices.count == 1 {
                let device = devices[0]
                self.loadWebPage(with: device.address, port: device.port)
                return
            }
            self.connectionView.showPicker(devices: devices)
        }
    }

    func loadWebPage(with address: String, port: Int) {
        DispatchQueue.main.async {
            self.currentAddress = address
            self.currentPort = port
            self.connectionView.isHidden = false
            self.connectedBar.isHidden = true
            self.connectionView.showConnecting(address: address, port: port)
            guard let url = URL(string: "http://\(address):\(port)") else {
                self.connectionView.showFailed(title: "Invalid address", message: "Could not open \(address):\(port).")
                return
            }
            self.webView.load(URLRequest(url: url))
            self.startLoadingTimer(for: address, port: port)
        }
    }
}

private extension ViewController {
    func startLoadingTimer(for address: String, port: Int) {
        loadingTimer?.invalidate()
        loadingTimer = Timer.scheduledTimer(withTimeInterval: 12.0, repeats: false) { [weak self] _ in
            self?.handleTimeout(for: address, port: port)
        }
    }

    func handleTimeout(for address: String, port: Int) {
        DispatchQueue.main.async {
            if self.webView.isLoading {
                self.webView.stopLoading()
                self.handleConnectionFailure(for: address, port: port)
            }
        }
    }

    func handleConnectionFailure(for address: String, port: Int) {
        loadingTimer?.invalidate()
        lastAction = .connect(address: address, port: port)
        connectionView.prefill(address: address, port: port)
        connectionView.isHidden = false
        connectedBar.isHidden = true
        connectionView.showFailed(
            title: "Couldn’t connect",
            message: "Failed to reach \(address):\(port). Check the address, port, and Wi-Fi, then try again."
        )
    }

    func markConnected() {
        loadingTimer?.invalidate()
        if let address = currentAddress {
            ConnectionStore.save(address: address, port: currentPort)
            connectedBar.setAddress("\(address):\(currentPort)")
        }
        connectionView.isHidden = true
        connectedBar.isHidden = false
    }

    private func applyPondLayoutFixes() {
        let script = """
        (function() {
          var style = document.getElementById('lilypad-mobile');
          if (!style) {
            style = document.createElement('style');
            style.id = 'lilypad-mobile';
            document.documentElement.appendChild(style);
          }
          style.textContent = [
            'html, body { background-color: #0b1b0b !important; }',
            '#menu_button { bottom: 1rem !important; right: 1rem !important; }',
            '.sidebar { top: 0 !important; height: 100% !important; }'
          ].join('\\n');
        })();
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }
}

extension ViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView.url?.absoluteString != "about:blank" else { return }
        applyPondLayoutFixes()
        markConnected()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
        handleConnectionFailure(for: currentAddress ?? webView.url?.host ?? "unknown", port: currentPort)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
        handleConnectionFailure(for: currentAddress ?? webView.url?.host ?? "unknown", port: currentPort)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        if url.absoluteString.contains("/full/") || url.absoluteString.contains("/download/") {
            downloadAndSaveVideo(url: url)
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }

    private func downloadAndSaveVideo(url: URL) {
        showDownloadAlert()
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        let task = session.downloadTask(with: url) { [weak self] localURL, _, error in
            guard let self else { return }
            if let error {
                self.finishDownload(success: false, message: error.localizedDescription)
                return
            }
            guard let localURL else {
                self.finishDownload(success: false, message: "The download did not finish.")
                return
            }
            let newURL = localURL.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".mp4")
            do {
                try FileManager.default.moveItem(at: localURL, to: newURL)
                self.saveVideoToAlbum(localURL: newURL)
            } catch {
                self.finishDownload(success: false, message: error.localizedDescription)
            }
        }
        task.resume()
    }

    private func saveVideoToAlbum(localURL: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    self.finishDownload(success: false, message: "Allow photo access to save videos.")
                }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                guard let assetChangeRequest = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: localURL),
                      let placeholder = assetChangeRequest.placeholderForCreatedAsset else { return }
                let options = PHFetchOptions()
                options.predicate = NSPredicate(format: "title = %@", "LilyPad")
                let collection = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: options)
                let albumRequest: PHAssetCollectionChangeRequest
                if let album = collection.firstObject {
                    albumRequest = PHAssetCollectionChangeRequest(for: album)!
                } else {
                    albumRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: "LilyPad")
                }
                albumRequest.addAssets([placeholder] as NSArray)
            }) { success, error in
                DispatchQueue.main.async {
                    if success {
                        self.finishDownload(success: true, message: "Saved to your LilyPad album.")
                    } else {
                        self.finishDownload(success: false, message: error?.localizedDescription ?? "Could not save the video.")
                    }
                }
            }
        }
    }

    private func showDownloadAlert() {
        let alert = UIAlertController(title: "Downloading video", message: "\n\n", preferredStyle: .alert)
        let label = UILabel(frame: CGRect(x: 20, y: 56, width: 230, height: 20))
        label.textAlignment = .center
        label.font = UIFont.monospacedDigitSystemFont(ofSize: 15, weight: .medium)
        label.textColor = .secondaryLabel
        label.text = "0%"
        alert.view.addSubview(label)
        downloadProgressLabel = label
        downloadAlert = alert
        present(alert, animated: true)
    }

    private func finishDownload(success: Bool, message: String) {
        downloadAlert?.dismiss(animated: true) {
            let alert = UIAlertController(
                title: success ? "Download complete" : "Download failed",
                message: message,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(alert, animated: true)
        }
        downloadAlert = nil
    }
}

extension ViewController: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Float(totalBytesWritten) / Float(totalBytesExpectedToWrite)
        downloadProgressLabel?.text = "\(Int(progress * 100))%"
    }
}

final class ConnectedBarView: UIView {
    var onRefresh: (() -> Void)?
    var onAddressTap: (() -> Void)?

    private let logoView = UIImageView(image: UIImage(named: "LilyPad"))
    private let addressButton = UIButton(type: .system)
    private let refreshButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = AppTheme.surface

        logoView.translatesAutoresizingMaskIntoConstraints = false
        logoView.contentMode = .scaleAspectFit

        var addressConfig = UIButton.Configuration.plain()
        addressConfig.baseForegroundColor = AppTheme.text
        addressConfig.titleAlignment = .leading
        addressConfig.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)
        addressConfig.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.systemFont(ofSize: 11, weight: .regular)
            outgoing.foregroundColor = AppTheme.textMuted
            return outgoing
        }
        addressConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium)
            outgoing.foregroundColor = AppTheme.text
            return outgoing
        }
        addressButton.configuration = addressConfig
        addressButton.addTarget(self, action: #selector(addressTapped), for: .touchUpInside)
        addressButton.contentHorizontalAlignment = .leading

        var refreshConfig = UIButton.Configuration.plain()
        refreshConfig.image = UIImage(systemName: "arrow.clockwise")
        refreshConfig.baseForegroundColor = AppTheme.accentBright
        refreshButton.configuration = refreshConfig
        refreshButton.addTarget(self, action: #selector(refreshTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [logoView, addressButton, refreshButton])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            logoView.widthAnchor.constraint(equalToConstant: 32),
            logoView.heightAnchor.constraint(equalToConstant: 32),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            refreshButton.widthAnchor.constraint(equalToConstant: 40),
            refreshButton.heightAnchor.constraint(equalToConstant: 40),
            heightAnchor.constraint(equalToConstant: 48)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setAddress(_ text: String) {
        var config = addressButton.configuration
        config?.title = text
        config?.subtitle = "Tap to change device"
        addressButton.configuration = config
        addressButton.accessibilityHint = "Opens options to disconnect or forget this device"
    }

    @objc private func addressTapped() { onAddressTap?() }
    @objc private func refreshTapped() { onRefresh?() }
}
