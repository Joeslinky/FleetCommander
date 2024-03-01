import Foundation

/// NetworkScanner is responsible for scanning the network for devices.
/// It communicates results through its delegate and updates the view controller.
class NetworkScanner {
    weak var viewController: ViewController?
    weak var delegate: NetworkScannerDelegate?
    
    // State variables to track the scanning process.
    var isSearchTimedOut = false
    var isScanning = false
    var isDeviceFound = false
    var pendingScanOperations = 0
    
    /// Starts the network scanning process.
    func startNetworkScan() {
        DispatchQueue.main.async {
            self.resetScanState()
            self.scanNetworks()
        }
    }
    
    /// Completes the network scanning process and handles timeout.
    func completeScan() {
        DispatchQueue.main.async {
            if !self.isDeviceFound && self.isScanning {
                self.isSearchTimedOut = true
                self.delegate?.showRetryButton()
                self.logMessage("No devices found")
            }
        }
    }
    
    /// Resets the state before starting a new scan.
    private func resetScanState() {
        isDeviceFound = false
        isScanning = true
        isSearchTimedOut = false
    }
    
    /// Retrieves active network interfaces.
    /// - Returns: An array of interface names.
    private func getActiveNetworkInterfaces() -> [String] {
        var interfaces = [String]()
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
    
        // Get the list of network interfaces.
            if getifaddrs(&ifaddr) == 0 {
                defer { freeifaddrs(ifaddr) }
        
                var ptr = ifaddr
                while ptr != nil {
                    if let interface = ptr?.pointee, isValidInterface(interface) {
                        interfaces.append(String(cString: interface.ifa_name))
                    }
                    ptr = ptr?.pointee.ifa_next
                }
            }
    
        let interfaceArray = Array(Set(interfaces))
    
        return interfaceArray
    }
    
    /// Checks if the network interface is valid for scanning.
    /// - Parameter interface: A network interface.
    /// - Returns: A Boolean indicating if the interface is valid.
    private func isValidInterface(_ interface: ifaddrs) -> Bool {
        if let interfaceName = String(cString: interface.ifa_name)?.trimmingCharacters(in: .whitespacesAndNewlines) {
            let validInterfaceNames = ["en0", "bridge100", "utun0", "utun1", "utun2", "utun3"]
            return interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) && validInterfaceNames.contains(interfaceName)
        } else {
            return false // Return false if interfaceName is nil
        }
    }

    /// Retrieves the IP address for a given network interface.
    /// - Parameter interface: The name of the network interface.
    /// - Returns: The IP address as a string, or nil if not found.
    private func getIPAddress(for interface: String) -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while ptr != nil {
                let interfaceName = String(cString: (ptr?.pointee.ifa_name)!)
                if let flags = ptr?.pointee.ifa_flags, let addr = ptr?.pointee.ifa_addr, Int32(flags) & (IFF_UP | IFF_RUNNING) != 0 {
                    if addr.pointee.sa_family == UInt8(AF_INET) {
                        if interfaceName == interface {
                            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                            getnameinfo(addr, socklen_t(addr.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST)
                            address = String(cString: hostname)
                            logMessage("IP Address for interface \(interface): \(address ?? "nil")")
                            delegate?.updateLogView()
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
    
    /// Initiates a scan of the networks based on active interfaces.
    private func scanNetworks() {
        let interfaces = getActiveNetworkInterfaces()
        if interfaces.isEmpty {
            completeScan()
            return
        }
        for interface in interfaces {
            if let localIP = getIPAddress(for: interface) {
                let ipRange = calculateSubnetRange(from: localIP, forInterface: interface)
                pendingScanOperations += 1
                scanSubnetForService(ipRange: ipRange) {
                    self.pendingScanOperations -= 1
                    if self.pendingScanOperations == 0 {
                        self.completeScan()
                    }
                }
            }
        }
    }
    
    /// Calculates the subnet range based on the given local IP address.
    /// - Parameter localIPAddress: The local IP address.
    /// - Returns: An array of IP addresses in the subnet.
    private func calculateSubnetRange(from localIPAddress: String, forInterface interface: String) -> [String] {
        let components = localIPAddress.split(separator: ".")
        guard components.count == 4 else { return [] }
        let subnetBase = components.dropLast().joined(separator: ".")
        return (1...254).map { "\(subnetBase).\($0)" }
    }

    /// Scans a given subnet for a specific service.
    /// - Parameter ipRange: The IP range of the subnet to scan.
    private func scanSubnetForService(ipRange: [String], completion: @escaping () -> Void) {
        guard !ipRange.isEmpty && isScanning else {
            completion()
            return
        }
        self.isDeviceFound = false
        for ipAddress in ipRange where !isDeviceFound {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.attemptConnection(ipAddress: ipAddress, port: 8082) { success in
                    if success {
                        self.isDeviceFound = true
                        self.isScanning = false
                        self.delegate?.loadWebPage(with: ipAddress)
                        completion()
                        return
                    } else if ipAddress == ipRange.last {
                        completion()
                    }
                }
            }
        }
    }
    
    /// Attempts to establish a connection to a specific IP address and port.
    /// - Parameters:
    /// - ipAddress: The IP address to connect to.
    /// - port: The port number for the connection.
    /// - completion: A closure to execute upon completion, returning a boolean indicating success.
    private func attemptConnection(ipAddress: String, port: Int, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "http://\(ipAddress):\(port)") else {
            completion(false)
            return
        }
        logMessage("Pinging \(ipAddress)...")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                completion(true)
                self.logMessage("Device found at \(ipAddress)")
                self.delegate?.loadWebPage(with: ipAddress)
                self.isDeviceFound = true
            } else {
                completion(false)
                if !self.isDeviceFound {
                    self.logMessage("Failed to connect to \(ipAddress)")
                }
            }
        }
        task.resume()
    }
    
    /// Logs a message and updates the delegate.
    /// - Parameter message: The message to log.
    private func logMessage(_ message: String) {
        print(message)
        delegate?.appendLogMessage(message)
        delegate?.updateLogView()
    }
}

/// Protocol defining delegate methods for NetworkScanner.
protocol NetworkScannerDelegate: AnyObject {
    func showRetryButton()
    func appendLogMessage(_ message: String)
    func updateLogView()
    func loadWebPage(with ipAddress: String)
}
