import SwiftUI
import AWSSSOToolkit

struct ContentView: View {
  @State var profile: ProfileViewModel

  init() {
    let staticProfile = AWSProfile(profileName: "myprofile", profileType: .SSO(session: AWSSSOSession(sessionName: "mysession", startUrl: "https://hsiao.awsapps.com/start", region: "us-east-1"), accountId: "714381189854", roleName: "AdministratorAccess", region: "us-east-1"))
    let staticProfileState = ProfileState(profile: staticProfile)
    profile = ProfileViewModel(profileState: staticProfileState)
  }

  var body: some View {
    VStack {
      VStack {
        Text("Static AWS Profile")
          .padding([.top, .bottom], 10)
        ToolkitProfileView(profile: $profile)
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
