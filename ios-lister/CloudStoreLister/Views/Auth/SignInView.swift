import SwiftUI

struct SignInView: View {
    let hostLabel: String
    let onSignIn: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 56))
                .foregroundStyle(Color.listerAccent)
            Text("Cloud Store Lister")
                .font(.title.bold())
            Text("Sign in with your store account to look up inventory.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Text(hostLabel)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Button(action: onSignIn) {
                Label("Sign in with Oracle", systemImage: "person.badge.key")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.listerAccent)
            .padding(.horizontal, 32)
            Spacer()
        }
        .padding()
    }
}

#if DEBUG
#Preview {
    SignInView(hostLabel: "oci.cloudstore893.com", onSignIn: {})
}
#endif
