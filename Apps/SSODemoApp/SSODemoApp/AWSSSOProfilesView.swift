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

  @State var profileViewStates: [UUID: (userArn: String, tokenExpiration: String, credentialExpiration: String)] = [:]

  private func ssoLogin(profileState: ProfileState) async throws {
    let ir = profileState.identityResolver
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
    profileState.userArn = response.arn
    profileViewStates[profileState.id] = (response.arn!,
                                          getDateString(await profileState.tokenExpiration()),
                                          getDateString(await profileState.credentialExpiration()))
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

  private func initProfileViewStates(_ profileStates: [ProfileState]) {
    for profileState in profileStates {
      profileViewStates[profileState.id] = ("N/A", "N/A", "N/A")
    }
  }

  @ViewBuilder
  private func menu(items: Set<ProfileState.ID>) -> some View{
    Group {
      Button("Login") {
        Task {
          let profileState = profileStore.profileStates.first(where: { $0.id == items.first! })!
          try await ssoLogin(profileState: profileState)
        }
      }
      Button("Logout") {
        Task {
          let profileState = profileStore.profileStates.first(where: { $0.id == items.first! })!
          try await profileState.identityResolver.actor.logout()
        }
      }
      Button("Forget role credentials") {
        Task {
          let profileState = profileStore.profileStates.first(where: { $0.id == items.first! })!
          await profileState.identityResolver.actor.forgetRoleCredentials()
        }
      }
      Button("Get caller identity (once logged in)") {
        Task {
          guard let profileState = profileStore.profileStates.first(where: { $0.id == items.first! }) else {
            return
          }
          let ir = profileState.identityResolver
          let stsConfiguration = try await STSClient.STSClientConfiguration(
            awsCredentialIdentityResolver: ir,
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

  var body: some View {
    VStack {
      let profileStates = profileStore.profileStates
      Table(profileStates, selection: $selectedProfiles) {
        TableColumn("Profile Name") {
          Text($0.profile.profileName)
        }
        TableColumn("User ARN") {
          let viewStates = profileViewStates[$0.id]
          Text(viewStates != nil ? viewStates!.userArn : "N/A")
            .alert(isPresented: self.$presentMessage) {
              Alert(title: Text(messageRecord!.title),
                    message: Text(messageRecord!.message)
              )
            }
        }
        TableColumn("Token Expiration") { (profileState: ProfileState) in
          let viewStates = self.profileViewStates[profileState.id]
          Text(viewStates != nil ? viewStates!.tokenExpiration : "N/A")
            .task {
              if viewStates != nil {
                let tokenExpiration = await profileState.tokenExpiration()
                profileViewStates[profileState.id] = (viewStates!.userArn, getDateString(tokenExpiration), viewStates!.credentialExpiration)
              }
            }
        }
        TableColumn("Credential Expiration") { (profileState: ProfileState) in
          let viewStates = self.profileViewStates[profileState.id]
          Text(viewStates != nil ? viewStates!.tokenExpiration : "N/A")
            .task {
              if viewStates != nil {
                let credentialExpiration = await profileState.credentialExpiration()
                profileViewStates[profileState.id] = (viewStates!.userArn, viewStates!.tokenExpiration, getDateString(credentialExpiration))
              }
            }
        }
      }
      .contextMenu(forSelectionType: ProfileState.ID.self) { items in
        menu(items: items)
      }
      primaryAction: { items in
        Task {
          try await ssoLogin(profileState: profileStore.profileStates.first(where: { $0.id == items.first! })!)
        }
      }
    }
    .task {
      initProfileViewStates(self.profileStore.profileStates)
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
