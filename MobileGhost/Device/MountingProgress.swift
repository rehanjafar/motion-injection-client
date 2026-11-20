//
//  MountingProgress.swift
//  MobileGhost
//

import Foundation
import idevice

final class MountingProgress: ObservableObject {
    static let shared = MountingProgress()

    @Published private(set) var mountProgress: Double = 0.0
    @Published private(set) var mountingThread: Thread?
    @Published private(set) var coolisMounted: Bool = false

    private init() {}

    private var isChecking = false
    func checkforMounted() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.checkforMounted() }; return
        }
        guard !isChecking, mountingThread == nil else { return }
        isChecking = true
        LocationSimulationCommandQueue.shared.async {
            // Do not compete with an active simulation for its developer endpoint.
            let result: MountCheckResult? = LocationSimulationSession.isOpen || LocationSimulationSession.isMaintained ? nil : checkMountStatus()
            DispatchQueue.main.async {
                if let result {
                    switch result {
                    case .mounted: self.coolisMounted = true
                    case .notMounted: self.coolisMounted = false
                    case .unreachable: break // A failed check is not proof of an unmounted image.
                    }
                }
                self.isChecking = false
            }
        }
    }

    func progressCallback(progress: size_t, total: size_t, context: UnsafeMutableRawPointer?) {
        let percentage = Double(progress) / Double(total) * 100.0
        DispatchQueue.main.async {
            self.mountProgress = percentage
        }
    }

    func pubMount() {
        mount()
    }

    private func mount() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.mount() }; return
        }
        guard mountingThread == nil else { return }
        let thread = Thread { [weak self] in
            guard let self else { return }
            // These calls can wait on the developer connection. Never run them
            // on the UI thread, where they would block map gestures.
            let currentlyMounted = isMounted()
            var mountError: String?
            var mounted = currentlyMounted
            if !currentlyMounted {
                if isPairing() {
                    mountError = mountPersonalDDI(
                        imagePath: URL.documentsDirectory.appendingPathComponent("DDI/Image.dmg").path,
                        trustcachePath: URL.documentsDirectory.appendingPathComponent("DDI/Image.dmg.trustcache").path,
                        manifestPath: URL.documentsDirectory.appendingPathComponent("DDI/BuildManifest.plist").path)
                    mounted = mountError == nil
                } else { mountError = "Import a valid pairing file before preparing the developer image." }
            }
            DispatchQueue.main.async {
                self.coolisMounted = mounted
                self.mountingThread = nil
                if let mountError {
                    showAlert(title:String(localized:"DDI Mount Failed"),message:mountError,showOk:true,showTryAgain:true) { retry in
                        if retry { self.mount() }
                    }
                }
            }
        }
        thread.qualityOfService = .utility
        thread.name = "mounting"
        mountingThread = thread
        thread.start()
    }

}

func isPairing() -> Bool {
    let pairingPath = PairingFileStore.prepareURL().path
    var pairingFile: RpPairingFileHandle?
    let error = rp_pairing_file_read(pairingPath, &pairingFile)
    if error != nil {
        return false
    }
    rp_pairing_file_free(pairingFile)
    return true
}
