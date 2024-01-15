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
        return Array(Set(interfaces)) // Remove duplicates
    }
    
    /// Checks if the network interface is valid for scanning.
    /// - Parameter interface: A network interface.
    /// - Returns: A Boolean indicating if the interface is valid.
    private func isValidInterface(_ interface: ifaddrs) -> Bool {
        let interfaceName = String(cString: interface.ifa_name)
        return (interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) || interface.ifa_addr.pointee.sa_family == UInt8(AF_INET6)) &&
        (interfaceName == "en0" || interfaceName == "bridge100")
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
                                delegate?.appendLogMessage("IP Address for interface \(interface): \(address ?? "nil")")
                                delegate?.updateLogView()
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
    
    /// Initiates a scan of the networks based on active interfaces.
    private func scanNetworks() {
        guard let localIP = getActiveNetworkInterfaces().compactMap(getIPAddress).first else {
            completeScan()
            return
        }
        
        let ipRange = calculateSubnetRange(from: localIP)
        scanSubnetForService(ipRange: ipRange)
    }
    
    /// Calculates the subnet range based on the given local IP address.
    /// - Parameter localIPAddress: The local IP address.
    /// - Returns: An array of IP addresses in the subnet.
    private func calculateSubnetRange(from localIPAddress: String) -> [String] {
        let components = localIPAddress.split(separator: ".")
        let subnetBase = components.dropLast().joined(separator: ".")
        
        guard components.count == 4 else { return [] }
        return (1...254).map { "\(subnetBase).\($0)" }
    }
    
    /// Scans a given subnet for a specific service.
    /// - Parameter ipRange: The IP range of the subnet to scan.
    private func scanSubnetForService(ipRange: [String]) {
        // Implementation remains the same.
    }
    
    /// Attempts to establish a connection to a specific IP address and port.
    /// - Parameters:
    /// - ipAddress: The IP address to connect to.
    /// - port: The port number for the connection.
    /// - completion: A closure to execute upon completion, returning a boolean indicating success.
    private func attemptConnection(ipAddress: String, port: Int, completion: @escaping (Bool) -> Void) {
        // Implementation remains the same.
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
