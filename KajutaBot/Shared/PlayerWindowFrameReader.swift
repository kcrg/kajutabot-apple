import SwiftUI
import UIKit

/// GeometryProxy's global space belongs to a hosting hierarchy. Convert to the
/// containing window when connecting the system accessory with a tab's content.
struct PlayerWindowFrameReader: UIViewRepresentable {
    let layoutSignal: CGRect
    var identity: PlayerTransitionIdentity? = nil
    var refreshID: UUID? = nil
    let onChange: @MainActor (CGRect) -> Void

    func makeUIView(context: Context) -> FrameView {
        let view = FrameView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ view: FrameView, context: Context) {
        if view.identity != identity || view.refreshID != refreshID {
            view.lastFrame = nil
        }
        view.identity = identity
        view.refreshID = refreshID
        view.onChange = onChange
        // layoutSignal changes also invalidate coordinates after scrolling.
        view.scheduleReport()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: FrameView, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width, height: height)
    }

    static func dismantleUIView(_ view: FrameView, coordinator: Void) {
        view.onChange = nil
    }

    final class FrameView: UIView {
        var identity: PlayerTransitionIdentity?
        var refreshID: UUID?
        var lastFrame: CGRect?
        var onChange: (@MainActor (CGRect) -> Void)?
        private var reportScheduled = false

        override func layoutSubviews() {
            super.layoutSubviews()
            scheduleReport()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            lastFrame = nil
            scheduleReport()
        }

        func scheduleReport() {
            guard !reportScheduled else { return }
            reportScheduled = true
            // Publish after layout, without mutating SwiftUI state during an update.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.reportScheduled = false
                guard let window = self.window else { return }
                var ancestor: UIView? = self
                while let view = ancestor {
                    guard !view.isHidden else { return }
                    ancestor = view.superview
                }
                let frame = self.convert(self.bounds, to: window)
                guard !frame.isEmpty, frame != self.lastFrame else { return }
                self.lastFrame = frame
                self.onChange?(frame)
            }
        }
    }
}
