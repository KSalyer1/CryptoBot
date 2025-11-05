import SwiftUI
import Observation
import CryptoKit

struct SettingsView: View {
    @Environment(ApplicationState.self) private var app
    @AppStorage("openai_api_key") private var storedOpenAIKey: String = ""

    @State private var apiKeyInput: String = ""
    @State private var privateKeySeedInput: String = ""
    @State private var publicKeyInput: String = ""
    @State private var baseURLInput: String = ""
    @State private var brokerStatus: String?
    @State private var brokerError: String?
    
    @State private var openAIKeyInput: String = ""
    @State private var openAIStatus: String?

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
                    robinhoodSection
                    openAISection
                    ingestionSection
                    safetySection
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
        }
        .navigationTitle("Settings")
#if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.large)
#endif
        .onAppear(perform: syncFields)
    }

    private var robinhoodSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "building.2.fill")
                    .foregroundColor(.blue)
                    .font(.system(size: 16))
                
                Text("Robinhood Crypto API")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
            }
            
            VStack(spacing: 12) {
                modernTextField(title: "API Key", text: $apiKeyInput, isSecure: true)
                modernTextField(title: "Base64 Private Key Seed", text: $privateKeySeedInput, isSecure: true)
                modernTextField(title: "Base64 Public Key", text: $publicKeyInput, isSecure: true)
                modernTextField(title: "Base URL", text: $baseURLInput, placeholder: "https://trading.robinhood.com")
            }
            
            HStack(spacing: 12) {
                Button("Apply Credentials") { applyBrokerUpdates() }
                    .buttonStyle(ModernButtonStyle(style: .primary))
                
                Button("Generate New Keys") { generateNewKeyPair() }
                    .buttonStyle(ModernButtonStyle(style: .secondary))
            }
            
            if let brokerStatus {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(brokerStatus)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.green.opacity(0.1))
                )
            }
            
            if let brokerError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(brokerError)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.red)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.red.opacity(0.1))
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

    private var openAISection: some View {
        Section(header: Text("OpenAI API")) {
            SecureField("OpenAI API Key (sk-...)", text: $openAIKeyInput)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)
#if os(iOS) || os(visionOS)
                .autocapitalization(.none)
#endif
            
            Button("Save OpenAI Key") {
                storedOpenAIKey = openAIKeyInput
                openAIStatus = "API key saved successfully!"
                
                // Clear status after 2 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    openAIStatus = nil
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(openAIKeyInput.isEmpty)
            
            if let openAIStatus {
                Text(openAIStatus)
                    .font(.footnote)
                    .foregroundStyle(.green)
            }
            
            if !storedOpenAIKey.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("API key configured")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            
            Text("Required for AI Trading features. Get your API key from platform.openai.com")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
    
    private var ingestionSection: some View {
        Section(header: Text("MySQL Ingestion")) {
            @Bindable var ingestion = app.ingestionSettings
            Toggle("Enable Ingestion", isOn: $ingestion.enabled)
            TextField("Host", text: $ingestion.host)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)
#if os(iOS) || os(visionOS)
                .autocapitalization(.none)
#endif
            TextField("Port", value: $ingestion.port, format: .number)
                .textFieldStyle(.roundedBorder)
#if os(iOS) || os(visionOS)
                .keyboardType(.numberPad)
#endif
            TextField("Database", text: $ingestion.database)
                .textFieldStyle(.roundedBorder)
#if os(iOS) || os(visionOS)
                .autocapitalization(.none)
#endif
            TextField("Username", text: $ingestion.username)
                .textFieldStyle(.roundedBorder)
#if os(iOS) || os(visionOS)
                .autocapitalization(.none)
#endif
            SecureField("Password", text: $ingestion.password)
                .textFieldStyle(.roundedBorder)
            Toggle("Use TLS", isOn: $ingestion.useTLS)
            Text("Credentials should be stored securely (e.g., Keychain). These fields are configuration bindings only.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var safetySection: some View {
        Section(header: Text("Trading Safety")) {
            @Bindable var safety = app.safety
            Toggle("Paper Mode (simulate only)", isOn: $safety.paperMode)
            HStack {
                Text("Max Notional / Order (USD)")
                Spacer()
                TextField("5000", value: $safety.maxNotionalPerOrderUSD, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 160)
#if os(iOS) || os(visionOS)
                    .keyboardType(.decimalPad)
#endif
            }
            HStack {
                Text("Daily Exposure Limit (USD)")
                Spacer()
                TextField("25000", value: $safety.dailyExposureLimitUSD, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 160)
#if os(iOS) || os(visionOS)
                    .keyboardType(.decimalPad)
#endif
            }
            TextField("Symbol Whitelist (CSV)", text: $safety.symbolWhitelistCSV)
                .textFieldStyle(.roundedBorder)
#if os(iOS) || os(visionOS)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled(true)
#endif
            Text("Leave empty to allow all symbols. Use uppercase symbols, e.g., BTC-USD,ETH-USD.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func syncFields() {
        apiKeyInput = app.apiKey
        privateKeySeedInput = app.base64PrivateKeySeed
        publicKeyInput = app.base64PublicKey
        baseURLInput = app.baseURL.absoluteString
        brokerStatus = nil
        brokerError = nil
        
        // Load OpenAI key if stored
        if !storedOpenAIKey.isEmpty {
            openAIKeyInput = storedOpenAIKey
        }
    }

    private func applyBrokerUpdates() {
        let trimmedURL = baseURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedURL), let scheme = url.scheme, !scheme.isEmpty else {
            brokerError = "Enter a valid base URL including scheme."
            brokerStatus = nil
            return
        }
        brokerError = nil
        brokerStatus = "Updating credentials..."
        Task { @MainActor in
            app.refreshBroker(apiKey: apiKeyInput, base64Seed: privateKeySeedInput, base64PublicKey: publicKeyInput, baseURL: url)
            brokerStatus = "Credentials applied."
        }
    }
    
    private func generateNewKeyPair() {
        brokerStatus = "Generating new key pair..."
        brokerError = nil
        
        Task {
            do {
                let (privateKey, publicKey) = try await generateEd25519KeyPair()
                await MainActor.run {
                    privateKeySeedInput = privateKey
                    publicKeyInput = publicKey
                    brokerStatus = "New key pair generated successfully!"
                }
            } catch {
                await MainActor.run {
                    brokerError = "Failed to generate key pair: \(error.localizedDescription)"
                    brokerStatus = nil
                }
            }
        }
    }
    
    private func generateEd25519KeyPair() async throws -> (privateKey: String, publicKey: String) {
        // Generate Ed25519 key pair using CryptoKit
        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKey = privateKey.publicKey
        
        // Convert to base64 strings
        let privateKeyBase64 = privateKey.rawRepresentation.base64EncodedString()
        let publicKeyBase64 = publicKey.rawRepresentation.base64EncodedString()
        
        return (privateKeyBase64, publicKeyBase64)
    }
    
    // MARK: - Modern UI Components
    
    private func modernTextField(title: String, text: Binding<String>, placeholder: String = "", isSecure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
            
            Group {
                if isSecure {
                    SecureField(placeholder.isEmpty ? title : placeholder, text: text)
                } else {
                    TextField(placeholder.isEmpty ? title : placeholder, text: text)
                }
            }
            .font(.system(size: 16))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(red: 0.12, green: 0.12, blue: 0.16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
            .disableAutocorrection(true)
#if os(iOS) || os(visionOS)
            .autocapitalization(.none)
            .keyboardType(placeholder.contains("http") ? .URL : .default)
#endif
        }
    }
}

// MARK: - Modern Button Style
struct ModernButtonStyle: ButtonStyle {
    enum Style {
        case primary, secondary
    }
    
    let style: Style
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(style == .primary ? .white : .blue)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(style == .primary ? Color.blue : Color.blue.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

#Preview {
    NavigationStack { SettingsView().environment(ApplicationState()) }
}
