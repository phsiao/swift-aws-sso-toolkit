import SmithyIdentity
import SwiftUI
import GRDB
import os

@Observable
class ProfileViewModel: Identifiable {
  public var id: String { profileState.id }
  let profileState: ProfileState
  var userArn: String
  var tokenExpiration: AnyView
  var credentialExpiration: AnyView

  init(profileState: ProfileState) {
    self.profileState = profileState
    self.userArn = "N/A"
    self.tokenExpiration = AnyView(EmptyView())
    self.credentialExpiration = AnyView(EmptyView())
  }

  // format the date as a string for display in current time zone
  func getDateString(_ date: Date) -> String {
    let dateFormatter = DateFormatter()
    dateFormatter.dateStyle = .short
    dateFormatter.timeStyle = .short
    dateFormatter.timeZone = TimeZone.current
    return dateFormatter.string(from: date)
  }

  @MainActor
  func updateExpirationTimes() async {
    let tokenExpiration = await profileState.tokenExpiration()
    let credentialExpiration = await profileState.credentialExpiration()

    if tokenExpiration == nil {
      self.tokenExpiration = AnyView(EmptyView())
    } else {
      let tokenExpirationStr = getDateString(tokenExpiration!)
      self.tokenExpiration = AnyView(
        HStack {
          Image(systemName: "clock")
          Text(tokenExpirationStr)
        }
      )
    }

    if credentialExpiration == nil {
      self.credentialExpiration = AnyView(EmptyView())
    } else {
      let credentialExpirationStr = getDateString(credentialExpiration!)
      self.credentialExpiration = AnyView(
        HStack {
          Image(systemName: "clock")
          Text(credentialExpirationStr)
        }
      )
    }
  }
}

@Observable
class ProfileViewModelStore: Identifiable {
  public var store: [ProfileViewModel]
  init(profileViewModels: [ProfileViewModel]) {
    self.store = profileViewModels
  }
}

@Observable
class SSOSessionForm {
  var ssoSessionName: String = "" {
    didSet {
      isFormComplete = !ssoSessionName.isEmpty &&
      awsRegionList.filter({$0.region == self.region}).count == 1 &&
      URL(string: startUrl) != nil
    }
  }
  var startUrl: String = "" {
    didSet {
      isFormComplete = !ssoSessionName.isEmpty &&
      awsRegionList.filter({$0.region == self.region}).count == 1 &&
      URL(string: startUrl) != nil
    }
  }
  var region: String = "Select the region where IAM Identity Center is hosted" {
    didSet {
      isFormComplete = !ssoSessionName.isEmpty &&
      awsRegionList.filter({$0.region == self.region}).count == 1 &&
      URL(string: startUrl) != nil
    }
  }
  var isFormComplete: Bool = false
}

struct AddSSOSessionView: View {
  private let backingDb = BackingDatabase(identifier: Bundle.main.bundleIdentifier!)

  @State private var form = SSOSessionForm()
  @Binding var showAddSessionView: Bool

  var body: some View {
    VStack {
      Text("Create a new SSO session").padding([.top, .horizontal])
      VStack {
        TextField("Session name", text: $form.ssoSessionName)
          .padding([.bottom, .horizontal], 5)
        TextField("Start URL", text: $form.startUrl)
          .padding([.bottom, .horizontal], 5)
        Menu(form.region) {
          ForEach(awsRegionList) { reg in
            Button(reg.region) {
              self.form.region = reg.region
            }
          }
        }
        .padding([.horizontal], 5)
      }
      .padding()
      HStack {
        Spacer()
        Button("Cancel") {
          showAddSessionView.toggle()
        }
        Spacer()
        Button("Add") {
          Task {
            let session = AWSSSOSession(sessionName: form.ssoSessionName,
                                        startUrl: form.startUrl,
                                        region: form.region)
            let dbq = try backingDb.getDbQueue()
            try dbq.write { dbq in
              try session.insert(dbq)
            }
            showAddSessionView.toggle()
          }
        }
        .disabled(!form.isFormComplete)
        Spacer()
      }
      .padding(.bottom, 20)
    }
  }
}

@Observable
class ProfileForm {
  var profileName: String = "" {
    didSet {
      isFormComplete = !profileName.isEmpty &&
      !accountId.isEmpty &&
      !roleName.isEmpty &&
      awsRegionList.filter({$0.region == self.region}).count == 1 &&
      ssoSession != nil
    }
  }
  var accountId: String = "" {
    didSet {
      isFormComplete = !profileName.isEmpty &&
      !accountId.isEmpty &&
      !roleName.isEmpty &&
      awsRegionList.filter({$0.region == self.region}).count == 1 &&
      ssoSession != nil
    }
  }
  var roleName: String = "" {
    didSet {
      isFormComplete = !profileName.isEmpty &&
      !accountId.isEmpty &&
      !roleName.isEmpty &&
      awsRegionList.filter({$0.region == self.region}).count == 1 &&
      ssoSession != nil
    }
  }
  var region: String = "Select a region" {
    didSet {
      isFormComplete = !profileName.isEmpty &&
      !accountId.isEmpty &&
      !roleName.isEmpty &&
      awsRegionList.filter({$0.region == self.region}).count == 1 &&
      ssoSession != nil
    }
  }
  var ssoSession: AWSSSOSession? {
    didSet {
      isFormComplete = !profileName.isEmpty &&
      !accountId.isEmpty &&
      !roleName.isEmpty &&
      awsRegionList.filter({$0.region == self.region}).count == 1 &&
      ssoSession != nil
    }
  }
  var isFormComplete: Bool = false
}

struct AddProfileView: View {
  private let backingDb = BackingDatabase(identifier: Bundle.main.bundleIdentifier!)
  private let ssoSessions: [AWSSSOSession]

  @Binding var showAddProfileView: Bool
  @Binding var reloadNeeded: Bool

  @State private var form = ProfileForm()

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
      Text("Create a new profle").padding([.top, .horizontal])
      VStack {
        TextField("Profile name", text: $form.profileName)
          .padding([.bottom, .horizontal], 5)
        TextField("Account ID", text: $form.accountId)
          .padding([.bottom, .horizontal], 5)
        TextField("Role name", text: $form.roleName)
          .padding([.bottom, .horizontal], 5)
        Menu(form.region) {
          ForEach(awsRegionList) { reg in
            Button(reg.region) {
              form.region = reg.region
            }
          }
        }.padding([.bottom, .horizontal], 5)
        Menu("Select SSO session") {
          ForEach(ssoSessions) { session in
            Button(session.sessionName) {
              form.ssoSession = session
            }
          }
        }.padding([.horizontal], 5)
      }
      .padding()
      HStack {
        Spacer()
        Button("Cancel") {
          showAddProfileView.toggle()
        }
        Spacer()
        Button("Add") {
          Task {
            let profile = AWSProfile(profileName: form.profileName,
                                     profileType: .SSO(session: form.ssoSession!,
                                                       accountId: form.accountId,
                                                       roleName: form.roleName,
                                                       region: form.region))
            let ssoProfile = AWSSSOProfile(from: profile)
            let dbq = try backingDb.getDbQueue()
            try dbq.write { dbq in
              try ssoProfile.insert(dbq)
            }
            showAddProfileView.toggle()
            reloadNeeded.toggle()
          }
        }
        .disabled(!form.isFormComplete)
        Spacer()
      }
    }
    .padding([.bottom], 20)
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
        Spacer()
        Button("Add a new SSO session") {
          showAddSessionView.toggle()
        }
        Spacer()
        Button("Add a new profile") {
          showAddProfileView.toggle()
        }
        Spacer()
      }
      .padding(.top, 20)
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
