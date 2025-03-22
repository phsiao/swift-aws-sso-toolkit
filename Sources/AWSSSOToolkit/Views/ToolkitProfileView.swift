import SwiftUI
@preconcurrency import AWSSTS

public struct ToolkitProfileView: View {
  @SwiftUI.Environment(\.openURL) private var openURL

  @Binding private var profileViewModel: ProfileViewModel

  @State var presentAuthUri: Bool = false
  @State var authUriRecord: AuthUriRecord?
  @State var presentMessage: Bool = false
  @State var messageRecord: MessageRecord?

  public init(profile: Binding<ProfileViewModel>) {
    self._profileViewModel = profile
  }

  public var body: some View {
    HStack {
      Text(profileViewModel.profileState.profile.profileName)
        .contextMenu {
          HStack {
            Text("Expiration")
            CredentialExpirationView(profileViewModel: profileViewModel)
          }
          Divider()
          Button("Login") {
            Task {
              try await ssoLogin(profileViewModel: profileViewModel)
            }
          }
        }
    }
    .alert(isPresented: $presentAuthUri) {
      Alert(
        title: Text("Login via AWS SSO"),
        message: Text(
          "You now need to login via AWS SSO. Click the link below to open in your browser."
        ),
        primaryButton: .default(Text("Open")) {
          openURL(authUriRecord!.authUri)
        },
        secondaryButton: .cancel()
      )
    }
  }

  func ssoLogin(profileViewModel: ProfileViewModel) async throws {
    let profileState = profileViewModel.profileState
    let identityProvider = profileState.identityResolver
    let authUri = try await identityProvider.actor.setupAuth()

    await MainActor.run {
      authUriRecord = AuthUriRecord(authUri: authUri)
      presentAuthUri = true
    }

    try await identityProvider.actor.getToken()
    _ = try await identityProvider.actor.getRoleCredentials()

    switch profileState.profile.profileType {
    case .SSO(let session, _, _, _):
      let stsConfiguration = try await STSClient.STSClientConfiguration(
        awsCredentialIdentityResolver: identityProvider,
        region: session.region
      )
      let stsClient = STSClient(config: stsConfiguration)
      // print("making callerid call")
      let response = try await stsClient.getCallerIdentity(
        input: GetCallerIdentityInput())
      // print("done callerid call")

      profileViewModel.userArn = response.arn!
      await profileViewModel.updateExpirationTimes()
    }
  }
}
