import SwiftUI

struct GhostMenuItem: Identifiable {
    let id: String
    let title: String
    let symbol: String
    var selected = false
    let action: () -> Void
}

/// App-owned menus share one cancellable, bottom-to-top reveal sequence.
struct GhostDropdown<Label: View>: View {
    let items: [GhostMenuItem]
    @ViewBuilder var label: () -> Label
    @State private var open = false
    @State private var presentationID = UUID()
    var body: some View {
        Button { if !open { presentationID = UUID() }; open.toggle() } label: { label() }
            .popover(isPresented:$open,attachmentAnchor:.rect(.bounds),arrowEdge:.bottom) {
                GhostMenuChoices(items:items) { item in
                    open = false
                    // Finish dismissing the popover before presenting another surface.
                    DispatchQueue.main.asyncAfter(deadline:.now()+0.18) { item.action() }
                }.id(presentationID)
                    .presentationCompactAdaptation(.popover)
                    .presentationBackground(.clear)
            }
    }
}

private struct GhostMenuChoices: View {
    let items: [GhostMenuItem]
    let choose: (GhostMenuItem) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible: Set<String> = []
    var body: some View {
        GhostGlassGroup {
            VStack(spacing:8) {
                ForEach(items) { item in
                    Button {
                        choose(item)
                    } label: {
                        HStack(spacing:12) {
                            Image(systemName:item.symbol).frame(width:22)
                            Text(item.title).font(.subheadline.weight(.medium))
                            Spacer(minLength:8)
                            if item.selected { Image(systemName:"checkmark").font(.caption.bold()) }
                        }.padding(.horizontal,16).frame(minHeight:46)
                    }
                    .buttonStyle(.plain)
                    .ghostGlass(cornerRadius:16,interactive:true)
                    .opacity(visible.contains(item.id) ? 1 : 0)
                    .scaleEffect(x:visible.contains(item.id) ? 1 : 0.94,y:visible.contains(item.id) ? 1 : 0.65,anchor:.bottom)
                    .offset(y:visible.contains(item.id) ? 0 : 18)
                    .allowsHitTesting(visible.contains(item.id))
                    .accessibilityHidden(!visible.contains(item.id))
                }
            }.padding(12).frame(width:260)
        }
        .task {
            for step in PresentationMotion.menuSequence(ids:items.map(\.id),reduceMotion:reduceMotion) {
                if step.wait > 0 {
                    do { try await Task.sleep(for:.seconds(step.wait)) } catch { return }
                }
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? nil : .spring(response:0.36,dampingFraction:0.86)) {
                    _ = visible.insert(step.id)
                }
            }
        }
    }
}
