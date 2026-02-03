import Foundation

enum SignalHandler {
    private static var sources: [DispatchSourceSignal] = []

    static func install(handler: @escaping () -> Void) {
        for sig in [SIGINT, SIGTERM] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                handler()
            }
            source.resume()
            sources.append(source)
        }
    }
}
