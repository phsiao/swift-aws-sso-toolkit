import SwiftUI

// format the date as a string for display in current time zone
private func getDateString(_ date: Date) -> String {
  let dateFormatter = DateFormatter()
  dateFormatter.dateStyle = .short
  dateFormatter.timeStyle = .short
  dateFormatter.timeZone = TimeZone.current
  return dateFormatter.string(from: date)
}

private let expirationNotAvaliable = "Not valid yet"

struct CredentialExpirationView: View {
  @State var profileViewModel: ProfileViewModel

  var body: some View {
    Text(profileViewModel.credentialExpirationDate == nil ?
         expirationNotAvaliable : getDateString(profileViewModel.credentialExpirationDate!))
  }
}

struct TokenExpirationView: View {
  @State var profileViewModel: ProfileViewModel

  var body: some View {
    Text(profileViewModel.credentialExpirationDate == nil ?
         expirationNotAvaliable: getDateString(profileViewModel.credentialExpirationDate!))
  }
}
