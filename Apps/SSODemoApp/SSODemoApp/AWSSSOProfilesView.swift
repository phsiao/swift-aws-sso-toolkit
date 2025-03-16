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

@Observable
class ProfileViewModel: Identifiable {
  public var id: UUID { profileState.id }
  let profileState: ProfileState
  var userArn: String
  var tokenExpiration: String
  var credentialExpiration: String

  init(profileState: ProfileState) {
    self.profileState = profileState
    self.userArn = "N/A"
    self.tokenExpiration = "N/A"
    self.credentialExpiration = "N/A"
  }
}

struct AWSSSOProfilesView: View {
  @SwiftUI.Environment(\.openURL) private var openURL
  @SwiftUI.Environment(ProfileStore.self) private var profileStore

  @State var presentAuthUri: Bool = false
  @State var authUriRecord: AuthUriRecord? = nil
  @State var presentMessage: Bool = false
  @State var messageRecord: MessageRecord? = nil
  @State var selectedProfiles: Set<ProfileViewModel.ID> = Set()

  @State var profileViewModels: [UUID:ProfileViewModel] = [:]

  private func ssoLogin(profileViewModel: ProfileViewModel) async throws {
    let profileState = profileViewModel.profileState
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
    profileViewModel.userArn = response.arn!
    profileViewModel.tokenExpiration = getDateString(await profileState.tokenExpiration())
    profileViewModel.credentialExpiration = getDateString(await profileState.credentialExpiration())
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

  @ViewBuilder
  private func menu(items: Set<ProfileViewModel.ID>) -> some View{
    Group {
      Button("Login") {
        Task {
          let profileViewModel = self.profileViewModels[items.first!]!
          try await ssoLogin(profileViewModel: profileViewModel)
        }
      }
      Button("Logout") {
        Task {
          let profileViewModel = profileViewModels[items.first!]!
          let profileState = profileViewModel.profileState
          try await profileState.identityResolver.actor.logout()
          profileViewModel.tokenExpiration = getDateString(await profileState.tokenExpiration())
          profileViewModel.credentialExpiration = getDateString(await profileState.credentialExpiration())
        }
      }
      Button("Forget role credentials") {
        Task {
          let profileViewModel = profileViewModels[items.first!]!
          let profileState = profileViewModel.profileState
          await profileState.identityResolver.actor.forgetRoleCredentials()
          profileViewModel.tokenExpiration = getDateString(await profileState.tokenExpiration())
          profileViewModel.credentialExpiration = getDateString(await profileState.credentialExpiration())
        }
      }
      Button("Get caller identity (once logged in)") {
        Task {
          let profileViewModel = profileViewModels[items.first!]!
          let profileState = profileViewModel.profileState
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
          profileViewModel.tokenExpiration = getDateString(await profileState.tokenExpiration())
          profileViewModel.credentialExpiration = getDateString(await profileState.credentialExpiration())
        }
      }
    }
  }

  var body: some View {
    VStack {
      Table(Array(profileViewModels.values), selection: $selectedProfiles) {
        TableColumn("Profile Name") {
          Text($0.profileState.profile.profileName)
        }
        TableColumn("User ARN") {
          Text($0.userArn)
            .alert(isPresented: self.$presentMessage) {
              Alert(title: Text(messageRecord!.title),
                    message: Text(messageRecord!.message)
              )
            }
        }
        TableColumn("Token Expiration") {
          Text($0.tokenExpiration)
        }
        TableColumn("Credential Expiration") {
          Text($0.credentialExpiration)
        }
      }
      .task {
        for profileState in self.profileStore.profileStates {
          if profileViewModels[profileState.id] == nil {
            profileViewModels[profileState.id] = (ProfileViewModel(profileState: profileState))
          }
        }
      }
      .contextMenu(forSelectionType: ProfileViewModel.ID.self) { items in
        menu(items: items)
      }
      primaryAction: { items in
        Task {
          try await ssoLogin(profileViewModel: self.profileViewModels[items.first!]!)
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
