import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum Clipboard {
    static func copy(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        #endif
    }
}

/// Selectable, copyable message bubble. Tap the icon to copy; long-press the
/// text also works via `.textSelection(.enabled)`.
struct CopyableText: View {
    let text: String
    var color: Color = Theme.textPrimary
    var iconColor: Color = Theme.textSecondary
    var monospaced: Bool = true

    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(text)
                .font(monospaced ? .footnote.monospaced() : .footnote)
                .foregroundColor(color)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Clipboard.copy(text)
                withMotion { copied = true }
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    withMotion { copied = false }
                }
            } label: {
                Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                    .font(.callout)
                    .foregroundColor(copied ? Theme.success : iconColor)
            }
            .buttonStyle(.plain)
            .help("Kopieren")
        }
    }
}

/// Inline error banner that's always copyable. Drop-in replacement for the
/// scattered "Text(msg).foregroundColor(Theme.danger)" pattern.
struct ErrorBanner: View {
    let message: String
    var tint: Color = Theme.danger

    var body: some View {
        CopyableText(text: message, color: tint, iconColor: tint)
            .padding(10)
            .background(tint.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: – Odometer-Zahl (rollende Ziffern)

/// Misst die Zellgröße EINER Ziffer (Breite + Höhe) an der konkreten Schrift,
/// damit das Roll-Fenster exakt eine Ziffer hoch ist (Dynamic-Type-fest).
private struct DigitCellSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let n = nextValue()
        if n != .zero { value = n }
    }
}

/// Eine Odometer-Ziffer: vertikales 0–9-Rad, das bei Wertwechsel in die neue
/// Ziffer rollt (Offset animiert, ein Zellen-Fenster, Rest geclippt).
private struct RollingDigit: View {
    let digit: Int          // 0...9
    let font: Font
    let color: Color
    @State private var cell: CGSize = .zero

    var body: some View {
        Group {
            if cell.height > 0 {
                VStack(spacing: 0) {
                    ForEach(0...9, id: \.self) { n in
                        Text("\(n)").font(font)
                            .frame(width: cell.width, height: cell.height)
                    }
                }
                .offset(y: -CGFloat(digit) * cell.height)   // Zielziffer ins Fenster
                .frame(width: cell.width, height: cell.height, alignment: .top)
                .clipped()
                // Weiche Ober-/Unterkante: rein-/rausrollende Ziffern faden an
                // den Rändern, statt hart am Clip-Rand abgeschnitten zu wirken.
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .black, location: 0.16),
                            .init(color: .black, location: 0.84),
                            .init(color: .clear, location: 1.0),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .motion(Motion.smooth, value: digit)
            } else {
                Text("0").font(font).opacity(0)             // Platzhalter bis gemessen
            }
        }
        .foregroundColor(color)
        // Unsichtbarer Sizer misst eine Ziffer; pro RollingDigit eigener Scope.
        .background(
            Text("0").font(font).opacity(0).background(
                GeometryReader { g in
                    Color.clear.preference(key: DigitCellSizeKey.self, value: g.size)
                }
            )
        )
        .onPreferenceChange(DigitCellSizeKey.self) { cell = $0 }
    }
}

/// Rechtsbündige Ganzzahl, deren Ziffern als Odometer-Räder rollen. Die
/// Animation steckt pro Ziffer drin (respektiert „Bewegung reduzieren"), läuft
/// also unabhängig vom umgebenden Animationskontext.
struct RollingNumber: View {
    let value: Int
    var font: Font = .caption.monospacedDigit()
    var color: Color = Theme.textPrimary

    var body: some View {
        let v = max(0, value)
        let count = max(1, String(v).count)
        HStack(spacing: 0) {
            // place = Stelle von rechts; reversed ⇒ höchstwertige Ziffer zuerst.
            ForEach((0..<count).reversed(), id: \.self) { place in
                RollingDigit(digit: digit(of: v, at: place), font: font, color: color)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .motion(Motion.smooth, value: count)   // neue Stelle (99→100) gleitet rein
    }

    private func digit(of v: Int, at place: Int) -> Int {
        var x = v
        for _ in 0..<place { x /= 10 }
        return x % 10
    }
}
