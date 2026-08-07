import Foundation
import IOKit

enum LidState {

    /// True when the laptop lid is shut (clamshell). On Apple silicon the
    /// built-in mic is HARDWARE-disconnected in this state, so it still
    /// enumerates as a device but can never capture audio — selecting it hands
    /// you silence. That's what the "only when lid open" rule exists to avoid.
    static var isClosed: Bool {
        let entry = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard entry != 0 else { return false }
        defer { IOObjectRelease(entry) }

        guard let raw = IORegistryEntryCreateCFProperty(
            entry, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() else { return false }

        // Desktops have no clamshell key at all; absence means "lid open".
        return (raw as? Bool) ?? false
    }
}
