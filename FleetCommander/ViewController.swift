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
    var manualEntryButton: UIButton!
    var autodiscoveryButton: UIButton!
    var rememberIPSwitch: UISwitch!
    var initialOptionsView: UIView!
    var rememberIPLabel: UILabel!
    var choiceLabel: UILabel!
    var portTextField: UITextField!
    var loadingTimer: Timer?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupInitialOptionsView()
        setupSpinner()
        setupStatusLabel()
        setupRefreshButton()
        setupIPLabel()
        setupRetryButton()
        setupLogTextView()
        
        networkScanner = NetworkScanner()
        networkScanner.viewController = self
        networkScanner.delegate = self
        manualIPTextField.delegate = self
        
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
        
        if let savedIP = UserDefaults.standard.string(forKey: "SavedIPAddress"),
           UserDefaults.standard.object(forKey: "SavedPort") != nil {
            let savedPort = UserDefaults.standard.integer(forKey: "SavedPort")
            connectToAddress(savedIP, port: savedPort)
        } else {
            showInitialOptions()
        }
    }
    private func setupInitialOptionsView() {
        initialOptionsView = UIView()
        initialOptionsView.isUserInteractionEnabled = true
        initialOptionsView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(initialOptionsView)
        view.bringSubviewToFront(initialOptionsView)
        initialOptionsView.backgroundColor = .systemBackground.withAlphaComponent(0.9)

        portTextField = UITextField()
        portTextField.placeholder = "Enter Port (default: 8082)"
        portTextField.borderStyle = .roundedRect
        portTextField.translatesAutoresizingMaskIntoConstraints = false
        portTextField.isHidden = true
        portTextField.delegate = self
        portTextField.keyboardType = .numberPad
        initialOptionsView.addSubview(portTextField)
    
        choiceLabel = UILabel()
        choiceLabel.text = "Choose connection method:"
        if traitCollection.userInterfaceStyle == .dark {
            choiceLabel.textColor = .white
        } else {
            choiceLabel.textColor = .black
        }
        choiceLabel.translatesAutoresizingMaskIntoConstraints = false
        choiceLabel.isHidden = true
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
        autodiscoveryButton.isUserInteractionEnabled = true
        autodiscoveryButton.isHidden = true
        initialOptionsView.addSubview(autodiscoveryButton)
    
        manualEntryButton = UIButton(type: .system)
        configureButton(manualEntryButton, "Manual Entry")
        manualEntryButton.addTarget(self, action: #selector(showManualIPEntry), for: .touchUpInside)
        manualEntryButton.translatesAutoresizingMaskIntoConstraints = false
        manualEntryButton.isUserInteractionEnabled = true
        manualEntryButton.isHidden = true
        initialOptionsView.addSubview(manualEntryButton)
    
        manualIPTextField = UITextField()
        manualIPTextField.placeholder = "Enter IP/Hostname"
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
        rememberIPLabel.text = "Remember IP/Hostname"
        if self.traitCollection.userInterfaceStyle == .dark {
            self.rememberIPLabel.textColor = .white
        } else {
            self.rememberIPLabel.textColor = .black
        }
        rememberIPLabel.translatesAutoresizingMaskIntoConstraints = false
        rememberIPLabel.isHidden = true
        initialOptionsView.addSubview(rememberIPLabel)
    
        NSLayoutConstraint.activate([
            initialOptionsView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            initialOptionsView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            initialOptionsView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.8),
            initialOptionsView.bottomAnchor.constraint(equalTo: rememberIPLabel.bottomAnchor, constant: 20),
    
            choiceLabel.topAnchor.constraint(equalTo: initialOptionsView.topAnchor),
            choiceLabel.centerXAnchor.constraint(equalTo: initialOptionsView.centerXAnchor),
    
            autodiscoveryButton.topAnchor.constraint(equalTo: choiceLabel.bottomAnchor, constant: 20),
            autodiscoveryButton.centerXAnchor.constraint(equalTo: initialOptionsView.centerXAnchor),
    
            manualEntryButton.topAnchor.constraint(equalTo: autodiscoveryButton.bottomAnchor, constant: 20),
            manualEntryButton.centerXAnchor.constraint(equalTo: initialOptionsView.centerXAnchor),
    
            manualIPTextField.topAnchor.constraint(equalTo: manualEntryButton.bottomAnchor, constant: 20),
            manualIPTextField.leadingAnchor.constraint(equalTo: initialOptionsView.leadingAnchor),
            manualIPTextField.trailingAnchor.constraint(equalTo: initialOptionsView.trailingAnchor),
    
            portTextField.topAnchor.constraint(equalTo: manualIPTextField.bottomAnchor, constant: 10),
            portTextField.leadingAnchor.constraint(equalTo: initialOptionsView.leadingAnchor),
            portTextField.trailingAnchor.constraint(equalTo: initialOptionsView.trailingAnchor),

            manualIPButton.topAnchor.constraint(equalTo: portTextField.bottomAnchor, constant: 20),
            manualIPButton.centerXAnchor.constraint(equalTo: initialOptionsView.centerXAnchor),

            rememberIPSwitch.topAnchor.constraint(equalTo: manualIPButton.bottomAnchor, constant: 10),
            rememberIPSwitch.leadingAnchor.constraint(equalTo: initialOptionsView.leadingAnchor),

            rememberIPLabel.centerYAnchor.constraint(equalTo: rememberIPSwitch.centerYAnchor),
            rememberIPLabel.leadingAnchor.constraint(equalTo: rememberIPSwitch.trailingAnchor, constant: 10)
        ])
    }
    
    @objc func showManualIPEntry() {
        manualIPTextField.isHidden = false
        portTextField.isHidden = false
        manualIPButton.isHidden = false
        rememberIPSwitch.isHidden = false
        rememberIPLabel.isHidden = false
        autodiscoveryButton.isHidden = true
        manualEntryButton.isHidden = true
        choiceLabel.isHidden = true
    }
    
    func showInitialOptions() {
        DispatchQueue.main.async {
            self.initialOptionsView.isHidden = false
            self.spinner.isHidden = true
            self.statusLabel.isHidden = true
            self.refreshButton.isHidden = true
            self.ipLabel.isHidden = true
            self.retryButton.isHidden = true
            self.logTextView.isHidden = true
            
            self.autodiscoveryButton.isHidden = false
            self.manualEntryButton.isHidden = false
            self.choiceLabel.isHidden = false
            
            self.manualIPTextField.isHidden = true
            self.portTextField.isHidden = true
            self.manualIPButton.isHidden = true
            self.rememberIPSwitch.isHidden = true
            self.rememberIPLabel.isHidden = true
            
            self.view.bringSubviewToFront(self.initialOptionsView)
        }
    }
    
    @objc func manualIPButtonTapped() {
        view.endEditing(true)
        guard let inputAddress = manualIPTextField.text, !inputAddress.isEmpty else {
            showAlert(title: "Error", message: "Please enter an IP address or hostname.")
            return
        }
    
        guard isValidInputAddress(inputAddress) else {
            showAlert(title: "Invalid Input", message: "Please enter a valid IP address or hostname.")
            return
        }
    
        guard let port = validateAndGetPort() else {
            return
        }
    
        if rememberIPSwitch.isOn {
            UserDefaults.standard.set(inputAddress, forKey: "SavedIPAddress")
            UserDefaults.standard.set(port, forKey: "SavedPort")
        }
    
        connectToAddress(inputAddress, port: port)
    }
    
    func validateAndGetPort() -> Int? {
        if let portText = portTextField.text, !portText.isEmpty {
            if let port = Int(portText), port > 0 && port <= 65535 {
                return port
            } else {
                showAlert(title: "Invalid Port", message: "Please enter a valid port number between 1 and 65535.")
                return nil
            }
        }
        return 8082
    }

    func isValidInputAddress(_ address: String) -> Bool {
        return isValidIPAddress(address) || isValidHostname(address)
    }
    
    func isValidIPAddress(_ ipAddress: String) -> Bool {
        let ipAddressRegex = "^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"
        let ipPredicate = NSPredicate(format: "SELF MATCHES %@", ipAddressRegex)
        return ipPredicate.evaluate(with: ipAddress)
    }
    
    func isValidHostname(_ hostname: String) -> Bool {
        let hostnameRegex = "^(?=.{1,253}$)(?:(?!-)[A-Za-z0-9-]{1,63}(?<!-)\\.)+[A-Za-z]{2,63}$"
        let hostnamePredicate = NSPredicate(format: "SELF MATCHES %@", hostnameRegex)
        return hostnamePredicate.evaluate(with: hostname)
    }
    
    func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
    }
    
    @objc func autodiscoveryButtonTapped() {
        initialOptionsView.isHidden = true
        spinner.isHidden = false
        statusLabel.isHidden = false
        logTextView.isHidden = false
        
        DispatchQueue.global(qos: .background).async {
            self.networkScanner.startNetworkScan()
        }
    }
    
    private func connectToAddress(_ address: String, port: Int) {
        initialOptionsView.isHidden = true
        spinner.isHidden = false
        statusLabel.isHidden = false
        logTextView.isHidden = false
        
        loadWebPage(with: address, port: port)
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
        UserDefaults.standard.removeObject(forKey: "SavedIPAddress")
        UserDefaults.standard.removeObject(forKey: "SavedPort")
        showInitialOptions()
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
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleConnectionFailure(for: webView.url?.host ?? "unknown IP", port: webView.url?.port ?? 8082)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleConnectionFailure(for: webView.url?.host ?? "unknown IP", port: webView.url?.port ?? 8082)
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
        }
    }
    
     func loadWebPage(with address: String, port: Int) {
        DispatchQueue.main.async {
            self.statusLabel.text = "Trying \(address):\(port)..."
            self.retryButton.isHidden = true
            self.logTextView.isHidden = true
            self.spinner.startAnimating()
            self.ipLabel.text = "\(address):\(port)"
            let url = URL(string: "http://\(address):\(port)")!
            self.webView.load(URLRequest(url: url))
            self.webView.allowsBackForwardNavigationGestures = false
            
            self.startLoadingTimer(for: address, port: port)
        }
    }

    private func startLoadingTimer(for address: String, port: Int) {
        loadingTimer?.invalidate()
        
        loadingTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
            self?.handleTimeout(for: address, port: port)
        }
    }

    private func handleTimeout(for address: String, port: Int) {
        DispatchQueue.main.async {
            if self.webView.isLoading {
                self.webView.stopLoading()
                self.handleConnectionFailure(for: address, port: port)
            }
        }
    }

    private func handleConnectionFailure(for ipAddress: String, port: Int) {
        showAlert(title: "Connection Failed", message: "Failed to connect to \(ipAddress):\(port). Would you like to try again or enter a new IP/Hostname?", actions: [
            UIAlertAction(title: "Try Again", style: .default) { _ in
                self.connectToAddress(ipAddress, port: port)
            },
            UIAlertAction(title: "Enter New IP/Hostname", style: .default) { _ in
                self.initialOptionsView.isHidden = false
                self.statusLabel.text = "Connection Failed"
                self.spinner.isHidden = true
                self.statusLabel.isHidden = true
                self.manualIPTextField.isHidden = false
                self.portTextField.isHidden = false
                self.manualEntryButton.isHidden = true
                self.autodiscoveryButton.isHidden = true
                self.manualIPButton.isHidden = false
                self.rememberIPSwitch.isHidden = false
                self.rememberIPLabel.isHidden = false
                self.choiceLabel.isHidden = true
                self.manualIPTextField.text = ipAddress
                self.portTextField.text = "\(port)"
            },
            UIAlertAction(title: "Cancel", style: .cancel) { _ in
                self.showInitialOptions()
                self.manualIPTextField.isHidden = true
                self.portTextField.isHidden = true
                self.manualIPButton.isHidden = true
                self.rememberIPSwitch.isHidden = true
                self.rememberIPLabel.isHidden = true
                UserDefaults.standard.removeObject(forKey: "SavedIPAddress")
                UserDefaults.standard.removeObject(forKey: "SavedPort")
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
        if textField == manualIPTextField {
            portTextField.becomeFirstResponder()
        } else if textField == portTextField {
            manualIPButtonTapped()
        }
        return true
    }
}
