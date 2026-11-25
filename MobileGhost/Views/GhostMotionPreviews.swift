#if DEBUG
import SwiftUI

/// Isolated controls: previews never connect to a device or run a simulation.
private struct GhostMotionPreview: View {
    @State private var selected = "Route"
    @State private var expanded = false
    var body: some View {
        VStack(spacing:24) {
            GhostDropdown(items:[
                GhostMenuItem(id:"walking",title:"Walking",symbol:"figure.walk",action:{}),
                GhostMenuItem(id:"saved",title:"Saved places",symbol:"bookmark",action:{}),
                GhostMenuItem(id:"settings",title:"Settings",symbol:"gearshape",action:{})
            ]) { Image(systemName:"gearshape").frame(width:48,height:48) }
                .ghostGlass(cornerRadius:17,interactive:true)
            GhostPanelSurface(title:"Selected location",subtitle:"Ready to move",expanded:$expanded,close:{}) {
                VStack(spacing:20) {
                    Text("Village 1").font(.headline)
                    Text("A larger glass panel with room for location controls.")
                    Button("Set location") {}.buttonStyle(.borderedProminent)
                    Spacer()
                }.padding()
            }.frame(height:330)
            GhostDockTabs(selection:$selected,openRoute:{},openSchedules:{})
        }.padding(24).background(Color.gray.opacity(0.25)).preferredColorScheme(.dark)
    }
}
#Preview("Glass controls and motion") { GhostMotionPreview() }
#endif
