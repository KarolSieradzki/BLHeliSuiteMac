import SwiftUI
import BLHeliCore

/// Chooses the classic BLHeliSuite look (default) or the modern macOS layout.
struct RootView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("uiStyle") private var uiStyle = "classic"

    var classic: Bool { uiStyle != "modern" }

    var body: some View {
        Group {
            if classic {
                ClassicMainView()
            } else {
                ContentView()
                    .frame(minWidth: 1100, minHeight: 780)
                    .navigationTitle("BLHeliSuite")
            }
        }
        .modifier(ModelDialogs(classic: classic))
        .onAppear {
            let a = CommandLine.arguments
            // GUI tests remember the user's preferences before `--style` changes the look
            let autoTest = AutoTest.fromArguments()
            let uiTest = autoTest == nil ? UITest.fromArguments() : nil
            if let i = a.firstIndex(of: "--style"), i + 1 < a.count { uiStyle = a[i + 1] }
            if let t = autoTest {
                AutoTest.current = t
                t.run(model)
            } else if let t = uiTest {
                UITest.current = t
                t.run(model)
            }
        }
    }
}

/// Alerts, confirmations and the flash assistant – shared by both looks.
struct ModelDialogs: ViewModifier {
    @EnvironmentObject var model: AppModel
    let classic: Bool

    func body(content: Content) -> some View {
        content
            .alert(item: $model.alert) { a in
                Alert(title: Text(a.title), message: Text(a.message), dismissButton: .default(Text("OK")))
            }
            .sheet(isPresented: $model.showFlashAssistant) {
                if classic {
                    ClassicFlashAssistant().environmentObject(model)
                } else {
                    FlashAssistantView().environmentObject(model)
                }
            }
            .confirmationDialog(model.confirm?.title ?? "", isPresented: Binding(get: { model.confirm != nil }, set: { if !$0 { model.confirm = nil } }), titleVisibility: .visible) {
                if let c = model.confirm {
                    Button(c.destructive ? "Yes, continue" : "OK", role: c.destructive ? .destructive : nil) {
                        let action = c.action
                        model.confirm = nil
                        action()
                    }
                    Button("Cancel", role: .cancel) { model.confirm = nil }
                }
            } message: {
                Text(model.confirm?.message ?? "")
            }
    }
}
