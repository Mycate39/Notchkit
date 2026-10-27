// Planche d'images légendées pour le banc d'essai visuel (scripts/visual-matrix.py).
// Usage : contact-sheet <sortie.png> <colonnes> <largeur-cellule> <image> <légende> [<image> <légende>…]
import AppKit

let args = CommandLine.arguments
guard args.count >= 6, let columns = Int(args[2]), let cellWidth = Double(args[3]) else {
    FileHandle.standardError.write(Data("usage : contact-sheet sortie colonnes largeur (image légende)…\n".utf8))
    exit(1)
}
let pairs = stride(from: 4, to: args.count - 1, by: 2).map { (args[$0], args[$0 + 1]) }
let images = pairs.map { NSImage(contentsOfFile: $0.0) }
let ratio = images.compactMap { $0 }.first.map { $0.size.height / $0.size.width } ?? 0.33
let label = 26.0
let cell = CGSize(width: cellWidth, height: cellWidth * ratio + label)
let rows = (pairs.count + columns - 1) / columns
let size = CGSize(width: cell.width * Double(columns), height: cell.height * Double(rows))

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSColor(white: 0.16, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.monospacedSystemFont(ofSize: 15, weight: .semibold), .foregroundColor: NSColor.white,
]
for (index, pair) in pairs.enumerated() {
    let x = Double(index % columns) * cell.width
    let top = size.height - Double(index / columns) * cell.height
    images[index]?.draw(in: NSRect(x: x, y: top - cell.height, width: cell.width, height: cell.height - label))
    NSString(string: pair.1).draw(at: NSPoint(x: x + 8, y: top - label + 4), withAttributes: attributes)
    NSColor(white: 0.35, alpha: 1).setFill()
    NSRect(x: x, y: top - cell.height, width: 1, height: cell.height).fill()
}
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[1]))
