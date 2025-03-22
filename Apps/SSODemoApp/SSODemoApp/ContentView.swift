import SwiftUI
import AWSSSOToolkit
@preconcurrency import AWSSTS

struct ContentView: View {
  @State var profileViewModel: ProfileViewModel

  init() {
    let staticProfile = AWSProfile(profileName: "myprofile", profileType: .SSO(session: AWSSSOSession(sessionName: "mysession", startUrl: "https://hsiao.awsapps.com/start", region: "us-east-1"), accountId: "714381189854", roleName: "AdministratorAccess", region: "us-east-1"))
    let staticProfileState = ProfileState(profile: staticProfile)
    profileViewModel = ProfileViewModel(profileState: staticProfileState)
  }

  var body: some View {
    VStack {
      VStack {
        Text("Static AWS Profile")
          .padding([.top, .bottom], 10)
        ToolkitProfileView(profile: $profileViewModel)
          .padding([.bottom], 10)
        Text("Profile user ARN: \(profileViewModel.userArn)")
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
              print("done callerid call, response: \(response)")
            }
          }
        }
      }
      .padding([.bottom], 20)
      VStack {
        Text("Managed AWS Profiles")
        AWSSSOProfilesView()
      }
      .padding()
    }
  }
}

#Preview {
  ContentView()
}
