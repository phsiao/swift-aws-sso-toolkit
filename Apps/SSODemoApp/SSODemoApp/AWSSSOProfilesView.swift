import SwiftUI
@preconcurrency import AWSSTS
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

    authUriRecord = AuthUriRecord(authUri: authUri)
    presentAuthUri = true

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

  // format the date as a string for display in current time zone
  private func getDateString(_ date: Date?) -> String {
    guard let date = date else {
      return "N/A"
    }
    let dateFormatter = ISO8601DateFormatter()
    dateFormatter.timeZone = TimeZone.current
    return dateFormatter.string(from: date)
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
          Text(getDateString($0.tokenExpiration))
        }
        TableColumn("Credential Expiration") {
          Text(getDateString($0.credentialExpiration))
        }
      }
      .contextMenu(forSelectionType: ProfileState.ID.self) { items in
        Group {
          Button("Login") {
            Task {
              try await ssoLogin(profileState: profileStates.first(where: { $0.id == items.first! })!)
            }
          }
          Button("Logout") {
            Task {
              let profileState = profileStates.first(where: { $0.id == items.first! })!
              guard let ir = profileState.identityResolver else {
                return
              }
              try await ir.actor.logout()
              profileState.tokenExpiration = await ir.actor.tokenExpiration
            }
          }
          Button("Forget role credentials") {
            Task {
              let profileState = profileStates.first(where: { $0.id == items.first! })!
              guard let ir = profileState.identityResolver else {
                return
              }
              await ir.actor.forgetRoleCredentials()
              profileState.credentialExpiration = await ir.actor.credentialExpiration
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
              do {
                let response = try await stsClient.getCallerIdentity(input: GetCallerIdentityInput())
                print("done callerid call")
                print("response: \(response.arn!)")

                messageRecord = MessageRecord(title: "Caller Identity", message: response.arn!)
                presentMessage = true
              } catch {
                print("error: \(error)")
                messageRecord = MessageRecord(title: "Error", message: String(describing: error))
                presentMessage = true
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
