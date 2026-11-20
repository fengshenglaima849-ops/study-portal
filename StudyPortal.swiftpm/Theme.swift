import SwiftUI

/// ダークはピアノブラック、ライトは白いピアノ塗装。どちらも金は要所だけに使う
struct Palette {
    let base: Color
    let sheen: Color
    let text: Color
    let subtext: Color
    let surface: Color
    let stroke: Color
    let gold: Color

    static func of(_ scheme: ColorScheme) -> Palette {
        if scheme == .dark {
            return Palette(
                base: Color(red: 0.02, green: 0.02, blue: 0.025),
                sheen: Color(red: 0.17, green: 0.17, blue: 0.19),
                text: Color(white: 0.97),
                subtext: Color(white: 0.62),
                surface: Color.white.opacity(0.06),
                stroke: Color.white.opacity(0.14),
                gold: Color(red: 0.84, green: 0.71, blue: 0.45)
            )
        } else {
            return Palette(
                base: Color(red: 0.95, green: 0.945, blue: 0.935),
                sheen: Color.white,
                text: Color(red: 0.05, green: 0.05, blue: 0.06),
                subtext: Color(white: 0.38),
                surface: Color.black.opacity(0.04),
                stroke: Color.black.opacity(0.12),
                gold: Color(red: 0.60, green: 0.47, blue: 0.22)
            )
        }
    }
}

/// 塗装面の艶と、斜めに映り込む光
struct PianoBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Palette.of(scheme)
        ZStack {
            LinearGradient(colors: [p.sheen, p.base, p.base, p.sheen.opacity(0.7)],
                           startPoint: .top, endPoint: .bottom)
            LinearGradient(stops: [
                .init(color: .clear, location: 0.0),
                .init(color: Color.white.opacity(scheme == .dark ? 0.06 : 0.45), location: 0.42),
                .init(color: .clear, location: 0.58)
            ], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .ignoresSafeArea()
    }
}

struct ProgressRing: View {
    let progress: Double
    let lineWidth: CGFloat
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Palette.of(scheme)
        let shown = max(0.001, progress)
        ZStack {
            Circle()
                .stroke(p.stroke, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(
                    AngularGradient(colors: [p.gold.opacity(0.5), p.gold], center: .center,
                                    startAngle: .degrees(0), endAngle: .degrees(360 * shown)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.25), value: progress)
        }
    }
}

/// 艶のあるボタン。prominent は白鍵（ダーク）／黒鍵（ライト）のような主ボタン
struct LacquerButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        LacquerButtonBody(configuration: configuration, prominent: prominent)
    }
}

private struct LacquerButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Palette.of(scheme)
        configuration.label
            .font(.system(size: prominent ? 22 : 20, weight: .semibold))
            .foregroundStyle(prominent ? p.base : p.text)
            .padding(.horizontal, prominent ? 36 : 0)
            .frame(minWidth: prominent ? 180 : 64, minHeight: prominent ? 72 : 64)
            .background(
                ZStack {
                    Capsule().fill(prominent ? p.text : p.surface)
                    Capsule().fill(LinearGradient(colors: [Color.white.opacity(prominent ? 0.22 : 0.10), .clear],
                                                  startPoint: .top, endPoint: .center))
                }
            )
            .overlay(Capsule().strokeBorder(prominent ? p.gold.opacity(0.7) : p.stroke, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
