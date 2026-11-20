import SwiftUI

/// グレージュの壁紙に、墨色の太いセリフ体。ホーム画面のウィジェットのような見た目
struct Palette {
    let base: Color       // 壁紙
    let text: Color       // 墨色の文字
    let subtext: Color
    let tileLight: Color  // 明るいタイル
    let tileDark: Color   // 濃いタイル（選択中・主ボタン）
    let onDark: Color     // 濃いタイルの上の文字
    let stroke: Color
    let accent: Color

    static func of(_ scheme: ColorScheme) -> Palette {
        if scheme == .dark {
            return Palette(
                base: Color(red: 0.16, green: 0.157, blue: 0.15),
                text: Color(red: 0.93, green: 0.92, blue: 0.90),
                subtext: Color(red: 0.68, green: 0.67, blue: 0.65),
                tileLight: Color(red: 0.25, green: 0.245, blue: 0.235),
                tileDark: Color(red: 0.86, green: 0.85, blue: 0.83),
                onDark: Color(red: 0.12, green: 0.115, blue: 0.11),
                stroke: Color.white.opacity(0.08),
                accent: Color(red: 0.93, green: 0.92, blue: 0.90)
            )
        } else {
            return Palette(
                base: Color(red: 0.66, green: 0.65, blue: 0.635),
                text: Color(red: 0.11, green: 0.105, blue: 0.10),
                subtext: Color(red: 0.27, green: 0.265, blue: 0.255),
                tileLight: Color(red: 0.74, green: 0.73, blue: 0.715),
                tileDark: Color(red: 0.27, green: 0.265, blue: 0.255),
                onDark: Color(red: 0.94, green: 0.93, blue: 0.91),
                stroke: Color.black.opacity(0.06),
                accent: Color(red: 0.11, green: 0.105, blue: 0.10)
            )
        }
    }
}

/// 壁紙。上をほんの少し明るくする
struct GreigeBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Palette.of(scheme)
        LinearGradient(colors: [p.base.opacity(0.92), p.base], startPoint: .top, endPoint: .bottom)
            .background(p.base)
            .ignoresSafeArea()
    }
}

/// 細い進み具合の線
struct ProgressLine: View {
    let progress: Double
    var color: Color? = nil
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let tint = color ?? Palette.of(scheme).text
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.2))
                Capsule().fill(tint)
                    .frame(width: max(3, g.size.width * min(1, max(0, progress))))
            }
        }
        .animation(.linear(duration: 0.25), value: progress)
    }
}

/// 押したときに少し縮むだけのボタン
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension Font {
    /// 太いセリフ体
    static func serif(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}
