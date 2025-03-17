import SmithyIdentity
import SwiftUI
import GRDB
import os

@Observable
class ProfileViewModel: Identifiable {
  public var id: String { profileState.id }
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

@Observable
class ProfileViewModelStore: Identifiable {
  public var store: [ProfileViewModel]
  init(profileViewModels: [ProfileViewModel]) {
    self.store = profileViewModels
  }
}

struct AddSSOSessionView: View {
  private let backingDb = BackingDatabase(identifier: Bundle.main.bundleIdentifier!)

  @Binding var showAddSessionView: Bool
  @State var ssoSessionName: String = ""
  @State var startUrl: String = ""
  @State var region: String = ""

  var body: some View {
    VStack {
      VStack {
        TextField("Session name", text: $ssoSessionName)
        TextField("Start URL", text: $startUrl)
        TextField("Region", text: $region)
      }
      HStack {
        Spacer()
        Button("Cancel") {
          showAddSessionView.toggle()
        }
        Spacer()
        Button("Add session") {
          Task {
            let session = AWSSSOSession(sessionName: ssoSessionName, startUrl: startUrl, region: region)
            let dbq = try backingDb.getDbQueue()
            try dbq.write { dbq in
              try session.insert(dbq)
            }
            showAddSessionView.toggle()
          }
        }
        Spacer()
      }
    }
    .padding()
  }
}

struct AddProfileView: View {
  private let backingDb = BackingDatabase(identifier: Bundle.main.bundleIdentifier!)
  private let ssoSessions: [AWSSSOSession]

  @Binding var showAddProfileView: Bool
  @Binding var reloadNeeded: Bool

  @State var profileName: String = ""
  @State var accountId: String = ""
  @State var roleName: String = ""
  @State var region: String = ""
  @State var ssoSession: AWSSSOSession?

  init(showAddProfileView: Binding<Bool>, reloadNeeded: Binding<Bool>) {
    self._reloadNeeded = reloadNeeded
    self._showAddProfileView = showAddProfileView
    do {
      let dbq = try backingDb.getDbQueue()
      ssoSessions = try dbq.read { dbq in
        try AWSSSOSession.order(Column("sessionName")).fetchAll(dbq)
      }
    } catch {
      ssoSessions = []
      fatalError("Error: \(error)")
    }
  }

  var body: some View {
    VStack {
      VStack {
        TextField("Profile name", text: $profileName)
        TextField("Account ID", text: $accountId)
        TextField("Role name", text: $roleName)
        TextField("Region", text: $region)
        Menu("Select SSO session") {
          ForEach(ssoSessions) { session in
            Button(session.sessionName) {
              ssoSession = session
            }
          }
        }
      }
      HStack {
        Spacer()
        Button("Cancel") {
          showAddProfileView.toggle()
        }
        Spacer()
        Button("Add profile") {
          Task {
            let profile = AWSProfile(profileName: profileName,
                                     profileType: .SSO(session: ssoSession!,
                                                       accountId: accountId,
                                                       roleName: roleName,
                                                       region: region))
            let ssoProfile = AWSSSOProfile(from: profile)
            let dbq = try backingDb.getDbQueue()
            try dbq.write { dbq in
              try ssoProfile.insert(dbq)
            }
            showAddProfileView.toggle()
            reloadNeeded.toggle()
          }
        }
        Spacer()
      }
    }
    .padding()
  }
}

/// A SwiftUI view that displays a list of AWS profiles available to the application, and a set of
/// actions that can be performed on them.
///
/// The actions include adding a new sso session and profile, log in to a profile and manage the
/// device token and role credentials.
public struct AWSSSOProfilesView: View {
  private var logger: Logger = Logger(
    subsystem: defaultSubsystemName,
    category: String(describing: AWSSSOProfilesView.self))

  @State private var showAddSessionView: Bool = false
  @State private var showAddProfileView: Bool = false
  @State private var reloadNeeded: Bool = false

  public init() {
  }

  public var body: some View {
    VStack {
      ProfilesTableView(reloadNeeded: $reloadNeeded)
      HStack {
        Button("Add a new SSO session") {
          showAddSessionView.toggle()
        }
        Button("Add a new profile") {
          showAddProfileView.toggle()
        }
      }
    }
    .sheet(isPresented: $showAddSessionView) {
      VStack {
        AddSSOSessionView(showAddSessionView: $showAddSessionView)
      }
    }
    .sheet(isPresented: $showAddProfileView, content: {
      VStack {
        AddProfileView(showAddProfileView: $showAddProfileView, reloadNeeded: $reloadNeeded)
      }
    })
    .padding()
  }
}

#Preview {
  AWSSSOProfilesView()
}
