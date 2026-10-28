import SafariServices
import SwiftUI

/// OAuth runs in the system browser so its HttpOnly state cookie stays with the
/// callback. No Ritm session is injected into Safari or included in a URL.
struct IntegrationBrowser: UIViewControllerRepresentable {
  var onDismiss: () -> Void = {}

  func makeCoordinator() -> Coordinator { Coordinator(onDismiss: onDismiss) }

  func makeUIViewController(context: Context) -> SFSafariViewController {
    // The only internal integration entrypoint. Caller-supplied destinations
    // cannot change the OAuth host or smuggle credentials through query data.
    let safe = URL(string: "https://ritm-eta-hazel.vercel.app/#settings")!
    let controller = SFSafariViewController(url: safe)
    controller.delegate = context.coordinator
    controller.preferredControlTintColor = UIColor(RitmTheme.lavender)
    controller.dismissButtonStyle = .done
    return controller
  }
  func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}

  final class Coordinator: NSObject, SFSafariViewControllerDelegate {
    let onDismiss: () -> Void
    init(onDismiss: @escaping () -> Void) { self.onDismiss = onDismiss }
    func safariViewControllerDidFinish(_ controller: SFSafariViewController) { onDismiss() }
  }
}
