import SwiftUI

/// Place details, route planning, and schedules use the same surface and handle.
struct GhostPanelSurface<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @Binding var expanded: Bool
    var editable = false
    let close: () -> Void
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing:0) {
            VStack(spacing:14) {
                Capsule().fill(.secondary.opacity(0.5)).frame(width:42,height:4)
                    .frame(maxWidth:.infinity,minHeight:28)
                Rectangle().fill(GhostPalette.border).frame(height:1)
            }
            .padding(.horizontal,18)
            .contentShape(Rectangle())
            .onTapGesture { expanded.toggle() }
            .gesture(DragGesture(minimumDistance:15).onEnded { value in
                if value.translation.height < -15 { expanded = true }
                else if value.translation.height > 15 {
                    if expanded { expanded = false } else { close() }
                }
            })
            .accessibilityElement(children:.ignore)
            .accessibilityLabel(expanded ? "Collapse panel" : "Expand panel")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { expanded.toggle() }
            HStack(alignment:.top,spacing:10) {
                VStack(alignment:.leading,spacing:5) {
                    Text(title).font(.system(size:22,weight:.semibold))
                    if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer(minLength:4)
                if editable { EditButton().font(.subheadline).frame(minHeight:44) }
                Button(action:close) { Image(systemName:"xmark").frame(width:44,height:44) }
                    .accessibilityLabel("Close \(title)")
            }.padding(.horizontal,20).padding(.top,12).padding(.bottom,8)
            content().frame(maxWidth:.infinity,maxHeight:.infinity)
        }
        .ghostGlass(cornerRadius:28)
        .clipShape(RoundedRectangle(cornerRadius:28,style:.continuous))
    }
}
