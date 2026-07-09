import Network
import Combine

@MainActor
final class NetworkMonitor: ObservableObject {

    static let shared = NetworkMonitor()

    @Published private(set) var isConnected: Bool = true
    @Published private(set) var isExpensive: Bool = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.smartnotes.networkmonitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in //Call back closure .
            guard let self else { return }
                        let connected = path.status == .satisfied
                        let expensive = path.isExpensive
            Task { @MainActor in
                self.isConnected = connected
                self.isExpensive = expensive
            }
        }
        monitor.start(queue: queue)
    }
}

