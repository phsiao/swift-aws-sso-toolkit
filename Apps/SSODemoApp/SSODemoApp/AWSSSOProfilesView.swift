import SwiftUI
import AWSSTS
import SmithyIdentity
import AWSSSOToolkit
import os

struct AuthUriRecord: Identifiable {
  let id: UUID = UUID()
  let authUri: URL
}

struct MessageRecord: Identifiable {
  let id: UUID = UUID()
  let title: String
  let message: String
}

struct AWSSSOProfilesView: View {
  @SwiftUI.Environment(\.openURL) private var openURL
  @SwiftUI.Environment(ProfileStore.self) private var profileStore
  
  @State var presentAuthUri: Bool = false
  @State var authUriRecord: AuthUriRecord? = nil
  @State var presentMessage: Bool = false
  @State var messageRecord: MessageRecord? = nil
  @State var selectedProfiles: Set<ProfileState.ID> = Set()
  
  private func ssoLogin(profileState: ProfileState) async throws {
    let ir = InMemoryAWSSSOIdentityResolver(profile: profileState.profile)
    let authUri = try await ir.actor.setupAuth()
    
    await MainActor.run {
      authUriRecord = AuthUriRecord(authUri: authUri)
      presentAuthUri = true
    }
    
    try await ir.actor.getToken()
    // try await actor.getAccounts()
    // try await actor.getAccountRoles()
    let _ = try await ir.actor.getRoleCredentials()
    let stsConfiguration = try await STSClient.STSClientConfiguration(
      awsCredentialIdentityResolver: ir,
      region: profileState.profile.region
    )
    let stsClient = STSClient(config: stsConfiguration)
    print("making callerid call")
    let response = try await stsClient.getCallerIdentity(input: GetCallerIdentityInput())
    print("done callerid call")
    
    // FIXME: the following updates might not be instaneous
    profileState.identityResolver = ir
    profileState.userArn = response.arn
    profileState.tokenExpiration = await ir.actor.tokenExpiration
    profileState.credentialExpiration = await ir.actor.credentialExpiration
  }
  
  var body: some View {
    VStack {
      let profileStates = profileStore.profileStates
      Table(profileStates, selection: $selectedProfiles) {
        TableColumn("Profile Name") {
          Text($0.profile.profileName)
        }
        TableColumn("User ARN") {
          Text($0.userArn != nil ? String(describing: $0.userArn!) : "N/A")
            .alert(isPresented: self.$presentMessage) {
              Alert(title: Text(messageRecord!.title),
                    message: Text(messageRecord!.message)
              )
            }
        }
        TableColumn("Token Expiration") {
          Text($0.tokenExpiration != nil ? String(describing: $0.tokenExpiration!) : "N/A")
        }
        TableColumn("Credential Expiration") {
          Text($0.credentialExpiration != nil ? String(describing: $0.credentialExpiration!) : "N/A")
        }
      }
      .contextMenu(forSelectionType: ProfileState.ID.self) { items in
        Group {
          Button("Login") {
            Task {
              try await ssoLogin(profileState: profileStates.first(where: { $0.id == items.first! })!)
            }
          }
          Button("Get caller identity (once logged in)") {
            Task {
              guard let profileState = profileStates.first(where: { $0.id == items.first! }) else {
                return
              }
              guard let identityResolver = profileState.identityResolver else {
                return
              }
              let stsConfiguration = try await STSClient.STSClientConfiguration(
                awsCredentialIdentityResolver: identityResolver,
                region: profileState.profile.region
              )
              let stsClient = STSClient(config: stsConfiguration)
              print("making callerid call")
              let response = try await stsClient.getCallerIdentity(input: GetCallerIdentityInput())
              print("done callerid call")
              print("response: \(response.arn!)")
              await MainActor.run {
                messageRecord = MessageRecord(title: "Caller Identity", message: response.arn!)
                presentMessage = true
                print("updating messageRecord \(messageRecord!)")
              }
            }
          }
        }
      }
      primaryAction: { items in
        Task {
          try await ssoLogin(profileState: profileStates.first(where: { $0.id == items.first! })!)
        }
      }
    }
    .alert(isPresented: self.$presentAuthUri) {
      Alert(title: Text("Login via AWS SSO"),
            message: Text("You now need to login via AWS SSO. Click the link below to open in your browser."),
            primaryButton: .default(Text("Open")) {
        openURL(authUriRecord!.authUri)
      },
            secondaryButton: .cancel()
      )
    }
    .padding()
  }
}

#Preview {
  AWSSSOProfilesView()
}
