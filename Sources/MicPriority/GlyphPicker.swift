import AppKit
import SwiftUI

/// Per-device glyph and label editor.
///
/// Two reasons this exists: picking an icon you like, and — for AirPlay —
/// being the ONLY way to tell two devices apart, since macOS names every one of
/// them "AirPlay". Labelling one also promotes it from disposable to permanent.
struct GlyphPicker: View {
    let entry: PriorityEntry
    let direction: Direction
    @ObservedObject var model: PriorityModel
    @Environment(\.dismiss) private var dismiss

    @State private var draftName: String = ""
    @State private var customSymbolField: String = ""

    /// Curated set, filtered at runtime so a symbol missing on this OS version
    /// never renders as an invisible gap.
    private static let curated: [String] = [
        "airpodspro", "airpods", "airpods.gen3", "airpodsmax", "earbuds",
        "headphones", "headset", "beats.headphones",
        "homepod", "homepodmini", "homepod.and.homepodmini", "hifispeaker", "hifispeaker.2",
        "appletv", "tv", "display", "display.2", "laptopcomputer", "macbook", "desktopcomputer",
        "ipad", "iphone", "applewatch", "car", "airplayaudio", "airplayvideo",
        "mic", "mic.fill", "mic.circle", "music.mic", "waveform", "waveform.circle",
        "speaker.wave.2", "speaker.wave.3", "speaker.wave.1", "speaker",
        "dot.radiowaves.left.and.right", "antenna.radiowaves.left.and.right", "radio",
        "music.note", "music.quarternote.3", "guitars", "pianokeys", "amplifier",
        "person.wave.2", "ear", "megaphone", "bell", "sparkles", "star", "bolt",
        "flame", "leaf", "moon", "sun.max", "cloud", "heart", "brain",
    ]

    private var available: [String] {
        Self.curated.filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil }
    }

    private let columns = Array(repeating: GridItem(.fixed(30), spacing: 4), count: 8)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Preview at the exact size the list draws it, so a glyph that
            // turns to mush at badge size is obvious before you commit to it.
            HStack(spacing: 9) {
                DeviceBadge(symbol: model.symbol(entry, direction), filled: true)
                DeviceBadge(symbol: model.symbol(entry, direction))
                VStack(alignment: .leading, spacing: 1) {
                    Text(draftName.isEmpty ? entry.name : draftName)
                        .font(.system(size: 13))
                        .lineLimit(1)
                    Text("Preview").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .padding(8)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 4) {
                Text("Label").font(.system(size: 10)).foregroundStyle(.secondary)
                TextField(entry.name, text: $draftName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .onSubmit { model.setCustomName(draftName, for: entry, direction) }
            }

            Divider()

            Text("Icon").font(.system(size: 10)).foregroundStyle(.secondary)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(available, id: \.self) { name in
                        Button {
                            model.setCustomSymbol(name, for: entry, direction)
                        } label: {
                            Image(systemName: name)
                                .font(.system(size: 14, weight: .medium))
                                .scaledToFit()
                                .frame(width: 30, height: 27)
                                .background(
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(model.symbol(entry, direction) == name
                                              ? Color.accentColor : Color.primary.opacity(0.06)))
                                .foregroundStyle(model.symbol(entry, direction) == name
                                                 ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                        .help(name)
                    }
                }
            }
            .frame(height: 150)

            Divider()

            // The SF Symbols app copies names to the clipboard, so paste-any is
            // more useful than any curated grid can be.
            VStack(alignment: .leading, spacing: 4) {
                Text("Or paste any SF Symbol name")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                HStack(spacing: 5) {
                    TextField("e.g. hifispeaker.and.homepodmini", text: $customSymbolField)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                    Button("Set") { applyTypedSymbol() }
                        .font(.system(size: 11))
                        .disabled(!typedSymbolValid)
                }
                if !customSymbolField.isEmpty && !typedSymbolValid {
                    Text("No such symbol in this macOS version")
                        .font(.system(size: 9)).foregroundStyle(.orange)
                }
            }

            HStack {
                Button("Reset to Default") {
                    model.setCustomSymbol(nil, for: entry, direction)
                    model.setCustomName(nil, for: entry, direction)
                    draftName = ""
                }
                .font(.system(size: 10))
                Spacer()
                Button("Done") {
                    model.setCustomName(draftName, for: entry, direction)
                    dismiss()
                }
                .font(.system(size: 10))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(width: 300)
        .onAppear { draftName = entry.customName ?? "" }
    }

    private var typedSymbolValid: Bool {
        let name = customSymbolField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        return NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }

    private func applyTypedSymbol() {
        let name = customSymbolField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil else { return }
        model.setCustomSymbol(name, for: entry, direction)
    }
}
