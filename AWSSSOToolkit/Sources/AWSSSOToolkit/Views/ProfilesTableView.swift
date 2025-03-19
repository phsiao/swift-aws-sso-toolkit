@preconcurrency import AWSSTS
import SmithyIdentity
import SwiftUI
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
class ProfilesTableViewModel {
  var presentAuthUri: Bool = false
  var authUriRecord: AuthUriRecord?
  var presentMessage: Bool = false
  var messageRecord: MessageRecord?
  var selectedProfiles: Set<ProfileViewModel.ID> = Set()
  var profileViewModels: [ProfileViewModel] = []

  func getProfileViewModel(id: ProfileViewModel.ID) -> ProfileViewModel? {
    return profileViewModels.filter { $0.id == id }.first
  }
}

private struct FullTableView: View {
  @State var viewModel: ProfilesTableViewModel
  var body: some View {
    Table(viewModel.profileViewModels, selection: $viewModel.selectedProfiles) {
      TableColumn("Profile Name") {
        Text($0.profileState.profile.profileName)
      }
      TableColumn("SSO Session Name") {
        switch $0.profileState.profile.profileType {
        case .SSO(let session, _, _, _):
          Text(session.sessionName)
        }
      }
      TableColumn("Account ID") {
        switch $0.profileState.profile.profileType {
        case .SSO(_, let accountId, _, _):
          Text(accountId)
        }
      }
      TableColumn("Region") {
        switch $0.profileState.profile.profileType {
        case .SSO(_, _, _, let region):
          Text(region)
        }
      }
      TableColumn("Role Name") {
        switch $0.profileState.profile.profileType {
        case .SSO(_, _, let roleName, _):
          Text(roleName)
        }
      }
      TableColumn("Token Expiration") {
        Text($0.tokenExpiration)
      }
      TableColumn("Credential Expiration") {
        Text($0.credentialExpiration)
      }
      TableColumn("User ARN") {
        Text($0.userArn)
          .alert(isPresented: $viewModel.presentMessage) {
            Alert(
              title: Text(viewModel.messageRecord!.title),
              message: Text(viewModel.messageRecord!.message)
            )
          }
      }
    }
    .frame(minWidth: 1400)
  }
}

private struct MediumTableView: View {
  @State var viewModel: ProfilesTableViewModel
  var body: some View {
    Table(viewModel.profileViewModels, selection: $viewModel.selectedProfiles) {
      TableColumn("Profile Name") {
        Text($0.profileState.profile.profileName)
      }
      TableColumn("SSO Session Name") {
        switch $0.profileState.profile.profileType {
        case .SSO(let session, _, _, _):
          Text(session.sessionName)
        }
      }
      TableColumn("Token Expiration") {
        Text($0.tokenExpiration)
      }
      TableColumn("Credential Expiration") {
        Text($0.credentialExpiration)
      }
      TableColumn("User ARN") {
        Text($0.userArn)
          .alert(isPresented: $viewModel.presentMessage) {
            Alert(
              title: Text(viewModel.messageRecord!.title),
              message: Text(viewModel.messageRecord!.message)
            )
          }
      }
    }
    .frame(minWidth: 800)
  }
}

private struct NarrowTableView: View {
  @State var viewModel: ProfilesTableViewModel
  var body: some View {
    Table(viewModel.profileViewModels, selection: $viewModel.selectedProfiles) {
      TableColumn("Profile Name") {
        Text($0.profileState.profile.profileName)
          .alert(isPresented: $viewModel.presentMessage) {
            Alert(
              title: Text(viewModel.messageRecord!.title),
              message: Text(viewModel.messageRecord!.message)
            )
          }
      }
      TableColumn("SSO Session Name") {
        switch $0.profileState.profile.profileType {
        case .SSO(let session, _, _, _):
          Text(session.sessionName)
        }
      }
    }
  }
}

struct ProfilesTableView: View {
  @SwiftUI.Environment(\.openURL) private var openURL

  @State var viewModel = ProfilesTableViewModel()
  @Binding var reloadNeeded: Bool

  public init(reloadNeeded: Binding<Bool>) {
    self._reloadNeeded = reloadNeeded
  }

  private let backingDb = BackingDatabase(identifier: Bundle.main.bundleIdentifier!)
  private var logger: Logger = Logger(
    subsystem: defaultSubsystemName,
    category: String(describing: ProfilesTableView.self))

  func reload() async throws {
    var profiles: [AWSProfile] = []
    do {
      profiles = try backingDb.load()
    } catch {
      logger.error("Error: \(error)")
    }
    let profileStates = profiles.map {
      ProfileState(profile: $0)
    }

    var models: [ProfileViewModel] = []
    for state in profileStates {
      if let existingModel = self.viewModel.profileViewModels.filter({ $0.id == state.id }).first {
        models.append(existingModel)
      } else {
        models.append(ProfileViewModel(profileState: state))
      }
    }
    viewModel.profileViewModels = models
  }

  var body: some View {
    ViewThatFits {
      FullTableView(viewModel: viewModel)
      MediumTableView(viewModel: viewModel)
      NarrowTableView(viewModel: viewModel)
    }
    .contextMenu(forSelectionType: ProfileViewModel.ID.self) { items in
      self.profileOpsMenu(items: items)
      Divider()
      self.profileFuncMenu(items: items)
    } primaryAction: { items in
      Task {
        try await ssoLogin(
          profileViewModel: viewModel.profileViewModels.filter { $0.id == items.first! }.first!
        )
      }
    }
    .onChange(of: reloadNeeded, initial: false) {
      Task {
        try await reload()
      }
    }
    .task {
      Task {
        try await reload()
      }
    }
    .alert(isPresented: $viewModel.presentAuthUri) {
      Alert(
        title: Text("Login via AWS SSO"),
        message: Text(
          "You now need to login via AWS SSO. Click the link below to open in your browser."
        ),
        primaryButton: .default(Text("Open")) {
          openURL(viewModel.authUriRecord!.authUri)
        },
        secondaryButton: .cancel()
      )
    }
  }
}

// MARK: - utility functions for ProfilesTableView
extension ProfilesTableView {
  // format the date as a string for display in current time zone
  func getDateString(_ date: Date?) -> String {
    guard let date = date else {
      return "N/A"
    }
    let dateFormatter = ISO8601DateFormatter()
    dateFormatter.timeZone = TimeZone.current
    return dateFormatter.string(from: date)
  }

  func ssoLogin(profileViewModel: ProfileViewModel) async throws {
    let profileState = profileViewModel.profileState
    let identityProvider = profileState.identityResolver
    let authUri = try await identityProvider.actor.setupAuth()

    viewModel.authUriRecord = AuthUriRecord(authUri: authUri)
    viewModel.presentAuthUri = true

    try await identityProvider.actor.getToken()
    _ = try await identityProvider.actor.getRoleCredentials()

    switch profileState.profile.profileType {
    case .SSO(let session, _, _, _):
      let stsConfiguration = try await STSClient.STSClientConfiguration(
        awsCredentialIdentityResolver: identityProvider,
        region: session.region
      )
      let stsClient = STSClient(config: stsConfiguration)
      print("making callerid call")
      let response = try await stsClient.getCallerIdentity(
        input: GetCallerIdentityInput())
      print("done callerid call")

      // FIXME: the following updates might not be instaneous
      profileViewModel.userArn = response.arn!
      profileViewModel.tokenExpiration = getDateString(
        await profileState.tokenExpiration())
      profileViewModel.credentialExpiration = getDateString(
        await profileState.credentialExpiration())
    }
  }
}

// MARK: - view builder functions for ProfilesTableView
extension ProfilesTableView {
  @ViewBuilder
  private func profileOpsMenu(items: Set<ProfileViewModel.ID>) -> some View {
    Group {
      Button("Login") {
        Task {
          let profileViewModel = viewModel.getProfileViewModel(id: items.first!)!
          try await self.ssoLogin(profileViewModel: profileViewModel)
        }
      }
      Button("Logout") {
        Task {
          let profileViewModel = viewModel.getProfileViewModel(id: items.first!)!
          let profileState = profileViewModel.profileState
          try await profileState.identityResolver.actor.logout()
          profileViewModel.tokenExpiration = self.getDateString(await profileState.tokenExpiration())
          profileViewModel.credentialExpiration = self.getDateString(await profileState.credentialExpiration())
        }
      }
      Button("Forget role credentials") {
        Task {
          let profileViewModel = viewModel.getProfileViewModel(id: items.first!)!
          let profileState = profileViewModel.profileState
          await profileState.identityResolver.actor.forgetRoleCredentials()
          profileViewModel.tokenExpiration = self.getDateString(await profileState.tokenExpiration())
          profileViewModel.credentialExpiration = self.getDateString(await profileState.credentialExpiration())
        }
      }
    }
  }

  @ViewBuilder
  private func profileFuncMenu(items: Set<ProfileViewModel.ID>) -> some View {
    Group {
      Button("Get caller identity (once logged in)") {
        Task {
          let profileViewModel = viewModel.getProfileViewModel(id: items.first!)!
          let profileState = profileViewModel.profileState
          let identityProvider = profileState.identityResolver
          switch profileState.profile.profileType {
          case .SSO(let session, _, _, _):
            let stsConfiguration = try await STSClient.STSClientConfiguration(
              awsCredentialIdentityResolver: identityProvider,
              region: session.region
            )

            let stsClient = STSClient(config: stsConfiguration)
            print("making callerid call")
            do {
              let response = try await stsClient.getCallerIdentity(
                input: GetCallerIdentityInput())
              print("done callerid call")
              print("response: \(response.arn!)")
              viewModel.messageRecord = MessageRecord(
                title: "Caller Identity", message: response.arn!)
              viewModel.presentMessage = true
            } catch {
              print("error: \(error)")
              viewModel.messageRecord = MessageRecord(
                title: "Error", message: String(describing: error))
              viewModel.presentMessage = true
            }
            profileViewModel.tokenExpiration = getDateString(await profileState.tokenExpiration())
            profileViewModel.credentialExpiration = getDateString(await profileState.credentialExpiration())
          }
        }
      }
    }
  }
}
