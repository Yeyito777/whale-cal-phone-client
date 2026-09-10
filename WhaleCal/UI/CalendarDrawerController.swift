import SwiftUI
import UIKit

/// Keep both SwiftUI trees mounted. Dragging only updates UIKit transforms/alpha,
/// never rebuilds the calendar or combines a transition with a drag-state reset.
struct CalendarDrawerSurface<Content: View, Drawer: View>: UIViewControllerRepresentable {
    let content: Content
    let drawer: Drawer
    @Binding var isPresented: Bool
    let gesturesEnabled: Bool
    let reduceMotion: Bool

    func makeUIViewController(context: Context) -> CalendarDrawerController {
        let controller = CalendarDrawerController(content: AnyView(content), drawer: AnyView(drawer))
        updateUIViewController(controller, context: context)
        return controller
    }

    func updateUIViewController(_ controller: CalendarDrawerController, context: Context) {
        controller.onPresentationChange = { isPresented = $0 }
        controller.update(content: AnyView(content), drawer: AnyView(drawer), open: isPresented,
                          gesturesEnabled: gesturesEnabled, reduceMotion: reduceMotion)
    }

    static func dismantleUIViewController(_ controller: CalendarDrawerController, coordinator: ()) {
        controller.stopInteraction()
    }
}

@MainActor
final class CalendarDrawerController: UIViewController, UIGestureRecognizerDelegate {
    private let contentHost: UIHostingController<AnyView>
    private let drawerHost: UIHostingController<AnyView>
    private let shade = UIControl()
    private let panel = UIView()
    private let border = UIView()
    private lazy var pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
    private var animator: UIViewPropertyAnimator?
    private var drawerWidth: CGFloat = 0
    private var lastSize = CGSize.zero
    private var progress: CGFloat = 0
    private var targetOpen = false
    private var dragging = false
    private var dragStart: CGFloat = 0
    private var openAtDragStart = false
    private var interruptedScroll: UIScrollView?
    private var gesturesEnabled = true
    private var reduceMotion = false
    var onPresentationChange: ((Bool) -> Void)?

    init(content: AnyView, drawer: AnyView) {
        contentHost = UIHostingController(rootView: content)
        drawerHost = UIHostingController(rootView: drawer)
        // The outer SwiftUI layout already provides the safe-area bounds. The
        // off-screen panel must not gain changing insets as it slides onscreen.
        drawerHost.safeAreaRegions = []
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(content:drawer:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(Whale.background)
        view.clipsToBounds = true
        mount(contentHost, in: view)
        shade.backgroundColor = .black
        shade.addTarget(self, action: #selector(dismissDrawer), for: .touchUpInside)
        shade.isAccessibilityElement = true
        shade.accessibilityLabel = "Dismiss calendars"
        shade.accessibilityTraits = .button
        view.addSubview(shade)
        panel.backgroundColor = UIColor(Whale.background)
        panel.layer.shadowColor = UIColor.black.cgColor
        panel.layer.shadowOpacity = 0.25
        panel.layer.shadowRadius = 12
        panel.layer.shadowOffset = CGSize(width: 4, height: 0)
        view.addSubview(panel)
        mount(drawerHost, in: panel)
        border.backgroundColor = UIColor(Whale.muted.opacity(0.2))
        panel.addSubview(border)
        pan.delegate = self
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = true
        view.addGestureRecognizer(pan)
        apply(progress: targetOpen ? 1 : 0)
    }

    private func mount(_ host: UIHostingController<AnyView>, in parent: UIView) {
        addChild(host)
        host.view.backgroundColor = .clear
        parent.addSubview(host.view)
        host.didMove(toParent: self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard view.bounds.size != lastSize else { return }
        let wasAnimating = animator != nil
        interruptAnimation()
        lastSize = view.bounds.size
        drawerWidth = min(320, view.bounds.width * 0.82)
        contentHost.view.frame = view.bounds
        shade.frame = view.bounds
        panel.transform = .identity
        panel.frame = CGRect(x: -drawerWidth, y: 0, width: drawerWidth, height: view.bounds.height)
        drawerHost.view.frame = panel.bounds
        border.frame = CGRect(x: drawerWidth - 1, y: 0, width: 1, height: panel.bounds.height)
        panel.layer.shadowPath = UIBezierPath(rect: panel.bounds).cgPath
        apply(progress: progress)
        if wasAnimating && !dragging { settle(open: targetOpen, notify: false) }
    }

    func update(content: AnyView, drawer: AnyView, open: Bool, gesturesEnabled: Bool, reduceMotion: Bool) {
        contentHost.rootView = content
        drawerHost.rootView = drawer
        self.gesturesEnabled = gesturesEnabled
        self.reduceMotion = reduceMotion
        if open != targetOpen {
            settle(open: open, notify: false)
        }
    }

    private func apply(progress: CGFloat) {
        self.progress = min(max(progress, 0), 1)
        panel.transform = CGAffineTransform(translationX: drawerWidth * self.progress, y: 0)
        shade.alpha = 0.45 * self.progress
        let visible = self.progress > 0.001
        panel.isUserInteractionEnabled = visible
        shade.isUserInteractionEnabled = visible
        shade.accessibilityElementsHidden = !visible
        drawerHost.view.accessibilityElementsHidden = !visible
        drawerHost.view.accessibilityViewIsModal = visible
        contentHost.view.accessibilityElementsHidden = visible
    }

    private func visibleProgress() -> CGFloat {
        guard drawerWidth > 0, let presentation = panel.layer.presentation() else { return progress }
        return min(max(presentation.affineTransform().tx / drawerWidth, 0), 1)
    }

    private func interruptAnimation() {
        guard let animator else { return }
        let visible = visibleProgress()
        animator.stopAnimation(true)
        self.animator = nil
        UIView.performWithoutAnimation { apply(progress: visible) }
    }

    private func settle(open: Bool, notify: Bool) {
        interruptAnimation()
        targetOpen = open
        if notify { onPresentationChange?(open) }
        guard isViewLoaded else { progress = open ? 1 : 0; return }
        let end: CGFloat = open ? 1 : 0
        guard !reduceMotion, drawerWidth > 0, view.window != nil, abs(end - progress) > 0.001 else {
            UIView.performWithoutAnimation { apply(progress: end) }
            return
        }
        // One non-bouncy animator, starting at the actual visible position. A new
        // pan can interrupt this animation without jumping to its model endpoint.
        let animation = UIViewPropertyAnimator(duration: 0.26, curve: .easeOut) { [weak self] in
            self?.apply(progress: end)
        }
        animator = animation
        animation.addCompletion { [weak self, weak animation] _ in
            guard let self, self.animator === animation else { return }
            self.animator = nil
        }
        animation.startAnimation()
    }

    @objc private func dismissDrawer() { settle(open: false, notify: true) }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === pan, gesturesEnabled || targetOpen else { return false }
        let velocity = pan.velocity(in: view)
        guard CalendarDrawerInteraction.isHorizontal(x: velocity.x, y: velocity.y) else { return false }
        let visible = visibleProgress()
        // Dense timeline lanes scroll horizontally. Keep the left edge available
        // for opening the drawer, without hijacking drags within those lanes.
        if visible < 0.001, pan.location(in: view).x > 24 {
            var touched = view.hitTest(pan.location(in: view), with: nil)
            while let candidate = touched, candidate !== view {
                if let scroll = candidate as? UIScrollView, scroll.contentSize.width > scroll.bounds.width + 1 { return false }
                touched = candidate.superview
            }
        }
        return (visible > 0.001 || velocity.x > 0) && (visible < 0.999 || velocity.x < 0)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        gestureRecognizer === pan && other.view is UIScrollView
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            interruptAnimation()
            dragging = true
            dragStart = progress
            openAtDragStart = targetOpen
            // Once horizontal intent is established, don't let a child scroll
            // view wobble vertically underneath the drawer. Vertical pans never
            // start this recognizer and retain normal scrolling behavior.
            var touched = view.hitTest(recognizer.location(in: view), with: nil)
            while let candidate = touched, candidate !== view {
                if let scroll = candidate as? UIScrollView, scroll.isScrollEnabled {
                    interruptedScroll = scroll
                    scroll.isScrollEnabled = false
                    break
                }
                touched = candidate.superview
            }
            updatePan(recognizer)
        case .changed:
            updatePan(recognizer)
        case .ended:
            updatePan(recognizer)
            let open = CalendarDrawerInteraction.settledOpen(progress: progress, velocity: recognizer.velocity(in: view).x, width: drawerWidth)
            finishPan()
            settle(open: open, notify: true)
        case .cancelled, .failed:
            guard dragging else { return }
            finishPan()
            settle(open: openAtDragStart, notify: true)
        default: break
        }
    }

    private func updatePan(_ recognizer: UIPanGestureRecognizer) {
        let position = CalendarDrawerInteraction.dragProgress(start: dragStart, translation: recognizer.translation(in: view).x, width: drawerWidth)
        UIView.performWithoutAnimation { apply(progress: position) }
    }

    private func finishPan() {
        dragging = false
        interruptedScroll?.isScrollEnabled = true
        interruptedScroll = nil
    }

    func stopInteraction() {
        interruptAnimation()
        finishPan()
        apply(progress: targetOpen ? 1 : 0)
    }

    override func accessibilityPerformEscape() -> Bool {
        guard targetOpen || progress > 0 else { return false }
        dismissDrawer()
        return true
    }
}
