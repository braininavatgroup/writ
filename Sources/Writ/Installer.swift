import AppKit
import Foundation
import Security

/// Downloads a release and installs it over the running app.
///
/// **This is the most dangerous code in Writ.** It fetches an executable over
/// the network and replaces the one on disk. If the verification below is wrong
/// or skipped, anyone who can answer for the update host — or intercept the
/// connection — gets to run code as the user.
///
/// So the downloaded app is checked against a code-signing requirement pinned to
/// our own Team ID before anything is moved, and the check is the gate rather
/// than a warning. A download that fails it is deleted, not installed with a
/// caution.
@MainActor
final class Installer: ObservableObject {

    enum Phase: Equatable {
        case idle
        case downloading(Double)     // 0…1
        case verifying
        case installing
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle

    /// Pinned to the Developer ID that signs Writ. `anchor apple generic`
    /// requires Apple's root, and the leaf OU is the Team ID — together they
    /// mean "signed by us, with a certificate Apple issued". A self-signed
    /// impostor cannot satisfy this, and neither can a different developer's
    /// legitimately notarised app.
    private static let requirement =
        #"anchor apple generic and certificate leaf[subject.OU] = "L65VUZN7VJ""#

    private var task: URLSessionDownloadTask?
    private var observation: NSKeyValueObservation?

    func install(from urlString: String) {
        guard let url = URL(string: urlString), url.scheme == "https" else {
            phase = .failed("The update location is not a secure address.")
            return
        }
        phase = .downloading(0)

        let task = URLSession.shared.downloadTask(with: url) { [weak self] location, response, error in
            Task { @MainActor in
                guard let self else { return }
                guard let location,
                      let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    self.phase = .failed(error?.localizedDescription ?? "The download failed.")
                    return
                }
                // The temporary file is deleted the moment this callback
                // returns, so it has to be moved before anything else happens.
                let staged = FileManager.default.temporaryDirectory
                    .appendingPathComponent("Writ-update-\(http.hashValue).dmg")
                try? FileManager.default.removeItem(at: staged)
                do { try FileManager.default.moveItem(at: location, to: staged) }
                catch { self.phase = .failed("Could not stage the download."); return }

                self.verifyAndInstall(dmg: staged)
            }
        }
        observation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            Task { @MainActor in self?.phase = .downloading(progress.fractionCompleted) }
        }
        self.task = task
        task.resume()
    }

    private func verifyAndInstall(dmg: URL) {
        phase = .verifying

        Task.detached(priority: .userInitiated) {
            let result = Self.performInstall(dmg: dmg)
            await MainActor.run {
                switch result {
                case .success:
                    self.phase = .installing
                    Self.relaunch()
                case .failure(let message):
                    self.phase = .failed(message)
                }
            }
        }
    }

    private enum InstallResult { case success, failure(String) }

    /// Mount, verify, swap, unmount. Runs off the main thread — mounting a disk
    /// image and copying a bundle both block.
    private nonisolated static func performInstall(dmg: URL) -> InstallResult {
        defer { try? FileManager.default.removeItem(at: dmg) }

        guard let mountPoint = attach(dmg) else {
            return .failure("Could not open the downloaded disk image.")
        }
        defer { detach(mountPoint) }

        let candidate = mountPoint.appendingPathComponent("Writ.app")
        guard FileManager.default.fileExists(atPath: candidate.path) else {
            return .failure("The download did not contain Writ.")
        }

        // THE GATE. Nothing below this line runs for an unverified bundle.
        guard verifySignature(at: candidate) else {
            return .failure("The download was not signed by Brain in a Vat and has been discarded.")
        }

        let destination = URL(fileURLWithPath: "/Applications/Writ.app")
        let backup = FileManager.default.temporaryDirectory
            .appendingPathComponent("Writ-previous.app")
        try? FileManager.default.removeItem(at: backup)

        do {
            // Move the old one aside rather than deleting it, so a failed copy
            // leaves a working app to put back instead of nothing at all.
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.moveItem(at: destination, to: backup)
            }
            try FileManager.default.copyItem(at: candidate, to: destination)
            try? FileManager.default.removeItem(at: backup)
            return .success
        } catch {
            if FileManager.default.fileExists(atPath: backup.path),
               !FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.moveItem(at: backup, to: destination)
            }
            return .failure("Could not replace the installed app: \(error.localizedDescription)")
        }
    }

    /// Checks the bundle against our pinned requirement using the Security
    /// framework rather than shelling out to `codesign` — parsing another
    /// program's text output is not a security boundary.
    nonisolated static func verifySignature(at bundle: URL) -> Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundle as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else { return false }

        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(Self.requirement as CFString, [], &requirement)
                == errSecSuccess, let requirement else { return false }

        // .checkAllArchitectures so a universal binary cannot smuggle an
        // unsigned slice past a check that only looked at the native one.
        let status = SecStaticCodeCheckValidity(
            staticCode, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), requirement)
        return status == errSecSuccess
    }

    // MARK: - Disk image

    private nonisolated static func attach(_ dmg: URL) -> URL? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["attach", dmg.path, "-nobrowse", "-readonly",
                             "-mountrandom", "/tmp", "-plist"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        guard let plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]] else { return nil }
        for entity in entities {
            if let point = entity["mount-point"] as? String { return URL(fileURLWithPath: point) }
        }
        return nil
    }

    private nonisolated static func detach(_ mountPoint: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["detach", mountPoint.path, "-quiet"]
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
    }

    /// Start the newly installed copy, then exit. `open` is used rather than
    /// exec so the replacement is launched by LaunchServices as a fresh app
    /// rather than inheriting this process's state.
    private static func relaunch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", "/Applications/Writ.app"]
        try? process.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { NSApp.terminate(nil) }
    }
}
