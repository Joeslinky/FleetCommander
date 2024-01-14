//
//  NetworkScanner.swift
//  C3-Navigation
//
//  Created by Ethan Smith on 1/14/24.
//

import Foundation

class NetworkScanner {
    weak var viewController: ViewController?
    weak var delegate: NetworkScannerDelegate?
    var isSearchTimedOut = false
    var isScanning = false
    var isDeviceFound = false
    func startNetworkScan() {
        DispatchQueue.main.async {
            self.isDeviceFound = false
            self.isScanning = true
            self.scanNetworks()
        }
    }
    func completeScan() {
        DispatchQueue.main.async {
            if !self.isDeviceFound && self.isScanning {
                self.isSearchTimedOut = true
                self.delegate?.showRetryButton()
                self.isScanning = false
                print("No devices found")
                self.delegate?.appendLogMessage("No devices found")
                self.delegate?.updateLogView()
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
                            self.delegate?.loadWebPage(with: ipAddress)
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
        delegate?.appendLogMessage("Pinging \(ipAddress)...")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                completion(true)
                print("Device found at \(ipAddress)")
                self.delegate?.appendLogMessage("Device found at \(ipAddress)")
                self.delegate?.loadWebPage(with: ipAddress)
                self.isDeviceFound = true
            } else {
                completion(false)
                if !self.isDeviceFound {
                    print("Failed to connect to \(ipAddress)")
                    self.delegate?.appendLogMessage("Failed to connect to \(ipAddress)")
                }
            }
        }
        task.resume()
    }
}
protocol NetworkScannerDelegate: AnyObject {
    func showRetryButton()
    func appendLogMessage(_ message: String)
    func updateLogView()
    func loadWebPage(with ipAddress:String)
}
