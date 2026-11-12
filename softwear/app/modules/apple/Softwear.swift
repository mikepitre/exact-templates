// Softwear's native module: the zoomable product photo (ZoomImage.swift) and Clerk (Clerk.swift).
//
//   views   zoom-image          a product photo that pinches and pans
//   call    {op: "user"}        who is signed in: {email}, "" for no one
//   later   {op: "token"}       a Clerk session token for the store's API: {token}
//   topic   "user"              changes when someone signs in or out
//   routes  data-clerk          get UserButton (Sign in until someone signs in) in their navigation bar (iOS)
//   toolbar                     gets UserButton (macOS)
import Foundation

final class Softwear: ExactModule {
    override class var views: [String: ExactNativeFactory] {
        ["zoom-image": ExactNativeFactory(for: Softwear.self) { _, props, events in try ZoomImage(props: props, events: events) }]
    }

    required init(context: ExactModuleContext) {
        super.init(context: context)
        MainActor.assumeIsolated {
            SoftwearClerk.configure { [weak self] in self?.context.changed("user") }
        }
    }

    override func call(_ request: [String: Any]) throws -> [String: Any] {
        guard request["op"] as? String == "user" else { throw ExactNativeRefusal("Softwear answers user") }
        return MainActor.assumeIsolated { ["email": SoftwearClerk.email] }
    }

    override func later(_ request: [String: Any], reply: ExactReply) {
        guard request["op"] as? String == "token" else { return reply.fail("Softwear answers token") }
        Task { @MainActor in
            do { reply.send(["token": try await SoftwearClerk.token()]) }
            catch { reply.fail("\(error)") }
        }
    }

    #if os(macOS)
    override func toolbar(_ toolbar: ExactToolbar) {
        MainActor.assumeIsolated { SoftwearClerk.addAccountButton(to: toolbar) }
    }
    #else
    override func route(_ route: ExactRoute) {
        guard route.isNew, route.data[.clerk] != nil else { return }
        MainActor.assumeIsolated { SoftwearClerk.addAccountButton(to: route.controller) }
    }
    #endif
}

let exactModule: ExactModule.Type = Softwear.self
