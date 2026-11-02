import AppKit
import VCL

// Renders forms of the original BLHeliSuite through the VCL runtime and saves PNG snapshots.
// usage: vcl-preview <out dir> [FORMNAME ...]
let args = CommandLine.arguments
let out = URL(fileURLWithPath: args.count > 1 ? args[1] : NSTemporaryDirectory())
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
DFMLoader.verbose = ProcessInfo.processInfo.environment["VCL_VERBOSE"] != nil

final class PreviewForm: TForm {}

var names = Array(args.dropFirst(2))
if names.isEmpty, let f = Resources.folder {
    names = (try? FileManager.default.contentsOfDirectory(atPath: f.appendingPathComponent("Forms").path))?
        .filter { $0.hasPrefix("TFRM") || $0 == "TABOUTBOX.dfm" }.map { String($0.dropLast(4)) }.sorted() ?? []
}
for n in names {
    let f = PreviewForm(resource: n)
    f.formWindow.orderFront(nil)
    f.container.display()
    if let png = f.screenshotPNG() {
        try? png.write(to: out.appendingPathComponent("\(n).png"))
        print("\(n): \(Int(f.container.bounds.width))x\(Int(f.container.bounds.height))")
    }
    f.formWindow.orderOut(nil)
}
if names.count == 1 {
    let f = PreviewForm(resource: names[0])
    print("debug: frame=\(f.frame) container=\(f.container.frame) controls=\(f.controls.count) comps=\(f.components.count)")
}
