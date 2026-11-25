import Foundation

@main struct PresentationChecks {
    static func main() {
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition,message); checks += 1
        }
        var search = SearchPresentation()
        check(!search.isOpen,"Search begins closed")
        search.open(); let original = search.requestID
        check(search.stage == .expanded && !search.mayFocus(request:original),"Expansion cannot focus keyboard early")
        search.close()
        check(!search.raise(request:original),"Closing invalidates pending rise")
        check(!search.mayFocus(request:original),"Closing invalidates pending focus")
        search.open(); let reopened = search.requestID
        check(reopened != original,"Reopening creates a new request")
        check(!search.raise(request:original),"An old task cannot raise a new search session")
        check(search.raise(request:reopened) && search.mayFocus(request:reopened),"Only current raised search may focus")
        check(!search.raise(request:reopened),"Rise is a single transition")
        search.close(); search.open()
        check(!search.mayFocus(request:reopened),"A previously raised session cannot steal focus after reopening")
        let steps = PresentationMotion.menuSequence(ids:["top","middle","bottom"],reduceMotion:false)
        check(steps.map(\.id) == ["bottom","middle","top"],"Menus reveal bottom to top")
        check(steps.map(\.wait) == [0,0.25,0.25],"Each subsequent row waits a quarter second")
        check(steps.reduce(0){$0+$1.wait} == 0.5,"Three rows complete their stagger within half a second")
        let reduced = PresentationMotion.menuSequence(ids:["top","bottom"],reduceMotion:true)
        check(reduced.map(\.wait) == [0,0],"Reduce Motion removes stagger delays")
        check(PresentationMotion.menuSequence(ids:[],reduceMotion:false).isEmpty,"Empty menus schedule nothing")
        print("Passed \(checks) presentation checks")
    }
}
