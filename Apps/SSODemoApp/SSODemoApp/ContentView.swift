import SwiftUI
import AWSSSOToolkit
@preconcurrency import AWSSTS

private let startUrl = "https://foo.awsapps.com/start"
private let accountId = "123456789012"
private let roleName = "AdministratorAccess"

struct StaticProfileDemoView: View {
  @State var profileViewModel: ProfileViewModel
  @State var userArn: String = "N/A"

  init() {
    let ssoSession = AWSSSOSession(sessionName: "mysession", startUrl: startUrl, region: "us-east-1")
    let staticProfile = AWSProfile(profileName: "myprofile",
                                   profileType: .SSO(session: ssoSession,
                                                     accountId: accountId,
                                                     roleName: roleName,
                                                     region: "us-east-1"))
    let staticProfileState = ProfileState(profile: staticProfile)
    profileViewModel = ProfileViewModel(profileState: staticProfileState)
  }

  var body: some View {
    VStack {
      Text("Static AWS Profile Demo")
        .padding([.top, .bottom], 10)
      ToolkitProfileView(profile: $profileViewModel)
        .padding([.bottom], 10)
      Text("Profile user ARN: \(userArn)")
      Button("Get caller identity") {
        Task {
          let profileState = profileViewModel.profileState
          let identityProvider = profileState.identityResolver
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
            userArn = response.arn!
          }
        }
      }
    }
  }
}

struct ProfileManagementDemoView: View {
  var body: some View {
    VStack {
      Text("Managed AWS Profiles Demo")
      AWSSSOProfilesView()
    }
  }
}

struct ContentView: View {
  var body: some View {
    VStack {
      StaticProfileDemoView()
      Divider()
        .padding([.top, .bottom], 20)
      ProfileManagementDemoView()
    }
    .padding()
  }
}

#Preview {
  ContentView()
}
