import SwiftUI

struct AuthUriRecord: Identifiable {
  let id: UUID = UUID()
  let authUri: URL
}

struct MessageRecord: Identifiable {
  let id: UUID = UUID()
  let title: String
  let message: String
}

/// Represents an AWS profile and its associated state for viewing in the UI.
@Observable
public class ProfileViewModel: Identifiable {
  public var id: String { profileState.id }
  public let profileState: ProfileState
  public var userArn: String
  public var tokenExpirationDate: Date?
  public var credentialExpirationDate: Date?

  public init(profileState: ProfileState) {
    self.profileState = profileState
    self.userArn = "N/A"
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
    tokenExpirationDate = await profileState.tokenExpiration()
    credentialExpirationDate = await profileState.credentialExpiration()
  }
}

@Observable
public class ProfileViewModelStore: Identifiable {
  public var store: [ProfileViewModel]
  init(profileViewModels: [ProfileViewModel]) {
    self.store = profileViewModels
  }
}
