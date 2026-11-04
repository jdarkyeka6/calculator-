import SwiftUI

struct SecurityView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var addingDuress = false
    @State private var notice: String?
    @AppStorage("cv.faceDownAction") private var faceDownAction: FaceDownAction = .calculator
    @AppStorage("cv.faceDownCustomURL") private var faceDownCustomURL = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Privacy") {
                    Label("Face ID only: no iPhone passcode fallback", systemImage: "faceid")
                    Label("AES-256-GCM encrypted local files", systemImage: "lock.shield")
                    Label("Face-down gesture immediately locks the vault", systemImage: "iphone.gen3")
                    Label("Automatic lock after importing", systemImage: "arrow.down.doc")
                }
                Section("Face-down action") {
                    Picker("When face down", selection: $faceDownAction) {
                        ForEach(FaceDownAction.allCases) { action in
                            Text(action.title).tag(action)
                        }
                    }
                    if faceDownAction == .customWebsite {
                        TextField("Website, e.g. example.com", text: $faceDownCustomURL)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                        if FaceDownAction.safeWebsite(faceDownCustomURL) == nil {
                            Text("Enter a valid HTTPS address to enable the website action.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    Text("When the vault is open, turning your iPhone face down locks your encrypted files first, then attempts to open your selected destination. iOS controls whether another app or its website opens. This does not run while CipherVault is in the background or bypass device restrictions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Duress") {
                    Button(CredentialStore.hasDuressPattern ? "Change decoy pattern" : "Create decoy pattern") {
                        addingDuress = true
                    }
                    Text("Your decoy pattern opens an empty, separate interface without unlocking real files.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Recent security events") {
                    if AttemptLog.events.isEmpty {
                        Text("No events").foregroundStyle(.secondary)
                    }
                    ForEach(AttemptLog.events) { event in
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(event.stage): \(event.result)")
                            Text(event.time.formatted(date: .abbreviated, time: .standard))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text("Attempt logs are local diagnostics, not tamper-proof forensic evidence. Intruder video recording is not included in this initial build.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Security Centre")
            .toolbar { Button("Done") { dismiss() } }
            .sheet(isPresented: $addingDuress) {
                NavigationStack {
                    VStack(spacing: 18) {
                        Text("Draw a different pattern to open the decoy vault.").multilineTextAlignment(.center)
                        PatternPad { value in
                            do {
                                try model.enableDuressPattern(value)
                                notice = "Decoy pattern saved."
                                addingDuress = false
                            } catch {
                                notice = error.localizedDescription
                            }
                        }.frame(maxWidth: 290)
                        if let notice { Text(notice).foregroundStyle(.orange) }
                    }
                    .padding(25)
                    .navigationTitle("Duress Pattern")
                    .toolbar { Button("Cancel") { addingDuress = false } }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
