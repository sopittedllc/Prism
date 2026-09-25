import AppKit

// Preserve the supplied image's RGB AND alpha. Transparent RGB pixels are not artwork.
// Only scale the original onto the standard Dock tile; never reconstruct its shape.
let source = URL(fileURLWithPath: CommandLine.arguments[1])
let target = URL(fileURLWithPath: CommandLine.arguments[2])
let original = try Data(contentsOf: source)
guard let mark = NSImage(data: original) else { fatalError("Cannot decode supplied app icon") }
let markRep = NSBitmapImageRep(data: mark.tiffRepresentation!)!
try markRep.representation(using: .png, properties: [:])!.write(to: target.appendingPathComponent("AppMark.png"))
let icon = NSImage(size: NSSize(width: 1024, height: 1024))
icon.lockFocus()
NSColor.white.setFill()
NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 190, yRadius: 190).fill()
mark.draw(in: NSRect(x: 180, y: 180, width: 664, height: 664), from: .zero, operation: .sourceOver, fraction: 1)
icon.unlockFocus()
let iconRep = NSBitmapImageRep(data: icon.tiffRepresentation!)!
try iconRep.representation(using: .png, properties: [:])!.write(to: target.appendingPathComponent("IconMaster.png"))
