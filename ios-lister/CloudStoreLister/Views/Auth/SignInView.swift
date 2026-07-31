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
            Text("Cloud Store 893 Lister")
                .font(.title.bold())
            Text("Inventory Checker")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Text(hostLabel)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Button(action: onSignIn) {
                Label("Sign In", systemImage: "person.badge.key")
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
