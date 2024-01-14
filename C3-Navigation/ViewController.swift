//
//  ViewController.swift
//  C3(X) Navigation
//
//  Created by Ethan Smith on 11/29/23.
//

import UIKit
import WebKit
import Network
import SystemConfiguration
import Photos
class ViewController: UIViewController {
    var webView: WKWebView!
    var isSearchTimedOut = false
	var isScanning = false
    var isDeviceFound = false
    var spinner: UIActivityIndicatorView!
    var statusLabel: UILabel!
    var refreshButton: UIButton!
    var ipLabel: UILabel!
    var retryButton: UIButton!
	var logTextView: UITextView!
	var logBuffer: [String] = []
	var logUpdateTimer: Timer?
	var downloadAlert: UIAlertController?
	var downloadTask: URLSessionDownloadTask?
    var downloadProgressLabel: UILabel?

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = UIColor.systemBackground
        webView.backgroundColor = UIColor.systemBackground
        webView.isOpaque = false
        setupSpinner()
        setupStatusLabel()
        setupRefreshButton()
        setupIPLabel()
        setupRetryButton()
		setupLogTextView()
		startLogUpdateTimer()
        webView.navigationDelegate = self
        DispatchQueue.global(qos: .background).async {
            self.startNetworkScan()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(appBecameActive), name: UIApplication.didBecomeActiveNotification, object: nil)
    }
    
	@objc func ipLabelTapped() {
		reinitializeFirstViewController()
	}
	
    override func loadView() {
        let webConfiguration = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: webConfiguration)
        view = webView
    }
    @objc func appBecameActive() {
        webView.reload()
    }
    @objc func refreshWebView() {
        webView.reload()
    }
    @objc func retryNetworkScan() {
        resetAppDataAndState()
        reinitializeFirstViewController()
        isSearchTimedOut = false
        startNetworkScan()
        retryButton.isHidden = true
        spinner.startAnimating()
        statusLabel.text = "Searching for devices..."
    }
    deinit {
        NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
		logUpdateTimer?.invalidate()
	}
	func startLogUpdateTimer() {
        logUpdateTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(updateLogView), userInfo: nil, repeats: true)
    }
    func resetAppDataAndState() {
        UserDefaults.standard.removePersistentDomain (forName: Bundle.main.bundleIdentifier!)
        UserDefaults.standard.synchronize()
    }
    func reinitializeFirstViewController() {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            let window = UIWindow(windowScene: windowScene)
            let storyboard = UIStoryboard(name: "LaunchScreen", bundle: nil)
            storyboard.instantiateInitialViewController()
            window.rootViewController = ViewController()
            window.makeKeyAndVisible()
            windowScene.windows.first?.rootViewController = ViewController()
              windowScene.windows.first?.makeKeyAndVisible()
        }
    }
    func startNetworkScan() {
        DispatchQueue.main.async {
            self.isDeviceFound = false
            self.isScanning = true
            self.scanNetworks()
        }
    }
    private func showRetryButton() {
        DispatchQueue.main.async {
            self.retryButton.isHidden = false
            self.statusLabel.text = "Connection Timed Out"
            self.spinner.stopAnimating()
        }
    }
    func completeScan() {
        DispatchQueue.main.async {
            if !self.isDeviceFound && self.isScanning {
                self.isSearchTimedOut = true
                self.showRetryButton()
                self.isScanning = false
                print("No devices found")
                self.appendLogMessage("No devices found")
                self.updateLogView()
            }
        }
    }
    func getActiveNetworkInterfaces() -> [String] {
        var interfaces = [String]()
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while ptr != nil {
                if let interface = ptr?.pointee, interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) || interface.ifa_addr.pointee.sa_family == UInt8(AF_INET6) {
                    let interfaceName = String(cString: interface.ifa_name, encoding: .utf8)
                    if let name = interfaceName, (name == "en0" || name == "bridge100") {
                        interfaces.append(name)
                    }
                }
                ptr = ptr?.pointee.ifa_next
            }
            freeifaddrs(ifaddr)
        }
        let uniqueInterfaces = removeDuplicateInterfaces(interfaces)
        return uniqueInterfaces
    }
        
    
    func getIPAddress(for interface: String) -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while ptr != nil {
                let flags = Int32((ptr?.pointee.ifa_flags ?? 0))
                let addr = ptr?.pointee.ifa_addr.pointee
                
                if (flags & (IFF_UP | IFF_RUNNING)) != 0 {
                    if addr?.sa_family == UInt8(AF_INET) {
                        let name: String = String(cString: (ptr?.pointee.ifa_name)!)
                        if name == interface {
                            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                            if let addr = ptr?.pointee.ifa_addr {
                                getnameinfo(addr, socklen_t(addr.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST)
                                address = String(cString: hostname)
                                print("IP Address for interface \(interface): \(address ?? "nil")")
                                self.appendLogMessage("IP Address for interface \(interface): \(address ?? "nil")")
                                self.updateLogView()
                            }
                            break
                        }
                    }
                }
                ptr = ptr?.pointee.ifa_next
            }
            freeifaddrs(ifaddr)
        }
        return address
    }
    private func removeDuplicateInterfaces(_ interfaces: [String]) -> [String] {
        var uniqueSet = Set<String>()
        var uniqueInterfaces = [String]()
        for interface in interfaces {
            if uniqueSet.insert(interface).inserted {
                uniqueInterfaces.append(interface)
            }
        }
        return uniqueInterfaces
    }
    
    private func scanNetworks() {
        let activeInterfaces = getActiveNetworkInterfaces()
        if let firstInterface = activeInterfaces.first {
            if let localIP = getIPAddress(for: firstInterface) {
                let ipRange = calculateSubnetRange(from: localIP)
                scanSubnetForService(ipRange: ipRange)
            }
        }
    }
    
    func calculateSubnetRange(from localIPAddress: String) -> [String] {
        let components = localIPAddress.split(separator: ".")
        guard components.count == 4 else { return [] }
        
        let subnetBase = components.dropLast().joined(separator: ".")
        return (1...254).map { "\(subnetBase).\($0)" }
    }
    
    private func scanSubnetForService(ipRange: [String]) {
        guard !ipRange.isEmpty && isScanning else {
            completeScan()
            return
        }
        self.isDeviceFound = false
        let totalSequenceRepeats = 1
        var currentCount = 0
        for _ in 0..<totalSequenceRepeats where !isDeviceFound {
            for ipAddress in ipRange {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.attemptConnection(ipAddress: ipAddress, port: 8082) { success in
                        if success {
                            self.isDeviceFound = true
                            self.isScanning = false
                            self.loadWebPage(with: ipAddress)
                            return
                        }
                    }
                }
            }
            currentCount += 1
            if currentCount == totalSequenceRepeats {
                DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                    self.completeScan()
                }
            }
        }
    }
    
    func attemptConnection(ipAddress: String, port: Int, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "http://\(ipAddress):\(port)") else {
            completion(false)
            return
        }
        print("Pinging \(ipAddress)...")
        self.appendLogMessage("Pinging \(ipAddress)...")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                completion(true)
                print("Device found at \(ipAddress)")
                self.appendLogMessage("Device found at \(ipAddress)")
                self.loadWebPage(with: ipAddress)
                self.isDeviceFound = true
            } else {
                completion(false)
                if !self.isDeviceFound {
                    print("Failed to connect to \(ipAddress)")
                    self.appendLogMessage("Failed to connect to \(ipAddress)")
                }
            }
        }
        task.resume()
    }
	
    private func loadWebPage(with ipAddress:String) {
        DispatchQueue.main.async {
            self.statusLabel.text = "Device found at \(ipAddress)..."
            self.retryButton.isHidden = true
            self.logTextView.isHidden = true
            self.spinner.startAnimating()
            self.ipLabel.text = "\(ipAddress)"
            let url = URL(string: "http://\(ipAddress):8082")!
            self.webView.load(URLRequest(url: url))
            self.webView.allowsBackForwardNavigationGestures = false
        }
        
    }
    private func setupSpinner() {
        DispatchQueue.main.async {
            self.spinner = UIActivityIndicatorView(style: .large)
            if self.traitCollection.userInterfaceStyle == .dark {
                self.spinner.color = .white
            } else {
                self.spinner.color = .black
            }
            self.spinner.isHidden = false
            self.spinner.center = self.view.center
            self.view.addSubview(self.spinner)
            self.spinner.startAnimating()
        }
    }
    private func setupStatusLabel() {
        DispatchQueue.main.async {
            self.statusLabel = UILabel()
            self.statusLabel.translatesAutoresizingMaskIntoConstraints = false
            self.statusLabel.textAlignment = .center
            if self.traitCollection.userInterfaceStyle == .dark {
                self.statusLabel.textColor = .white
            } else {
                self.statusLabel.textColor = .black
            }
            self.statusLabel.font = UIFont.systemFont(ofSize: 16)
            self.statusLabel.text = "Searching for devices..."
            self.view.addSubview(self.statusLabel)
            
            NSLayoutConstraint.activate([
                self.statusLabel.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
                self.statusLabel.centerYAnchor.constraint(equalTo: self.view.centerYAnchor, constant: -40),
                self.statusLabel.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 20),
                self.statusLabel.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -20)
            ])
        }
    }
    private func setupRefreshButton() {
        DispatchQueue.main.async {
            self.refreshButton = UIButton(type: .system)
            let refreshImage = UIImage(systemName: "arrow.clockwise")
            self.refreshButton.setImage(refreshImage, for: .normal)
            self.refreshButton.addTarget(self, action: #selector(self.refreshWebView), for: .touchUpInside)
            self.view.addSubview(self.refreshButton)
            self.refreshButton.translatesAutoresizingMaskIntoConstraints = false
            
            NSLayoutConstraint.activate([
                self.refreshButton.trailingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
                self.refreshButton.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
                self.refreshButton.widthAnchor.constraint(equalToConstant: 44),
                self.refreshButton.heightAnchor.constraint(equalToConstant: 44)
            ])
            self.refreshButton.isHidden = true
        }
    }
    private func setupIPLabel() {
        DispatchQueue.main.async {
            self.ipLabel = UILabel()
            self.ipLabel.textColor = self.view.tintColor
            self.ipLabel.textAlignment = .left
            self.ipLabel.font = UIFont.systemFont(ofSize: 16)
            self.view.addSubview(self.ipLabel)
            self.ipLabel.translatesAutoresizingMaskIntoConstraints = false
            
            NSLayoutConstraint.activate([
                self.ipLabel.leadingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
                self.ipLabel.bottomAnchor.constraint(equalTo: self.refreshButton.bottomAnchor),
                self.ipLabel.trailingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.trailingAnchor, constant: -20)
            ])
            self.ipLabel.isHidden = true
            
            // Make label user-interactive
            self.ipLabel.isUserInteractionEnabled = true
            
            // Add UITapGestureRecognizer to label
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.ipLabelTapped))
            self.ipLabel.addGestureRecognizer(tapGesture)
        }
    }

    private func setupRetryButton() {
        DispatchQueue.main.async {
            self.retryButton = UIButton(type: .system)
            self.retryButton.setTitle("Retry", for: .normal)
            self.retryButton.addTarget(self, action: #selector(self.retryNetworkScan), for: .touchUpInside)
            self.view.addSubview(self.retryButton)
            self.retryButton.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                self.retryButton.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
                self.retryButton.centerYAnchor.constraint(equalTo: self.view.centerYAnchor, constant: 20)
            ])
            self.retryButton.isHidden = true
        }
    }
	private func setupLogTextView() {
        DispatchQueue.main.async {
            self.logTextView = UITextView()
            self.logTextView.translatesAutoresizingMaskIntoConstraints = false
            self.logTextView.isEditable = false
            self.logTextView.isSelectable = false
            if self.traitCollection.userInterfaceStyle == .dark {
                self.logTextView.backgroundColor = UIColor.black
                self.logTextView.textColor = UIColor.white
            } else {
                self.logTextView.backgroundColor = UIColor.white
                self.logTextView.textColor = UIColor.black
            }
            self.logTextView.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            self.logTextView.textAlignment = .center
            self.view.addSubview(self.logTextView)
            NSLayoutConstraint.activate([
                self.logTextView.topAnchor.constraint(equalTo: self.retryButton.bottomAnchor, constant: 20),
                self.logTextView.leadingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.leadingAnchor, constant: 10),
                self.logTextView.trailingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.trailingAnchor, constant: -10),
                self.logTextView.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
            ])
        }
    }

    func appendLogMessage(_ message: String) {
        DispatchQueue.main.async {
            self.logBuffer.append(message)
            
            if self.logBuffer.count >= 100 {
                self.updateLogView()
            }
        }
    }
	@objc func updateLogView() {
		DispatchQueue.main.async {
			if !self.logBuffer.isEmpty {
				self.logTextView.text += self.logBuffer.joined(separator: "\n") + "\n"
				self.logBuffer.removeAll()
				self.scrollToBottom()
			}
		}
	}

	func scrollToBottom() {
		let bottomRange = NSRange(location: self.logTextView.text.count - 1, length: 1)
		self.logTextView.scrollRangeToVisible(bottomRange)
	}

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.async {
            self.statusLabel.text = ""
            self.spinner.stopAnimating()
            self.refreshButton.isHidden = false
            self.ipLabel.isHidden = false
            self.retryButton.isHidden = true
        }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!) {
        DispatchQueue.main.async {
            self.statusLabel.text = "Connection Timed Out"
            self.spinner.stopAnimating()
            self.retryButton.isHidden = false
        }
    }
}

extension ViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        
        print("URL clicked: \(url)")
        // Replace with your specific condition to identify the download link
        if url.absoluteString.contains("/full/") && url.absoluteString.contains("8082") {
            print("Download link detected, initiating download...")
            downloadAndSaveVideo(url: url)
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }
    private func downloadAndSaveVideo(url: URL) {
        showDownloadAlert()
        let configuration = URLSessionConfiguration.default
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: OperationQueue.main)
        let downloadTask = session.downloadTask(with: url) { [weak self] localURL, response, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Download error: \(error)")
                return
            }
            
            guard let localURL = localURL else {
                print("Local URL not found")
                return
            }
            
            // Rename the file with the .mp4 extension
            let fileManager = FileManager.default
            let directory = localURL.deletingLastPathComponent()
            let newURL = directory.appendingPathComponent(UUID().uuidString + ".mp4")
            do {
                try fileManager.moveItem(at: localURL, to: newURL)
                self.saveVideoToAlbum(localURL: newURL)
            } catch {
                print("Error moving and renaming file: \(error)")
            }
        }
        downloadTask.resume()
    }

    private func saveVideoToAlbum(localURL: URL) {
        PHPhotoLibrary.requestAuthorization { status in
            if status == .authorized {
                PHPhotoLibrary.shared().performChanges({
                    guard let assetChangeRequest = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: localURL) else {
                        print("Error: Could not create asset change request.")
                        return
                    }

                    let assetPlaceholder = assetChangeRequest.placeholderForCreatedAsset
                    let options = PHFetchOptions()
                    options.predicate = NSPredicate(format: "title = %@", "FleetCommander")
                    let collection = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: options)

                    let assetCollectionChangeRequest: PHAssetCollectionChangeRequest
                    
                    if let album = collection.firstObject {
                        assetCollectionChangeRequest = PHAssetCollectionChangeRequest(for: album)!
                    } else {
                        assetCollectionChangeRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: "FleetCommander")
                    }

                    assetCollectionChangeRequest.addAssets([assetPlaceholder!] as NSArray)

                }) { success, error in
                    if let error = error {
                        print("Error saving video to album: \(error)")
                    } else if success {
                        print("Video saved successfully")
                        DispatchQueue.main.async {
                            self.downloadAlert?.dismiss(animated: true, completion: nil)
                            self.showDownloadCompleteAlert()
                        }
                    }
                }
            } else {
                print("Photo library access not granted")
            }
        }
    }

	private func logError(_ error: Error, function: String, line: Int) {
		print("Error in \(function) at line \(line): \(error)")

		let nsError = error as NSError
        let userInfo = nsError.userInfo
		print("Error code: \(nsError.code)")
		print("Error domain: \(nsError.domain)")

        for (key, value) in userInfo {
				print("UserInfo \(key): \(value)")
		}
	}

    private func showDownloadAlert() {
        downloadAlert = UIAlertController(title: "Downloading...", message: "\n\n\n", preferredStyle: .alert)

        // Adjust the positions to place the label above the spinner
        downloadProgressLabel = UILabel(frame: CGRect(x: 20, y: 45, width: 230, height: 20))
        downloadProgressLabel?.textAlignment = .center
        downloadProgressLabel?.text = "0%"
        downloadAlert?.view.addSubview(downloadProgressLabel!)

        let spinner = UIActivityIndicatorView(style: .large)
        spinner.center = CGPoint(x: 135.0, y: 85.5) // Position adjusted
        spinner.startAnimating()
        downloadAlert?.view.addSubview(spinner)

        DispatchQueue.main.async {
            self.present(self.downloadAlert!, animated: true, completion: nil)
        }
    }
	
	private func showDownloadCompleteAlert() {
		let alert = UIAlertController(title: "Download Complete", message: "The video has been successfully downloaded and saved.", preferredStyle: .alert)
		alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
    
		DispatchQueue.main.async {
			self.present(alert, animated: true, completion: nil)
		}
	}
}
extension ViewController: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didResumeAtOffset fileOffset: Int64, expectedTotalBytes: Int64) {
        // Handle resume
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Handle the completion of the download
        // This is where you would move the file from the temporary location and handle it as needed
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let progress = Float(totalBytesWritten) / Float(totalBytesExpectedToWrite)
        DispatchQueue.main.async {
            self.downloadProgressLabel?.text = "\(Int(progress * 100))%"
        }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print("Download error: \(error)")
        }
    }
}
//testing
