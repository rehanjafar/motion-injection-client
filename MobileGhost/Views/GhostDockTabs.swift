import SwiftUI

private struct DockHighlight {
    var position: CGFloat = 0
    var stretch: CGFloat = 1
}

/// Only the lightweight highlight animates every frame; route state stays outside.
struct GhostDockTabs: View {
    @Binding var selection: String
    let openRoute: () -> Void
    let openSchedules: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var initialPosition: CGFloat
    init(selection: Binding<String>, openRoute: @escaping () -> Void, openSchedules: @escaping () -> Void) {
        _selection = selection; self.openRoute = openRoute; self.openSchedules = openSchedules
        _initialPosition = State(initialValue:selection.wrappedValue == "Route" ? 0 : 1)
    }
    var body: some View {
        GeometryReader { geometry in
            let width = (geometry.size.width - 10) / 2
            ZStack(alignment:.leading) {
                if reduceMotion {
                    highlight(width:width).offset(x:5 + (selection == "Route" ? 0 : width))
                } else {
                    KeyframeAnimator(initialValue:DockHighlight(position:initialPosition),trigger:selection) { value in
                        highlight(width:width * value.stretch)
                            .offset(x:5 + width * value.position + width * (1-value.stretch)/2)
                    } keyframes: { _ in
                        KeyframeTrack(\.position) {
                            CubicKeyframe(selection == "Route" ? CGFloat(0) : CGFloat(1),duration:0.48,startVelocity:0,endVelocity:0)
                        }
                        KeyframeTrack(\.stretch) {
                            CubicKeyframe(CGFloat(1.25),duration:0.17,startVelocity:0,endVelocity:0)
                            CubicKeyframe(CGFloat(1),duration:0.31,startVelocity:0,endVelocity:0)
                        }
                    }
                }
                HStack(spacing:0) {
                    tab("Route",action:openRoute)
                    tab("Scheduled",action:openSchedules)
                }.padding(5)
            }
        }.frame(height:54)
            .ghostGlass(cornerRadius:20)
            .clipShape(RoundedRectangle(cornerRadius:20))
    }
    private func highlight(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius:15)
            .fill(.white.opacity(0.17))
            .overlay(RoundedRectangle(cornerRadius:15).strokeBorder(.white.opacity(0.24)))
            .frame(width:width,height:44)
    }
    private func tab(_ title: String, action: @escaping () -> Void) -> some View {
        Button { selection = title; action() } label: {
            Text(title).font(.system(size:14,weight:.semibold)).frame(maxWidth:.infinity,minHeight:44)
        }.buttonStyle(.plain)
            .accessibilityAddTraits(selection == title ? [.isSelected] : [])
    }
}
