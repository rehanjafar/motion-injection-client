import SwiftUI

enum GhostPalette {
    static let background = Color(uiColor:.systemBackground)
    static let accent = Color.primary
    static let secondary = Color.secondary
    static let border = Color.primary.opacity(0.12)
}

private struct GhostGlass: ViewModifier {
    var cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius:cornerRadius,style:.continuous)
        if reduceTransparency {
            content.background(Color(uiColor:.secondarySystemBackground),in:shape)
                .overlay(shape.strokeBorder(GhostPalette.border))
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular,in:shape)
        } else {
            content.background(.regularMaterial,in:shape)
                .overlay(shape.strokeBorder(.white.opacity(0.35)))
                .shadow(color:.black.opacity(0.08),radius:12,y:4)
        }
    }
}
extension View {
    func ghostGlass(cornerRadius: CGFloat) -> some View {
        modifier(GhostGlass(cornerRadius:cornerRadius))
    }
}
