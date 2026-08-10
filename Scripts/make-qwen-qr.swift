#!/usr/bin/env swift

import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Darwin
import Foundation

struct Configuration: Codable {
    let v: Int
    let provider: String
    let region: String
    let api_key: String
}

print("轻衡将使用千问按量付费北京接口：")
print("https://dashscope.aliyuncs.com/compatible-mode/v1\n")
guard let passwordPointer = getpass("API Key（输入时不会显示）: ") else {
    fputs("\n无法读取 API Key。\n", stderr)
    exit(1)
}
let apiKey = String(cString: passwordPointer)

guard apiKey.hasPrefix("sk-"),
      apiKey.count >= 12
else {
    fputs("\nAPI Key 格式不正确，应为 sk- 开头的完整密钥。\n", stderr)
    exit(1)
}

let configuration = Configuration(
    v: 2,
    provider: "dashscope",
    region: "cn-beijing",
    api_key: apiKey
)
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
guard let payload = try? encoder.encode(configuration) else {
    fputs("\n无法生成配置。\n", stderr)
    exit(1)
}

let filter = CIFilter.qrCodeGenerator()
filter.message = payload
filter.correctionLevel = "M"
guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 9, y: 9)) else {
    fputs("\n无法生成二维码。\n", stderr)
    exit(1)
}

let backgroundExtent = CGRect(
    x: 0,
    y: 0,
    width: output.extent.width + 64,
    height: output.extent.height + 64
)
let white = CIImage(color: .white).cropped(to: backgroundExtent)
let positionedQR = output.transformed(
    by: CGAffineTransform(translationX: 32 - output.extent.origin.x, y: 32 - output.extent.origin.y)
)
let finalImage = positionedQR.composited(over: white).cropped(to: backgroundExtent)
let context = CIContext(options: [.useSoftwareRenderer: false])
guard let cgImage = context.createCGImage(finalImage, from: backgroundExtent) else {
    fputs("\n无法显示二维码。\n", stderr)
    exit(1)
}

final class QRApplicationDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let image: NSImage
    private var window: NSWindow?

    init(image: NSImage) {
        self.image = image
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let imageSide: CGFloat = min(max(image.size.width, 320), 620)
        let contentSize = CGSize(width: imageSide + 48, height: imageSide + 104)
        let contentView = NSView(frame: CGRect(origin: .zero, size: contentSize))

        let imageView = NSImageView(frame: CGRect(
            x: 24,
            y: 64,
            width: imageSide,
            height: imageSide
        ))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        contentView.addSubview(imageView)

        let label = NSTextField(labelWithString: "使用轻衡扫描 · 完成后关闭窗口")
        label.alignment = .center
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.frame = CGRect(x: 24, y: 24, width: imageSide, height: 22)
        contentView.addSubview(label)

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "轻衡 · Qwen 配置"
        window.contentView = contentView
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window

        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        NSApplication.shared.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = QRApplicationDelegate(
    image: NSImage(cgImage: cgImage, size: backgroundExtent.size)
)
app.setActivationPolicy(.regular)
app.delegate = delegate
print("\n二维码仅在内存窗口中显示，不会写入磁盘。扫描完成后关闭窗口。")
app.run()
