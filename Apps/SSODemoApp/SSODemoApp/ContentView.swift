import SwiftUI
import AWSSSOToolkit

struct ContentView: View {

  var body: some View {
    VStack {
      Text("AWS Profiles")
      AWSSSOProfilesView()
    }
    .padding()
  }
}

#Preview {
  ContentView()
}
