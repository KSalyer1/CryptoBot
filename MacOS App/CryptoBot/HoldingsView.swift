import SwiftUI

struct HoldingsView: View {
    @Environment(ApplicationState.self) private var app

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.1, blue: 0.15),
                    Color(red: 0.05, green: 0.05, blue: 0.1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    portfolioHeader
                    accountSection
                    holdingsSection
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
        }
        .navigationTitle("Portfolio")
#if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.large)
#endif
        .task { await load() }
    }
    
    private var portfolioHeader: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Portfolio Value")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                    
                    Text(formatUSD(app.portfolioValue))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    let delta = app.portfolioDelta
                    let pct = app.portfolioDeltaPct
                    let sign = delta >= 0 ? "+" : ""
                    
                    HStack(spacing: 8) {
                        Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(delta >= 0 ? .green : .red)
                        
                        Text("\(sign)\(formatUSD(delta)) (\(String(format: "%.2f%%", pct * 100)))")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(delta >= 0 ? .green : .red)
                    }
                }
                
                Spacer()
                
                // Portfolio status indicator
                HStack(spacing: 6) {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                    Text("Live")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(.green.opacity(0.1))
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.1, green: 0.1, blue: 0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                )
        )
    }
    
    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "creditcard.fill")
                    .foregroundColor(.blue)
                    .font(.system(size: 16))
                
                Text("Account")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
            }
            
            if let acct = app.account {
                VStack(spacing: 12) {
                    accountInfoRow(title: "Buying Power", value: "\(acct.buying_power) \(acct.buying_power_currency)", icon: "dollarsign.circle.fill", color: .green)
                    accountInfoRow(title: "Status", value: acct.status.capitalized, icon: "checkmark.circle.fill", color: .blue)
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "clock")
                        .font(.system(size: 32))
                        .foregroundColor(.white.opacity(0.4))
                    
                    Text("Loading account information...")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.1, green: 0.1, blue: 0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                )
        )
    }
    
    private var holdingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "wallet.pass.fill")
                    .foregroundColor(.purple)
                    .font(.system(size: 16))
                
                Text("Holdings")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Text("\(app.holdings.count)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(.white.opacity(0.1))
                    )
            }
            
            if app.holdings.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "wallet.pass")
                        .font(.system(size: 32))
                        .foregroundColor(.white.opacity(0.4))
                    
                    VStack(spacing: 8) {
                        Text("No Holdings")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                        
                        Text("Start trading to see your holdings here")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(app.holdings) { h in
                        holdingRow(h)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.1, green: 0.1, blue: 0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                )
        )
    }
    
    private func accountInfoRow(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.system(size: 16))
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                
                Text(value)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.16))
        )
    }

    private func holdingRow(_ h: HoldingItem) -> some View {
        let sym = "\(h.asset_code)-USD"
        let qty = Double(h.quantity) ?? 0
        let price = app.quotes[sym]?.price ?? 0
        let value = qty * price
        
        return HStack(spacing: 16) {
            // Asset icon
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.blue.opacity(0.8), .purple.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 40, height: 40)
                .overlay(
                    Text(String(h.asset_code.prefix(2)))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(h.asset_code)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                
                Text("Qty: \(h.quantity)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(formatUSD(value))
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                
                if price > 0 {
                    Text("@ \(formatPrice(price))")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                } else {
                    Text("--")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.1, green: 0.1, blue: 0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                )
        )
    }
    
    // Smart price formatting based on value
    private func formatPrice(_ price: Double) -> String {
        if price >= 100 {
            return String(format: "%.2f", price)
        } else if price >= 10 {
            return String(format: "%.3f", price)
        } else if price >= 1 {
            return String(format: "%.4f", price)
        } else if price >= 0.1 {
            return String(format: "%.5f", price)
        } else if price >= 0.01 {
            return String(format: "%.6f", price)
        } else {
            return String(format: "%.8f", price)
        }
    }

    private func formatUSD(_ x: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: x)) ?? "$0.00"
    }

    private func load() async {
        do {
            // Load account and holdings
            let acct = try await app.broker.getAccount()
            await MainActor.run { app.account = AccountSummary(account_number: acct.account_number, status: acct.status, buying_power: acct.buying_power, buying_power_currency: acct.buying_power_currency) }
            let hold = try await app.broker.getHoldings()
            let items = hold.results.map { HoldingItem(asset_code: $0.asset_code, quantity: $0.total_quantity) }
            await MainActor.run { app.holdings = items }
            if !app.quotePoller.isRunning {
                app.quotePoller.start(state: app)
            }
        } catch {
            // Surface minimal error inside Account section for now
        }
        // Update portfolio totals after quotes begin to arrive
        Task.detached { [weak app] in
            while true {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if let app = app {
                    await MainActor.run { app.updatePortfolioDerivedValues() }
                }
            }
        }
    }
}

#Preview {
    NavigationStack { HoldingsView().environment(ApplicationState()) }
}
