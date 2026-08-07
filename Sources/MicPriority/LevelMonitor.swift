import AVFoundation
import Combine
import Foundation

/// Live input level metering.
///
/// Privacy posture: this captures microphone audio, so it runs ONLY while the
/// Input tab is actually on screen — opening the panel starts it, closing or
/// switching to Output stops it. Nothing is recorded, written, or retained; each
/// buffer is reduced to a single RMS number and discarded.
final class LevelMonitor: ObservableObject {

    /// Smoothed RMS, 0…1, already mapped from the dB floor.
    @Published private(set) var level: Float = 0
    /// Fast peak with slow decay, for the peak-hold tick.
    @Published private(set) var peak: Float = 0
    @Published private(set) var peakDB: Float = -120
    /// Rolling average — the level you're actually sitting at.
    @Published private(set) var averageDB: Float = -120
    /// Slow-tracking minimum: room tone / background noise. This is where
    /// Voice Isolation shows itself — it barely moves your speech level but
    /// pulls the floor down hard.
    @Published private(set) var noiseFloorDB: Float = -120
    @Published private(set) var clipping = false
    @Published private(set) var running = false
    @Published private(set) var denied = false

    /// Anything below this reads as silence on the meter.
    private let floorDB: Float = -60

    private var engine: AVAudioEngine?
    private var decayTimer: Timer?
    private var lastClipAt: Date?

    func start() {
        guard !running else { return }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            begin()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.begin() } else { self?.denied = true }
                }
            }
        default:
            denied = true
        }
    }

    func stop() {
        decayTimer?.invalidate(); decayTimer = nil
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        running = false
        level = 0; peak = 0; peakDB = -120; clipping = false
    }

    /// The engine binds to whatever the default input device was when it
    /// started, so a device switch needs a fresh engine.
    func restart() {
        guard running else { return }
        stop()
        start()
    }

    private func begin() {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return }

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self, let channels = buffer.floatChannelData else { return }
            let frames = Int(buffer.frameLength)
            guard frames > 0 else { return }

            var sumSquares: Float = 0
            var framePeak: Float = 0
            for channel in 0..<Int(buffer.format.channelCount) {
                let samples = channels[channel]
                for i in 0..<frames {
                    let sample = samples[i]
                    sumSquares += sample * sample
                    framePeak = max(framePeak, abs(sample))
                }
            }
            let count = Float(frames * Int(buffer.format.channelCount))
            let rms = sqrt(sumSquares / count)
            let db = rms > 0 ? 20 * log10(rms) : -120

            DispatchQueue.main.async { self.apply(db: db, framePeak: framePeak) }
        }

        do {
            try engine.start()
            self.engine = engine
            running = true
            denied = false
            startDecay()
        } catch {
            self.engine = nil
            running = false
        }
    }

    private func apply(db: Float, framePeak: Float) {
        let normalized = max(0, min(1, (db - floorDB) / -floorDB))
        // Fast attack so speech reads immediately, slow release so the bar
        // doesn't strobe on every buffer.
        level = normalized > level ? normalized : level * 0.8 + normalized * 0.2
        if normalized > peak { peak = normalized }
        peakDB = max(peakDB, db)

        // Rolling average of anything above the noise gate, so silence between
        // sentences doesn't drag the reading down.
        if db > floorDB {
            averageDB = averageDB <= -119 ? db : averageDB * 0.95 + db * 0.05
        }

        // Noise floor: snap down instantly, creep back up slowly, so it settles
        // on room tone rather than following speech.
        if noiseFloorDB <= -119 || db < noiseFloorDB {
            noiseFloorDB = db
        } else {
            noiseFloorDB += 0.02
        }
        if framePeak >= 0.99 {
            clipping = true
            lastClipAt = Date()
        }
    }

    private func startDecay() {
        decayTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.peak *= 0.97
            if self.peak < self.level { self.peak = self.level }
            // Clipping was latched until manually reset, so it stayed lit even
            // after the gain came down. It now clears itself once the input has
            // been clean for a moment.
            if self.clipping, let last = self.lastClipAt, Date().timeIntervalSince(last) > 1.5 {
                self.clipping = false
            }
        }
    }

    /// Apple's microphone mode (Standard / Voice Isolation / Wide Spectrum).
    /// Both mode properties are READ-ONLY on macOS — Apple exposes no way to set
    /// them programmatically, only to open their own picker. So this reports the
    /// mode and `showModePicker()` hands off to the system UI.
    var microphoneMode: String {
        switch AVCaptureDevice.activeMicrophoneMode {
        case .standard: return "Standard"
        case .wideSpectrum: return "Wide Spectrum"
        case .voiceIsolation: return "Voice Isolation"
        @unknown default: return "Unknown"
        }
    }

    var microphoneModeDiffersFromPreferred: Bool {
        AVCaptureDevice.activeMicrophoneMode != AVCaptureDevice.preferredMicrophoneMode
    }

    func showModePicker() {
        AVCaptureDevice.showSystemUserInterface(.microphoneModes)
    }

    /// Peak-hold readout, reset by the user between takes.
    func resetPeak() {
        peak = level
        peakDB = -120
        averageDB = -120
        noiseFloorDB = -120
        clipping = false
    }
}
