import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var faceDown = FaceDownMonitor()
    @AppStorage("cv.faceDownAction") private var faceDownAction: FaceDownAction = .calculator
    @AppStorage("cv.faceDownCustomURL") private var faceDownCustomURL = ""

    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.05, blue: 0.075).ignoresSafeArea()

            Group {
                switch model.route {
                case .setup: SetupView()
                case .calculator: CalculatorView()
                case .biometric: BiometricUnlockView()
                case .pattern: PatternUnlockView()
                case .vault: VaultHomeView()
                case .decoy: DecoyVaultView()
                }
            }
            .foregroundStyle(.white)
            .tint(.cyan)

            if scenePhase != .active {
                Color.black.ignoresSafeArea()
                VStack(spacing: 16) {
                    Image(systemName: "plus.slash.minus").font(.system(size: 52))
                    Text("Calculator").font(.title2)
                }
            }
        }
        .onAppear { updateMotion() }
        .onChange(of: model.route) { _, _ in updateMotion() }
        .onChange(of: scenePhase) { _, _ in updateMotion() }
        .alert("CipherVault", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .preferredColorScheme(.dark)
    }

    private func updateMotion() {
        faceDown.stop()
        if scenePhase == .active && (model.route == .vault || model.route == .decoy) {
            faceDown.start {
                // Always remove access to decrypted vault content first.
                model.emergencyCover()
                faceDownAction.openDestination(customWebsite: faceDownCustomURL)
            }
        }
    }
}

struct SetupView: View {
    @EnvironmentObject private var model: AppModel
    @State private var calculator = ""
    @State private var confirm = ""
    @State private var firstPattern = ""
    @State private var step = 0
    @State private var hint: String?

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 46)).foregroundStyle(.cyan)
            Text("Secure Setup").font(.largeTitle.bold())
            Text("Your files will stay encrypted on this iPhone. Face ID is mandatory; there is no iPhone-passcode fallback.")
                .font(.subheadline).multilineTextAlignment(.center).foregroundStyle(.secondary)
            if step == 0 {
                SecureField("6–12 digit calculator code", text: $calculator)
                    .keyboardType(.numberPad).textContentType(.newPassword)
                    .padding().background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                SecureField("Confirm calculator code", text: $confirm)
                    .keyboardType(.numberPad).textContentType(.newPassword)
                    .padding().background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                Button("Next: Draw pattern") {
                    if calculator == confirm, (6...12).contains(calculator.count),
                       calculator.allSatisfy(\.isNumber) { step = 1; hint = nil }
                    else { hint = "Codes must match and contain 6–12 digits." }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text(step == 1 ? "Draw your swipe pattern" : "Draw the same pattern again")
                    .font(.headline)
                PatternPad { pattern in
                    if step == 1 {
                        firstPattern = pattern
                        step = 2
                        hint = nil
                    } else if pattern != firstPattern {
                        hint = "Pattern didn't match. Try drawing it again."
                    } else {
                        do { try model.configure(calculator: calculator, pattern: pattern) }
                        catch { hint = error.localizedDescription }
                    }
                }
                .frame(maxWidth: 280)
            }
            if let hint { Text(hint).font(.footnote).foregroundStyle(.orange) }
            Spacer(minLength: 0)
            Text("Important: Changing enrolled Face ID or losing this device may make vault data permanently inaccessible until a recovery feature is added.")
                .font(.caption2).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
        .padding(24)
    }
}

struct BiometricUnlockView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "faceid").font(.system(size: 84)).foregroundStyle(.cyan)
            Text("Verify Face ID").font(.largeTitle.bold())
            Text("Only enrolled Face ID may continue. Device passcode fallback is disabled.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button {
                Task { await model.authenticateWithFaceID() }
            } label: {
                Label("Use Face ID", systemImage: "faceid")
                    .frame(maxWidth: .infinity).padding(8)
            }.buttonStyle(.borderedProminent)
            Button("Back to Calculator") { model.emergencyCover() }
                .foregroundStyle(.secondary)
            Spacer()
        }.padding(28)
    }
}

struct PatternUnlockView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "circle.grid.cross").font(.system(size: 38)).foregroundStyle(.cyan)
            Text("Final Lock").font(.largeTitle.bold())
            Text("Draw your private 3×3 pattern").foregroundStyle(.secondary)
            PatternPad { model.patternEntered($0) }.frame(maxWidth: 300)
            Button("Cancel") { model.emergencyCover() }.foregroundStyle(.secondary)
            Spacer()
        }.padding(28)
    }
}

struct DecoyVaultView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "folder").font(.system(size: 56)).foregroundStyle(.secondary)
                Text("No saved items").font(.title3)
                Text("Your collection is empty.").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("My Files")
            .toolbar { Button("Close") { model.emergencyCover() } }
        }
    }
}
