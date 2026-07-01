//
//  SwipeablePager.swift
//  PillCounter
//
//  A two-page horizontal pager backed by UIPageViewController. Unlike a
//  `.page`-style SwiftUI `TabView`, it reliably honors a programmatic `selection`
//  binding even when nested inside a fixed-frame `GeometryReader` — so both swipe
//  gestures and tab-header taps animate between pages. Used by DashboardView's
//  Today's Queue / Recent Activity tabs across all layouts.
//

import SwiftUI
import UIKit

struct SwipeablePager<Page: View>: UIViewControllerRepresentable {

    @Binding var selection: Int
    /// Builds the page for a given index (0 or 1).
    let page: (Int) -> Page

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pager = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal
        )
        pager.dataSource = context.coordinator
        pager.delegate = context.coordinator
        pager.view.backgroundColor = .clear

        // Let nested vertical ScrollViews receive their own pan — the page view's
        // horizontal pan handles left/right paging.
        for case let scroll as UIScrollView in pager.view.subviews {
            scroll.backgroundColor = .clear
        }

        let initial = context.coordinator.controller(for: selection)
        pager.setViewControllers(
            [initial],
            direction: .forward,
            animated: false
        )

        // Re-install the current page after foreground return. UIPageViewController
        // can silently drop its child on background/foreground and not call any
        // delegate, so the coordinator's currentIndex stays in sync with `selection`
        // and updateUIViewController's guard skips the re-set — leaving the pager blank.
        context.coordinator.foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak pager] _ in
            guard let pager else { return }
            let idx = context.coordinator.currentIndex
            let vc = context.coordinator.controller(for: idx)
            pager.setViewControllers([vc], direction: .forward, animated: false)
        }

        return pager
    }

    func updateUIViewController(
        _ pager: UIPageViewController,
        context: Context
    ) {
        context.coordinator.parent = self

        // Refresh hosted content so data changes (filters, new items) re-render.
        context.coordinator.refreshHostedContent()

        // If UIPageViewController has lost its visible child (e.g. after a
        // background/foreground cycle, UIKit can discard the hosted content
        // without notifying the coordinator), restore it non-animated so the
        // pager is never blank on foreground return.
        if pager.viewControllers?.isEmpty ?? true {
            let restore = context.coordinator.controller(for: selection)
            pager.setViewControllers([restore], direction: .forward, animated: false)
            context.coordinator.currentIndex = selection
            return
        }

        let current = context.coordinator.currentIndex
        guard current != selection else { return }

        // Programmatic selection change (e.g. tab-header tap) — animate-paginate.
        let direction: UIPageViewController.NavigationDirection =
            selection > current ? .forward : .reverse
        let target = context.coordinator.controller(for: selection)
        context.coordinator.currentIndex = selection
        pager.setViewControllers(
            [target],
            direction: direction,
            animated: true
        )
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject,
        UIPageViewControllerDataSource,
        UIPageViewControllerDelegate
    {
        var parent: SwipeablePager
        var currentIndex: Int
        var foregroundObserver: Any?
        // One hosting controller per page, reused so swipe + programmatic paging
        // navigate between stable instances.
        private var hosts: [Int: UIHostingController<Page>] = [:]

        init(_ parent: SwipeablePager) {
            self.parent = parent
            self.currentIndex = parent.selection
        }

        deinit {
            if let obs = foregroundObserver {
                NotificationCenter.default.removeObserver(obs)
            }
        }

        func controller(for index: Int) -> UIHostingController<Page> {
            if let existing = hosts[index] {
                existing.rootView = parent.page(index)
                return existing
            }
            let host = UIHostingController(rootView: parent.page(index))
            host.view.backgroundColor = .clear
            host.view.tag = index
            hosts[index] = host
            return host
        }

        /// Push fresh SwiftUI content into the already-visible hosts.
        func refreshHostedContent() {
            for (index, host) in hosts {
                host.rootView = parent.page(index)
            }
        }

        // MARK: DataSource (swipe paging between the 2 pages)

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerBefore viewController: UIViewController
        ) -> UIViewController? {
            viewController.view.tag == 1 ? controller(for: 0) : nil
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerAfter viewController: UIViewController
        ) -> UIViewController? {
            viewController.view.tag == 0 ? controller(for: 1) : nil
        }

        // MARK: Delegate (sync binding back after a swipe)

        func pageViewController(
            _ pageViewController: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            guard completed,
                let visible = pageViewController.viewControllers?.first
            else { return }
            let index = visible.view.tag
            currentIndex = index
            if parent.selection != index {
                parent.selection = index
            }
        }
    }
}
