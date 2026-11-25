import Foundation

/// Tokens invalidate delayed focus requests when search is closed or reopened.
struct SearchPresentation: Equatable {
    enum Stage { case closed, expanded, raised }
    private(set) var stage: Stage = .closed
    private(set) var requestID = UUID()
    var isOpen: Bool { stage != .closed }
    mutating func open() {
        guard !isOpen else { return }
        requestID = UUID(); stage = .expanded
    }
    mutating func close() {
        guard isOpen else { return }
        requestID = UUID(); stage = .closed
    }
    @discardableResult mutating func raise(request: UUID) -> Bool {
        guard request == requestID, stage == .expanded else { return false }
        stage = .raised; return true
    }
    func mayFocus(request: UUID) -> Bool { request == requestID && stage == .raised }
}

enum PresentationMotion {
    static let searchExpansionDelay: TimeInterval = 0.75
    static let keyboardFocusDelay: TimeInterval = 0.15
    struct RevealStep: Equatable {
        let id: String
        let wait: TimeInterval
    }
    static func menuSequence(ids: [String], reduceMotion: Bool) -> [RevealStep] {
        ids.reversed().enumerated().map { index,id in
            RevealStep(id:id,wait:index == 0 || reduceMotion ? 0 : 0.25)
        }
    }
}
