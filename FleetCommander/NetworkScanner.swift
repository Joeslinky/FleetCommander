import Foundation
import Darwin

protocol NetworkScannerDelegate: AnyObject {
    func showRetryButton()
    func appendLogMessage(_ message: String)
    func updateLogView()
    func loadWebPage(with ipAddress: String, port: Int)
}

final class NetworkScanner {
    weak var delegate: NetworkScannerDelegate?

    private var isSearchTimedOut = false
    private var isScanning = false
    private var isDeviceFound = false
    private var session: URLSession?
    private let scanPort = AddressValidator.defaultPort

    func startNetworkScan() {
        cancel()
        isDeviceFound = false
        isScanning = true
        isSearchTimedOut = false
        delegate?.appendLogMessage("Looking for Fleet Manager on port \(scanPort)…")
        scanNetworks()
    }

    func cancel() {
        isScanning = false
        session?.invalidateAndCancel()
        session = nil
    }

    private func completeScan() {
        DispatchQueue.main.async {
            guard self.isScanning, !self.isDeviceFound else { return }
            self.isScanning = false
            self.isSearchTimedOut = true
            self.delegate?.appendLogMessage("No devices responded.")
            self.delegate?.showRetryButton()
        }
    }

    private func getActiveNetworkInterfaces() -> [String] {
        var interfaces = [String]()
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return [] }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while ptr != nil {
            if let interface = ptr?.pointee, isValidInterface(interface) {
                interfaces.append(String(cString: interface.ifa_name))
            }
            ptr = ptr?.pointee.ifa_next
        }
        return Array(Set(interfaces))
    }

    private func isValidInterface(_ interface: ifaddrs) -> Bool {
        let interfaceName = String(cString: interface.ifa_name)
        let validInterfaceNames = ["en0", "bridge100", "utun0", "utun1", "utun2", "utun3", "utun4"]
        return interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) && validInterfaceNames.contains(interfaceName)
    }

    private func getIPAddress(for interface: String) -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while ptr != nil {
            let interfaceName = String(cString: ptr!.pointee.ifa_name)
            if let flags = ptr?.pointee.ifa_flags, let addr = ptr?.pointee.ifa_addr,
               Int32(flags) & (IFF_UP | IFF_RUNNING) != 0,
               addr.pointee.sa_family == UInt8(AF_INET),
               interfaceName == interface {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(addr, socklen_t(addr.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                address = String(cString: hostname)
                break
            }
            ptr = ptr?.pointee.ifa_next
        }
        return address
    }

    private func scanNetworks() {
        let interfaces = getActiveNetworkInterfaces()
        var allHosts = [String]()
        var labels = [String]()
        for interface in interfaces {
            guard let localIP = getIPAddress(for: interface) else { continue }
            labels.append(subnetLabel(from: localIP))
            allHosts.append(contentsOf: calculateSubnetRange(from: localIP).filter { $0 != localIP })
        }
        let uniqueHosts = Array(Set(allHosts)).sorted()

        guard !uniqueHosts.isEmpty else {
            delegate?.appendLogMessage("No Wi-Fi address found. Check that Wi-Fi is on.")
            completeScan()
            return
        }

        delegate?.appendLogMessage("Scanning \(labels.joined(separator: ", "))…")
        scanSubnet(uniqueHosts)
    }

    private func subnetLabel(from ip: String) -> String {
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return ip }
        return "\(parts[0]).\(parts[1]).\(parts[2]).0/24"
    }

    private func calculateSubnetRange(from localIPAddress: String) -> [String] {
        let components = localIPAddress.split(separator: ".")
        guard components.count == 4 else { return [] }
        let subnetBase = components.dropLast().joined(separator: ".")
        return (1...254).map { "\(subnetBase).\($0)" }
    }

    private func scanSubnet(_ ipRange: [String]) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 1.4
        configuration.timeoutIntervalForResource = 1.4
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration)
        self.session = session

        let queue = DispatchQueue(label: "com.fleetcommander.scan", qos: .userInitiated)
        let group = DispatchGroup()
        let limiter = DispatchSemaphore(value: 32)

        for ipAddress in ipRange {
            group.enter()
            queue.async {
                limiter.wait()
                guard self.isScanning, !self.isDeviceFound else {
                    limiter.signal()
                    group.leave()
                    return
                }
                self.probe(ipAddress: ipAddress, session: session) {
                    limiter.signal()
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.completeScan()
        }
    }

    private func probe(ipAddress: String, session: URLSession, completion: @escaping () -> Void) {
        guard let url = URL(string: "http://\(ipAddress):\(scanPort)") else {
            completion()
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 1.4
        session.dataTask(with: request) { [weak self] _, response, _ in
            defer { completion() }
            guard let self, self.isScanning, !self.isDeviceFound else { return }
            if let httpResponse = response as? HTTPURLResponse, (200...399).contains(httpResponse.statusCode) {
                self.isDeviceFound = true
                self.isScanning = false
                self.delegate?.appendLogMessage("Found \(ipAddress)")
                self.delegate?.loadWebPage(with: ipAddress, port: self.scanPort)
                self.session?.invalidateAndCancel()
            }
        }.resume()
    }
}
