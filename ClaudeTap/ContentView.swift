import SwiftUI

struct ContentView: View {
    @Bindable var auth: AuthStore

    var body: some View {
        if auth.isSignedIn {
            HomeView(auth: auth)
        } else {
            SignInView(auth: auth)
        }
    }
}
