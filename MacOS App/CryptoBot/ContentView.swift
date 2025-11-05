import SwiftUI
import Observation

public struct ContentView: View {
    @State private var appState = ApplicationState()

    @State private var showConfirm = false
    @State private var selectedSymbol: String = "BTC-USD"

    public var body: some View {
        TabView {
            NavigationStack { HoldingsView() }
                .tabItem { 
                    Label("Portfolio", systemImage: "house.fill") 
                }
                .environment(appState)

            MarketsView()
                .tabItem { 
                    Label("Markets", systemImage: "chart.line.uptrend.xyaxis") 
                }
                .environment(appState)

            NavigationStack { AITradingView() }
                .tabItem { 
                    Label("AI Trading", systemImage: "brain.head.profile") 
                }
                .environment(appState)

            NavigationStack { SettingsView() }
                .tabItem { 
                    Label("Settings", systemImage: "gearshape.fill") 
                }
                .environment(appState)
        }
        .accentColor(.blue)
#if os(iOS) || os(visionOS)
        .onAppear {
            // Configure tab bar appearance
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor(red: 0.1, green: 0.1, blue: 0.15, alpha: 1.0)
            appearance.shadowColor = UIColor.black.withAlphaComponent(0.3)
            
            // Configure tab bar item appearance
            appearance.stackedLayoutAppearance.normal.iconColor = UIColor.white.withAlphaComponent(0.6)
            appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
                .foregroundColor: UIColor.white.withAlphaComponent(0.6),
                .font: UIFont.systemFont(ofSize: 12, weight: .medium)
            ]
            
            appearance.stackedLayoutAppearance.selected.iconColor = UIColor.systemBlue
            appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
                .foregroundColor: UIColor.systemBlue,
                .font: UIFont.systemFont(ofSize: 12, weight: .semibold)
            ]
            
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
#endif
    }
}

#Preview {
    ContentView()
        .environment(ApplicationState())
}
