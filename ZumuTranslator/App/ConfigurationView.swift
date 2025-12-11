import SwiftUI

struct ConfigurationView: View {
    @State private var driverName = ""
    @State private var driverLanguage = "English"
    @State private var passengerName = ""
    @State private var passengerLanguage = "Spanish"

    let onStart: (ZumuTokenSource.TranslationConfig) -> Void

    private let supportedLanguages = ["English", "Spanish", "Russian", "Chinese", "Arabic", "Hindi", "Turkish"]

    var body: some View {
        NavigationView {
            Form {
                Section("Driver") {
                    TextField("Name", text: $driverName)
                        .autocapitalization(.words)

                    Picker("Language", selection: $driverLanguage) {
                        ForEach(supportedLanguages, id: \.self) { language in
                            Text(language).tag(language)
                        }
                    }
                }

                Section("Passenger") {
                    TextField("Name", text: $passengerName)
                        .autocapitalization(.words)

                    Picker("Language", selection: $passengerLanguage) {
                        ForEach(supportedLanguages, id: \.self) { language in
                            Text(language).tag(language)
                        }
                    }
                }

                Section {
                    Button(action: startTranslation) {
                        HStack {
                            Spacer()
                            Text("Start Translation")
                                .font(.headline)
                            Spacer()
                        }
                    }
                    .disabled(driverName.isEmpty || passengerName.isEmpty)
                }
            }
            .navigationTitle("Zumu Translator")
        }
    }

    private func startTranslation() {
        let config = ZumuTokenSource.TranslationConfig(
            driverName: driverName.isEmpty ? "Driver" : driverName,
            driverLanguage: driverLanguage,
            passengerName: passengerName.isEmpty ? "Passenger" : passengerName,
            passengerLanguage: passengerLanguage,
            tripId: UUID().uuidString
        )
        onStart(config)
    }
}
