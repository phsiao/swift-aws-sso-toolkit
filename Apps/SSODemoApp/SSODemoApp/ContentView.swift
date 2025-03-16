import SwiftUI
import AWSSSOToolkit

struct ContentView: View {
  var profileStore: ProfileStore
  init() {
    let profileStates: [ProfileState] = [
      ProfileState(profile: AWSProfile(
        profileName: "phsiao-main",
        profileType: .SSO(
          session: AWSSSOSession(
            sessionName: "hsiao",
            startUrl: "https://hsiao.awsapps.com/start",
            region: "us-east-1"
          ),
          accountId: "714381189854",
          roleName: "AdministratorAccess",
          region: "us-east-1"
        ),
        region: "us-east-1"
      ))]
    profileStore = ProfileStore(profileStates: profileStates)
  }
  var body: some View {
    VStack {
      Text("AWS Profiles")
      AWSSSOProfilesView()
    }
    .environment(profileStore)
    .padding()
  }
}

#Preview {
  ContentView()
}
