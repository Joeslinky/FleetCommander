//  ViewController.swift
//  C3-Navigation
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
    var networkScanner: NetworkScanner!
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
    var manualIPTextField: UITextField!
    var manualIPButton: UIButton!
    var autodiscoveryButton: UIButton!
    var rememberIPSwitch: UISwitch!
    var initialOptionsView: UIView!
    var forgetIPButton: UIButton!
    var savedIPLabel: UILabel!
    var rememberIPLabel: UILabel!
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupInitialOptionsView()
        setupSpinner()
        setupStatusLabel()
        setupRefreshButton()
        setupIPLabel()
        setupRetryButton()
        setupLogTextView()
        setupForgetIPButton()
        setupSavedIPLabel()
        
        networkScanner = NetworkScanner()
        networkScanner.viewController = self
        networkScanner.delegate = self
        manualIPTextField.delegate = self

        initialOptionsView.isUserInteractionEnabled = true
        
        startLogUpdateTimer()
        
        NotificationCenter.default.addObserver(self, selector: #selector(appBecameActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        
        let webConfiguration = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: webConfiguration)
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        view.sendSubviewToBack(webView)
        
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: self.view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor)
        ])
        
        self.view.backgroundColor = UIColor.systemBackground
        webView.backgroundColor = UIColor.systemBackground
        webView.isOpaque = false
        webView.navigationDelegate = self
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = false
        webView.scrollView.delegate = self
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if let savedIP = UserDefaults.standard.string(forKey: "SavedIPAddress") {
            connectToIP(savedIP)
        } else {
            showInitialOptions()
        }
    }
    private func setupInitialOptionsView() {
        initialOptionsView = UIView()
        initialOptionsView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(initialOptionsView)
    
        let choiceLabel = UILabel()
        choiceLabel.text = "Choose connection method:"
        choiceLabel.textColor = .black
        choiceLabel.translatesAutoresizingMaskIntoConstraints = false
        initialOptionsView.addSubview(choiceLabel)
    
        let configureButton: (UIButton, String) -> Void = { button, title in
            var configuration = UIButton.Configuration.filled()
            configuration.title = title
            configuration.baseBackgroundColor = .systemBlue
            configuration.baseForegroundColor = .white
            configuration.cornerStyle = .medium
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
            button.configuration = configuration
            button.layer.cornerRadius = 15
            button.clipsToBounds = true
        }
    
        autodiscoveryButton = UIButton(type: .system)
        configureButton(autodiscoveryButton, "Auto-Discovery")
        autodiscoveryButton.addTarget(self, action: #selector(autodiscoveryButtonTapped), for: .touchUpInside)
        autodiscoveryButton.translatesAutoresizingMaskIntoConstraints = false
        initialOptionsView.addSubview(autodiscoveryButton)
    
        manualEntryButton = UIButton(type: .system)
        configureButton(manualEntryButton, "Manual IP Entry")
        manualEntryButton.addTarget(self, action: #selector(showManualIPEntry), for: .touchUpInside)
        manualEntryButton.translatesAutoresizingMaskIntoConstraints = false
        initialOptionsView.addSubview(manualEntryButton)
    
        manualIPTextField = UITextField()
        manualIPTextField.placeholder = "Enter IP Address"
        manualIPTextField.borderStyle = .roundedRect
        manualIPTextField.translatesAutoresizingMaskIntoConstraints = false
        manualIPTextField.isHidden = true
        manualIPTextField.delegate = self
        initialOptionsView.addSubview(manualIPTextField)
    
        manualIPButton = UIButton(type: .system)
        configureButton(manualIPButton, "Connect")
        manualIPButton.addTarget(self, action: #selector(manualIPButtonTapped), for: .touchUpInside)
        manualIPButton.translatesAutoresizingMaskIntoConstraints = false
        manualIPButton.isHidden = true
        initialOptionsView.addSubview(manualIPButton)
    
        rememberIPSwitch = UISwitch()
        rememberIPSwitch.translatesAutoresizingMaskIntoConstraints = false
        rememberIPSwitch.isHidden = true
        initialOptionsView.addSubview(rememberIPSwitch)
    
        rememberIPLabel = UILabel()
        rememberIPLabel.text = "Remember IP"
        rememberIPLabel.textColor = .black
        rememberIPLabel.translatesAutoresizingMaskIntoConstraints = false
        rememberIPLabel.isHidden = true
        initialOptionsView.addSubview(rememberIPLabel)
    
        NSLayoutConstraint.activate([
            initialOptionsView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            initialOptionsView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            initialOptionsView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.8),
    
            choiceLabel.topAnchor.constraint(equalTo: initialOptionsView.topAnchor),
            choiceLabel.centerXAnchor.constraint(equalTo: initialOptionsView.centerXAnchor),
    
            autodiscoveryButton.topAnchor.constraint(equalTo: choiceLabel.bottomAnchor, constant: 20),
            autodiscoveryButton.centerXAnchor.constraint(equalTo: initialOptionsView.centerXAnchor),
    
            manualEntryButton.topAnchor.constraint(equalTo: autodiscoveryButton.bottomAnchor, constant: 20),
            manualEntryButton.centerXAnchor.constraint(equalTo: initialOptionsView.centerXAnchor),
    
            manualIPTextField.topAnchor.constraint(equalTo: manualEntryButton.bottomAnchor, constant: 20),
            manualIPTextField.leadingAnchor.constraint(equalTo: initialOptionsView.leadingAnchor),
            manualIPTextField.trailingAnchor.constraint(equalTo: initialOptionsView.trailingAnchor),
    
            manualIPButton.topAnchor.constraint(equalTo: manualIPTextField.bottomAnchor, constant: 10),
            manualIPButton.centerXAnchor.constraint(equalTo: initialOptionsView.centerXAnchor),
    
            rememberIPSwitch.topAnchor.constraint(equalTo: manualIPButton.bottomAnchor, constant: 10),
            rememberIPSwitch.leadingAnchor.constraint(equalTo: initialOptionsView.leadingAnchor),
    
            rememberIPLabel.centerYAnchor.constraint(equalTo: rememberIPSwitch.centerYAnchor),
            rememberIPLabel.leadingAnchor.constraint(equalTo: rememberIPSwitch.trailingAnchor, constant: 10)
        ])

        view.bringSubviewToFront(autodiscoveryButton)
        view.bringSubviewToFront(manualEntryButton)
    
        initialOptionsView.isHidden = false
    }
    
    @objc func showManualIPEntry() {
        manualIPTextField.isHidden = false
        manualIPButton.isHidden = false
        rememberIPSwitch.isHidden = false
        rememberIPLabel.isHidden = false
        autodiscoveryButton.isHidden = true
        view.bringSubviewToFront(manualIPTextField)
        view.bringSubviewToFront(rememberIPSwitch)
    }

    private func setupForgetIPButton() {
        forgetIPButton = UIButton(type: .system)
        forgetIPButton.setTitle("Forget Saved IP", for: .normal)
        forgetIPButton.addTarget(self, selector: #selector(forgetIPButtonTapped), for: .touchUpInside)
        forgetIPButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(forgetIPButton)

        NSLayoutConstraint.activate([
            forgetIPButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            forgetIPButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
        
        forgetIPButton.isHidden = true
    }

    private func setupSavedIPLabel() {
        savedIPLabel = UILabel()
        savedIPLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(savedIPLabel)

        NSLayoutConstraint.activate([
            savedIPLabel.topAnchor.constraint(equalTo: forgetIPButton.bottomAnchor, constant: 10),
            savedIPLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
        
        savedIPLabel.isHidden = true
    }

    @objc func forgetIPButtonTapped() {
        UserDefaults.standard.removeObject(forKey: "SavedIPAddress")
        showInitialOptions()
    }
    
    func showInitialOptions() {
        initialOptionsView.isHidden = false
        webView.isHidden = true
        spinner.isHidden = true
        statusLabel.isHidden = true
        refreshButton.isHidden = true
        ipLabel.isHidden = true
        retryButton.isHidden = true
        logTextView.isHidden = true
        forgetIPButton.isHidden = true
        savedIPLabel.isHidden = true
        
        autodiscoveryButton.isHidden = false
        
        manualIPTextField.isHidden = true
        manualIPButton.isHidden = true
        rememberIPSwitch.isHidden = true
        rememberIPLabel.isHidden = true
        
        if let savedIP = UserDefaults.standard.string(forKey: "SavedIPAddress") {
            savedIPLabel.text = "Saved IP: \(savedIP)"
            savedIPLabel.isHidden = false
            forgetIPButton.isHidden = false
        }
    }
    
    @objc func manualIPButtonTapped() {
        guard let ipAddress = manualIPTextField.text, !ipAddress.isEmpty else {
            showAlert(title: "Error", message: "Please enter an IP address.")
            return
        }
        
        if !isValidIPAddress(ipAddress) {
            showAlert(title: "Invalid IP", message: "Please enter a valid IP address.")
            return
        }
        
        if rememberIPSwitch.isOn {
            UserDefaults.standard.set(ipAddress, forKey: "SavedIPAddress")
        }
        
        connectToIP(ipAddress)
    }
    
    func isValidIPAddress(_ ipAddress: String) -> Bool {
        let ipAddressRegex = "^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"
        let ipPredicate = NSPredicate(format: "SELF MATCHES %@", ipAddressRegex)
        return ipPredicate.evaluate(with: ipAddress)
    }
    
    func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
    }
    
    @objc func autodiscoveryButtonTapped() {
        initialOptionsView.isHidden = true
        webView.isHidden = false
        spinner.isHidden = false
        statusLabel.isHidden = false
        logTextView.isHidden = false
        view.bringSubviewToFront(logTextView)
        
        DispatchQueue.global(qos: .background).async {
            self.networkScanner.startNetworkScan()
        }
    }
    
    private func connectToIP(_ ipAddress: String) {
        initialOptionsView.isHidden = true
        webView.isHidden = false
        spinner.isHidden = false
        statusLabel.isHidden = false
        logTextView.isHidden = false
        
        loadWebPage(with: ipAddress)
    }
    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        webView.frame = view.bounds
    }
    deinit {
        NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
        logUpdateTimer?.invalidate()
    }
    private func setupSpinner() {
        DispatchQueue.main.async {
            self.spinner = UIActivityIndicatorView(style: .large)
            if self.traitCollection.userInterfaceStyle == .dark {
                self.spinner.color = .white
            } else {
                self.spinner.color = .black
            }
            self.spinner.isHidden = true
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
            self.statusLabel.isHidden = true
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
            self.refreshButton.tintColor = UIColor.systemBlue
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
            self.refreshButton.isUserInteractionEnabled = true
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.refreshWebView))
            self.refreshButton.addGestureRecognizer(tapGesture)
        }
    }
    private func setupIPLabel() {
        DispatchQueue.main.async {
            self.ipLabel = UILabel()
            self.ipLabel.textColor = UIColor.systemBlue
            if self.traitCollection.userInterfaceStyle == .dark {
                self.ipLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
            } else {
                self.ipLabel.backgroundColor = UIColor.white.withAlphaComponent(0.7)
            }
            self.ipLabel.textAlignment = .center
            self.ipLabel.font = UIFont.systemFont(ofSize: 16)
            self.view.addSubview(self.ipLabel)
            self.ipLabel.translatesAutoresizingMaskIntoConstraints = false
            self.ipLabel.numberOfLines = 1
            self.ipLabel.layer.cornerRadius = 10
            self.ipLabel.layer.masksToBounds = true
            NSLayoutConstraint.activate([
                self.ipLabel.leadingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
                self.ipLabel.bottomAnchor.constraint(equalTo: self.refreshButton.topAnchor, constant: 60),
                self.ipLabel.trailingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.trailingAnchor, constant: -20)
            ])
            self.ipLabel.isHidden = true
            self.ipLabel.isUserInteractionEnabled = true
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.ipLabelTapped))
            self.ipLabel.addGestureRecognizer(tapGesture)
        }
    }
    private func setupRetryButton() {
        DispatchQueue.main.async {
            self.retryButton = UIButton(type: .system)
            self.retryButton.tintColor = UIColor.systemBlue
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
            self.logTextView.isHidden = true
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
    @objc func ipLabelTapped() {
        reinitializeFirstViewController()
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
        networkScanner.isSearchTimedOut = false
        networkScanner.startNetworkScan()
        retryButton.isHidden = true
        spinner.startAnimating()
        statusLabel.text = "Searching for devices..."
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
            view.bringSubviewToFront(self.refreshButton)
        }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!) {
        DispatchQueue.main.async {
            self.statusLabel.text = "Connection Timed Out"
            self.spinner.stopAnimating()
            self.retryButton.isHidden = false
            view.bringSubviewToFront(self.retryButton)
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
        if url.absoluteString.contains("/full/") || url.absoluteString.contains("/download/") {
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
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            handleConnectionFailure(for: webView.url?.host ?? "unknown IP")
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            handleConnectionFailure(for: webView.url?.host ?? "unknown IP")
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
        downloadProgressLabel = UILabel(frame: CGRect(x: 20, y: 45, width: 230, height: 20))
        downloadProgressLabel?.textAlignment = .center
        downloadProgressLabel?.text = "0%"
        downloadAlert?.view.addSubview(downloadProgressLabel!)
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.center = CGPoint(x: 135.0, y: 85.5)
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
extension ViewController: NetworkScannerDelegate {
    func showRetryButton() {
        DispatchQueue.main.async {
            self.retryButton.isHidden = false
            self.statusLabel.text = "Connection Timed Out"
            self.spinner.stopAnimating()
            view.bringSubviewToFront(self.retryButton)
        }
    }
    
    func loadWebPage(with ipAddress:String) {
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { // 10-second timeout
            if self.webView.isLoading {
                self.webView.stopLoading()
                self.handleConnectionFailure(for: ipAddress)
            }
        }
    }

    private func handleConnectionFailure(for ipAddress: String) {
        showAlert(title: "Connection Failed", message: "Failed to connect to \(ipAddress). Would you like to try again or enter a new IP?", actions: [
            UIAlertAction(title: "Try Again", style: .default) { _ in
                self.connectToIP(ipAddress)
            },
            UIAlertAction(title: "Enter New IP", style: .default) { _ in
                self.showInitialOptions()
                self.manualIPTextField.text = ipAddress
            },
            UIAlertAction(title: "Cancel", style: .cancel) { _ in
                self.showInitialOptions()
            }
        ])
    }

    func showAlert(title: String, message: String, actions: [UIAlertAction]) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        for action in actions {
            alert.addAction(action)
        }
        present(alert, animated: true, completion: nil)
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
}
extension ViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView.contentOffset.y > scrollView.contentSize.height - scrollView.frame.size.height {
            scrollView.contentOffset.y = scrollView.contentSize.height - scrollView.frame.size.height
        }
    }
}
extension ViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        manualIPButtonTapped()
        return true
    }
}
