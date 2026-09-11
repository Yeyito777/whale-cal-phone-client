import SwiftUI
import UIKit

/// Keep both SwiftUI trees mounted. Dragging only updates UIKit transforms/alpha,
/// never rebuilds the calendar or combines a transition with a drag-state reset.
struct CalendarDrawerSurface<Content: View, Drawer: View>: UIViewControllerRepresentable {
    @Environment(\.whaleTheme) private var theme
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
                          gesturesEnabled: gesturesEnabled, reduceMotion: reduceMotion, theme: theme)
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
    private var pendingRoots: (content: AnyView, drawer: AnyView)?
    private var interactionVisible = false
    private var drawerWidth: CGFloat = 0
    private var lastSize = CGSize.zero
    private var lastBottomInset: CGFloat = -1
    private var progress: CGFloat = 0
    private var targetOpen = false
    private var dragging = false
    private var dragStart: CGFloat = 0
    private var openAtDragStart = false
    private var interruptedScroll: UIScrollView?
    private var gesturesEnabled = true
    private var reduceMotion = false
    private var theme = CalendarThemeName.dark.palette
    var onPresentationChange: ((Bool) -> Void)?

    init(content: AnyView, drawer: AnyView) {
        contentHost = UIHostingController(rootView: content)
        drawerHost = UIHostingController(rootView: drawer)
        // The off-screen panel must not gain changing insets as it slides
        // onscreen. Its stable bottom clearance is applied in UIKit layout.
        drawerHost.safeAreaRegions = []
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(content:drawer:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(theme.background)
        view.clipsToBounds = true
        mount(contentHost, in: view)
        shade.backgroundColor = .black
        shade.addTarget(self, action: #selector(dismissDrawer), for: .touchUpInside)
        shade.isAccessibilityElement = true
        shade.accessibilityLabel = "Dismiss calendars"
        shade.accessibilityTraits = .button
        view.addSubview(shade)
        panel.backgroundColor = UIColor(theme.sidebar)
        panel.layer.shadowColor = UIColor.black.cgColor
        panel.layer.shadowOpacity = 0.25
        panel.layer.shadowRadius = 12
        panel.layer.shadowOffset = CGSize(width: 4, height: 0)
        view.addSubview(panel)
        mount(drawerHost, in: panel)
        border.backgroundColor = UIColor(theme.line)
        panel.addSubview(border)
        pan.delegate = self
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = true
        view.addGestureRecognizer(pan)
        interactionVisible = !targetOpen // Force the initial accessibility state.
        setInteractionVisible(targetOpen)
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
        let bottomInset = view.safeAreaInsets.bottom
        guard view.bounds.size != lastSize || bottomInset != lastBottomInset else { return }
        let wasAnimating = animator != nil
        interruptAnimation()
        lastSize = view.bounds.size
        lastBottomInset = bottomInset
        drawerWidth = min(320, view.bounds.width * 0.82)
        contentHost.view.frame = view.bounds
        shade.frame = view.bounds
        panel.transform = .identity
        panel.frame = CGRect(x: -drawerWidth, y: 0, width: drawerWidth, height: view.bounds.height)
        // Keep the footer tappable above the home indicator while the panel
        // background (and main scroll surface) extends all the way to the edge.
        drawerHost.view.frame = panel.bounds.inset(by: UIEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0))
        border.frame = CGRect(x: drawerWidth - 1, y: 0, width: 1, height: panel.bounds.height)
        panel.layer.shadowPath = UIBezierPath(rect: panel.bounds).cgPath
        apply(progress: progress)
        if wasAnimating && !dragging { settle(open: targetOpen, notify: false) }
    }

    func update(content: AnyView, drawer: AnyView, open: Bool, gesturesEnabled: Bool, reduceMotion: Bool, theme: WhalePalette) {
        if self.theme.name != theme.name {
            self.theme = theme
            if isViewLoaded {
                UIView.performWithoutAnimation {
                    view.backgroundColor = UIColor(theme.background)
                    panel.backgroundColor = UIColor(theme.sidebar)
                    border.backgroundColor = UIColor(theme.line)
                }
            }
        }
        // Binding changes and live snapshots can arrive during a pan/settle.
        // Don't replace hosting roots (and trigger layout) on an animation frame.
        pendingRoots = (content, drawer)
        flushPendingRoots()
        self.gesturesEnabled = gesturesEnabled
        self.reduceMotion = reduceMotion
        if open != targetOpen {
            settle(open: open, notify: false)
        }
    }

    private func flushPendingRoots() {
        guard !dragging, animator == nil, let roots = pendingRoots else { return }
        pendingRoots = nil
        UIView.performWithoutAnimation {
            contentHost.rootView = roots.content
            drawerHost.rootView = roots.drawer
        }
    }

    private func apply(progress: CGFloat) {
        self.progress = min(max(progress, 0), 1)
        panel.transform = CGAffineTransform(translationX: drawerWidth * self.progress, y: 0)
        shade.alpha = 0.45 * self.progress
    }

    private func setInteractionVisible(_ visible: Bool) {
        // Accessibility-tree and hit-testing changes aren't animation properties.
        // In particular, don't switch the underlying scroll tree off mid-pan.
        guard interactionVisible != visible else { return }
        interactionVisible = visible
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

    private func settle(open: Bool, notify: Bool, velocity: CGFloat = 0) {
        interruptAnimation()
        targetOpen = open
        guard isViewLoaded else { progress = open ? 1 : 0; return }
        let end: CGFloat = open ? 1 : 0
        guard !reduceMotion, drawerWidth > 0, view.window != nil, abs(end - progress) > 0.001 else {
            UIView.performWithoutAnimation { apply(progress: end) }
            setInteractionVisible(open)
            if notify { onPresentationChange?(open) }
            flushPendingRoots()
            return
        }
        // Match the release speed instead of restarting a fixed ease-out curve.
        // A monotone cubic stops without spring bounce or overshooting the edge.
        let motion = CalendarDrawerInteraction.settleMotion(distance: (end - progress) * drawerWidth, velocity: velocity)
        let timing = UICubicTimingParameters(
            controlPoint1: CGPoint(x: 1.0 / 3.0, y: motion.firstControlY),
            controlPoint2: CGPoint(x: 2.0 / 3.0, y: 1))
        let animation = UIViewPropertyAnimator(duration: motion.duration, timingParameters: timing)
        animation.addAnimations { [weak self] in self?.apply(progress: end) }
        animator = animation
        setInteractionVisible(true)
        if notify { onPresentationChange?(open) }
        animation.addCompletion { [weak self, weak animation] _ in
            guard let self, self.animator === animation else { return }
            self.animator = nil
            self.setInteractionVisible(self.targetOpen)
            self.flushPendingRoots()
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
            // UIPan has already accumulated its recognition slop. Applying that
            // first delta makes the drawer jump ~10pt as it catches the finger.
            recognizer.setTranslation(.zero, in: view)
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
            settle(open: open, notify: true, velocity: recognizer.velocity(in: view).x)
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
        setInteractionVisible(targetOpen)
        flushPendingRoots()
    }

    override func accessibilityPerformEscape() -> Bool {
        guard targetOpen || progress > 0 else { return false }
        dismissDrawer()
        return true
    }
}
