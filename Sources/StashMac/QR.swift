//  Stash for Mac — MIT licensed. See LICENSE.
//
//  The recovery card: 24 words, a QR code of the same key, the fingerprint, and the date. Rendered
//  with Core Image (no dependency) and read back with Vision, so a card can be scanned by a phone
//  camera or by the app on a new Mac.

import Foundation
import AppKit
import CoreImage
import Vision

enum QR {
    /// A crisp QR image of the payload at the requested pixel size.
    static func image(_ payload: String, size: Int = 512) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let ci = filter.outputImage else { return nil }
        let scale = CGFloat(size) / ci.extent.width
        let scaled = ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let rep = NSCIImageRep(ciImage: scaled)
        let img = NSImage(size: rep.size)
        img.addRepresentation(rep)
        return img
    }

    static func png(_ payload: String, size: Int = 512) -> Data? {
        guard let img = image(payload, size: size), let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// First QR payload found in an image, if any.
    static func read(_ data: Data) -> String? {
        guard let img = NSImage(data: data), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
        return request.results?.first?.payloadStringValue
    }

    /// The printable recovery card as a PDF: words, QR, fingerprint, date, one plain-language warning.
    @MainActor
    static func recoveryCard(_ key: MasterKey, stashName: String) -> Data? {
        let page = NSRect(x: 0, y: 0, width: 612, height: 792)   // US Letter in points
        let view = NSView(frame: page)
        let pdf = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdf), var mediaBox = Optional(page),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }
        ctx.beginPDFPage(nil)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        func draw(_ s: String, at p: NSPoint, size: CGFloat, bold: Bool = false, color: NSColor = .black) {
            (s as NSString).draw(at: p, withAttributes: [.font: bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size), .foregroundColor: color])
        }
        draw("Stash for Mac recovery card", at: NSPoint(x: 54, y: 720), size: 22, bold: true)
        draw("Stash: \(stashName)   Key: \(key.fingerprint)   Made: \(Date().formatted(date: .long, time: .omitted))", at: NSPoint(x: 54, y: 696), size: 11, color: .darkGray)
        draw("These 24 words are the only way to read this backup. Keep this card somewhere safe and private.", at: NSPoint(x: 54, y: 672), size: 12)
        draw("Stash for Mac never keeps a copy. If the card is lost, the backup cannot be read by anyone, including you.", at: NSPoint(x: 54, y: 656), size: 12)
        let words = key.words
        for (i, w) in words.enumerated() {
            let col = i % 4, row = i / 4
            draw(String(format: "%2d.", i + 1), at: NSPoint(x: 60 + CGFloat(col) * 130, y: 610 - CGFloat(row) * 28), size: 13, color: .darkGray)
            draw(w, at: NSPoint(x: 88 + CGFloat(col) * 130, y: 610 - CGFloat(row) * 28), size: 15, bold: true)
        }
        if let qr = image(key.qrPayload, size: 600) {
            qr.draw(in: NSRect(x: 206, y: 150, width: 200, height: 200))
            draw("Scan with the phone camera, or with Stash for Mac on a new Mac.", at: NSPoint(x: 160, y: 130), size: 11, color: .darkGray)
        }
        draw("stashmac restore  ·  github.com/keithadler/stashmac", at: NSPoint(x: 54, y: 60), size: 10, color: .gray)
        ctx.endPDFPage()
        ctx.closePDF()
        _ = view
        return pdf as Data
    }
}
