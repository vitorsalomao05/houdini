import SwiftUI

struct ConnectionActionsView: View {
    @ObservedObject var session: SubscriptionSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(session.isSigningIn ? "Waiting for browser…" : "Connect \(session.displayName)…") {
                    session.signIn()
                }
                .disabled(session.isSigningIn)
                if session.isSigningIn {
                    Button("Cancel") { session.cancelSignIn() }
                }
            }
            if let error = session.lastError {
                Text(error).font(.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Connection error: \(error)")
            }
            Link(session.setupLabel, destination: session.setupURL)
                .font(.caption)
        }
    }
}
