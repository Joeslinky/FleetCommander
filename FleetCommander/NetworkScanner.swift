import Foundation
import Darwin

struct DiscoveredDevice {
    let address: String
    let port: Int
    let name: String
}

protocol NetworkScannerDelegate: AnyObject {
    func showRetryButton()
    func appendLogMessage(_ message: String)
    func updateLogView()
    func loadWebPage(with ipAddress: String, port: Int)
    func networkScanner(_ scanner: NetworkScanner, didDiscover devices: [DiscoveredDevice], ignoredOpenPorts: Int)
}

extension NetworkScannerDelegate {
    func networkScanner(_ scanner: NetworkScanner, didDiscover devices: [DiscoveredDevice], ignoredOpenPorts: Int) {
        if let first = devices.first, devices.count == 1 {
            loadWebPage(with: first.address, port: first.port)
        } else if devices.isEmpty {
            showRetryButton()
        }
    }
}

final class NetworkScanner {
    weak var delegate: NetworkScannerDelegate?

    private var isScanning = false
    private let scanPort = AddressValidator.defaultPort
    private let fingerprintSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        configuration.timeoutIntervalForResource = 3
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    func startNetworkScan() {
        cancel()
        isScanning = true
        delegate?.appendLogMessage("Looking for The Pond on port \(scanPort)…")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.scanNetworks()
        }
    }

    func cancel() {
        isScanning = false
    }

    private func finish(devices: [DiscoveredDevice], ignoredOpenPorts: Int) {
        DispatchQueue.main.async {
            guard self.isScanning else { return }
            self.isScanning = false
            if devices.isEmpty {
                if ignoredOpenPorts > 0 {
                    self.delegate?.appendLogMessage("Port \(self.scanPort) was open on \(ignoredOpenPorts) device\(ignoredOpenPorts == 1 ? "" : "s"), but none were The Pond.")
                } else {
                    self.delegate?.appendLogMessage("No Pond found on this network.")
                }
            } else {
                self.delegate?.appendLogMessage("Found \(devices.count) Pond device\(devices.count == 1 ? "" : "s").")
            }
            self.delegate?.networkScanner(self, didDiscover: devices, ignoredOpenPorts: ignoredOpenPorts)
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
        let validInterfaceNames = ["en0", "en1", "bridge100", "ap1", "utun0", "utun1", "utun2", "utun3", "utun4", "utun5"]
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
        let uniqueHosts = Array(Set(allHosts)).sorted { lhs, rhs in
            AddressValidator.ipSortKey(lhs) < AddressValidator.ipSortKey(rhs)
        }

        guard !uniqueHosts.isEmpty else {
            DispatchQueue.main.async {
                self.delegate?.appendLogMessage("No Wi-Fi address found. Check that Wi-Fi is on.")
            }
            finish(devices: [], ignoredOpenPorts: 0)
            return
        }

        DispatchQueue.main.async {
            self.delegate?.appendLogMessage("Scanning \(labels.joined(separator: ", "))…")
        }

        let openHosts = findOpenPorts(in: uniqueHosts)
        guard isScanning else { return }

        if openHosts.isEmpty {
            finish(devices: [], ignoredOpenPorts: 0)
            return
        }

        DispatchQueue.main.async {
            self.delegate?.appendLogMessage("Checking \(openHosts.count) device\(openHosts.count == 1 ? "" : "s") on port \(self.scanPort)…")
        }

        var ponds = [DiscoveredDevice]()
        let lock = NSLock()
        let group = DispatchGroup()
        let fingerprintQueue = DispatchQueue(label: "com.fleetcommander.fingerprint", qos: .userInitiated, attributes: .concurrent)

        for host in openHosts {
            guard isScanning else { break }
            group.enter()
            fingerprintQueue.async {
                defer { group.leave() }
                guard self.isScanning else { return }
                if let device = self.fingerprintPond(at: host) {
                    lock.lock()
                    ponds.append(device)
                    lock.unlock()
                    DispatchQueue.main.async {
                        self.delegate?.appendLogMessage("Found \(device.name) at \(device.address)")
                    }
                }
            }
        }

        group.wait()
        guard isScanning else { return }

        let ignored = openHosts.count - ponds.count
        let sorted = ponds.sorted { AddressValidator.ipSortKey($0.address) < AddressValidator.ipSortKey($1.address) }
        finish(devices: sorted, ignoredOpenPorts: max(0, ignored))
    }

    private func findOpenPorts(in hosts: [String]) -> [String] {
        var openHosts = [String]()
        let lock = NSLock()
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "com.fleetcommander.tcp", qos: .userInitiated, attributes: .concurrent)
        let limiter = DispatchSemaphore(value: 48)

        for host in hosts {
            group.enter()
            queue.async {
                limiter.wait()
                defer {
                    limiter.signal()
                    group.leave()
                }
                guard self.isScanning else { return }
                if self.tcpPortOpen(host, port: self.scanPort, timeoutMs: 600) {
                    lock.lock()
                    openHosts.append(host)
                    lock.unlock()
                }
            }
        }

        group.wait()
        return openHosts.sorted { AddressValidator.ipSortKey($0) < AddressValidator.ipSortKey($1) }
    }

    private func fingerprintPond(at ipAddress: String) -> DiscoveredDevice? {
        guard let url = URL(string: "http://\(ipAddress):\(scanPort)/") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("close", forHTTPHeaderField: "Connection")
        request.timeoutInterval = 3

        let semaphore = DispatchSemaphore(value: 0)
        var html: String?
        var status: Int = 0
        fingerprintSession.dataTask(with: request) { data, response, _ in
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let data {
                html = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1)
            }
            semaphore.signal()
        }.resume()

        _ = semaphore.wait(timeout: .now() + 3.2)
        guard (200...399).contains(status), let html, let name = PondFingerprint.match(html) else {
            return nil
        }
        return DiscoveredDevice(address: ipAddress, port: scanPort, name: name)
    }

    private func tcpPortOpen(_ host: String, port: Int, timeoutMs: Int32) -> Bool {
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else { return false }

        let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        let flags = fcntl(fd, F_GETFL, 0)
        guard flags >= 0 else { return false }
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        let connected: Int32 = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if connected == 0 { return true }
        if errno != EINPROGRESS { return false }

        var pollSocket = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        let polled = withUnsafeMutablePointer(to: &pollSocket) { poll($0, 1, timeoutMs) }
        guard polled > 0 else { return false }

        var soError: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(fd, SOL_SOCKET, SO_ERROR, &soError, &length)
        return soError == 0
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
}

private enum PondFingerprint {
    static func match(_ html: String) -> String? {
        let title = htmlTitle(html)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let lowered = html.lowercased()

        if title.compare("The Pond", options: .caseInsensitive) == .orderedSame {
            return "The Pond"
        }
        if title.localizedCaseInsensitiveContains("fleet manager") {
            return title.isEmpty ? "Fleet Manager" : title
        }
        if lowered.contains("id=\"htmlelement\"") && lowered.contains("/assets/components/") {
            return "The Pond"
        }
        if lowered.contains("/assets/components/router.js") || lowered.contains("dashcam_routes") {
            return "The Pond"
        }
        if lowered.contains("the pond") && lowered.contains("mapbox") {
            return "The Pond"
        }
        return nil
    }

    private static func htmlTitle(_ html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "<title[^>]*>(.*?)</title>", options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let titleRange = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return String(html[titleRange])
    }
}
