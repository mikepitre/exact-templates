// Clerk, with clerk-ios's own views: UserButton, showing Sign in (which opens AuthView) until someone signs in.
// On iOS it sits in the shop and account screens' navigation bars; on macOS, in the window's toolbar.
// clerk-ios is prebuilt into Clerk.xcframework by scripts/clerk-ios.sh (`bun exact.mjs clerk`).
import ClerkKit
import ClerkKitUI
import SwiftUI

/// Your instance's publishable key (Clerk Dashboard, API keys). It is public; server.ts reads the same one from .env.
private let publishableKey = ""

@MainActor
enum SoftwearClerk {
    /// Starts Clerk, and calls `userChanged` whenever someone signs in or out.
    static func configure(userChanged: @escaping @MainActor () -> Void) {
        // clerk-ios's resource bundles ship in the app's assets (scripts/clerk-ios.sh).
        #if os(macOS)
        let resources = (Bundle.main.resourcePath ?? "") + "/assets/clerk/macos"
        #else
        let resources = Bundle.main.bundlePath + "/assets/clerk/ios"
        #endif
        setenv("PACKAGE_RESOURCE_BUNDLE_PATH", resources, 1)
        Clerk.configure(publishableKey: publishableKey)
        watch(userChanged)
    }

    private static func watch(_ userChanged: @escaping @MainActor () -> Void) {
        withObservationTracking { _ = Clerk.shared.user?.id } onChange: {
            Task { @MainActor in
                userChanged()
                watch(userChanged)
            }
        }
    }

    /// The signed-in person's email, or "".
    static var email: String { Clerk.shared.user?.primaryEmailAddress?.emailAddress ?? "" }

    /// A session token for the store's API (clerk-ios caches and refreshes it), or "" while signed out.
    static func token() async throws -> String { try await Clerk.shared.session?.getToken() ?? "" }

    /// UserButton, with Clerk and Softwear's brand colour.
    fileprivate static var accountButton: some View {
        AccountButton()
            .environment(Clerk.shared)
            .environment(\.clerkTheme, ClerkTheme(colors: .init(primary: Color(red: 0.66, green: 0.29, blue: 0.16))))
    }

    /// The account buttons' hosts, kept for the app's life.
    fileprivate static var buttons: [AnyObject] = []
}

/// clerk-ios's UserButton, showing Sign in (which opens AuthView) until someone signs in.
private struct AccountButton: View {
    @State private var signingIn = false

    var body: some View {
        UserButton {
            Button("Sign in") { signingIn = true }
                .padding(.horizontal, 8)
        }
        .sheet(isPresented: $signingIn) { AuthView() }
        // Its own size, "Sign in" or the photo, not the size the bar last gave it.
        .fixedSize()
    }
}

#if os(macOS)
import AppKit

extension SoftwearClerk {
    /// Puts UserButton at the end of the window's toolbar.
    static func addAccountButton(to toolbar: ExactToolbar) {
        let item = NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier("account"))
        item.view = NSHostingView(rootView: accountButton)
        buttons.append(item)
        toolbar.add(item)
    }
}
#else
import UIKit

extension SoftwearClerk {
    /// Puts UserButton at the trailing end of a screen's navigation bar.
    static func addAccountButton(to screen: UIViewController) {
        buttons.append(NavigationBarButton(rootView: accountButton, screen: screen))
    }
}

/// Hosts SwiftUI as a screen's trailing navigation bar button. The bar is outside the screen's view controllers, so
/// the sheets the SwiftUI view opens (AuthView, UserButton's profile) are presented and dismissed by the screen.
private final class NavigationBarButton<Content: View>: UIHostingController<Content> {
    private weak var screen: UIViewController?

    init(rootView: Content, screen: UIViewController) {
        self.screen = screen
        super.init(rootView: rootView)
        sizingOptions = .intrinsicContentSize
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        screen.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: view)
    }

    required init?(coder: NSCoder) { nil }

    override func present(_ sheet: UIViewController, animated: Bool, completion: (() -> Void)? = nil) {
        screen?.present(sheet, animated: animated, completion: completion)
    }

    override func dismiss(animated: Bool, completion: (() -> Void)? = nil) {
        screen?.dismiss(animated: animated, completion: completion)
    }
}
#endif
