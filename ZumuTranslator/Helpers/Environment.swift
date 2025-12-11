import SwiftUI

extension EnvironmentValues {
    @Entry var voiceEnabled: Bool = true
    @Entry var videoEnabled: Bool = false  // Translation is voice-only
    @Entry var textEnabled: Bool = false   // No chat initially
    @Entry var namespace: Namespace.ID? // don't initialize outside View
    @Entry var translationConfig: ZumuTokenSource.TranslationConfig?
}
