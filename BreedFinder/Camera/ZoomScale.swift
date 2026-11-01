import AVFoundation

/// Translates between the zoom numbers people know from the Camera app, where 1× is the
/// main lens, and a capture device's own zoom factors, and picks the zoom buttons to show.
///
/// On phones with an ultra-wide lens, the combined back camera starts at the ultra-wide
/// (the Camera app's 0.5×), so 1× there is a device zoom factor of 2.
struct ZoomScale: Equatable {
    /// The most zoom offered. Further in, every iPhone enlarges the picture digitally,
    /// which blurs it rather than adding detail.
    static let limit: CGFloat = 10

    /// The device zoom factor the Camera app calls 1×.
    let mainLensFactor: CGFloat
    /// The widest view: 0.5× (the ultra-wide lens) on phones that have one, otherwise 1×.
    let minZoom: CGFloat
    /// The most zoom this phone offers, in the Camera app's numbers.
    let maxZoom: CGFloat
    /// Zoom buttons: 0.5× on phones with an ultra-wide lens, 1×, 2×, and the telephoto
    /// lens's zoom on phones that have one.
    let presets: [CGFloat]

    init(lenses: [AVCaptureDevice.DeviceType], switchOverFactors: [CGFloat], maxDeviceFactor: CGFloat) {
        let mainLensFactor = lenses.contains(.builtInUltraWideCamera) ? max(switchOverFactors.first ?? 1, 1) : 1
        // The combined camera's smallest zoom factor, 1, is the ultra-wide lens.
        let minZoom = 1 / mainLensFactor
        let maxZoom = max(min(maxDeviceFactor / mainLensFactor, Self.limit), 1)

        var presets: [CGFloat] = [1, 2]
        if mainLensFactor > 1 {
            presets.append((minZoom * 10).rounded() / 10)  // 0.5× for a dog that's too close
        }
        // The combined camera hands over to the telephoto lens at its last switch-over factor.
        if lenses.contains(.builtInTelephotoCamera), let telephoto = switchOverFactors.last {
            presets.append((telephoto / mainLensFactor * 10).rounded() / 10)
        }

        self.mainLensFactor = mainLensFactor
        self.minZoom = minZoom
        self.maxZoom = maxZoom
        self.presets = Set(presets).filter { $0 >= minZoom && $0 <= maxZoom }.sorted()
    }

    init(camera: AVCaptureDevice) {
        self.init(
            lenses: camera.constituentDevices.map(\.deviceType),
            switchOverFactors: camera.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat($0.doubleValue) },
            maxDeviceFactor: camera.activeFormat.videoMaxZoomFactor
        )
    }

    func deviceFactor(for zoom: CGFloat) -> CGFloat {
        zoom * mainLensFactor
    }

    /// A zoom level written the Camera app's way: "0.5", "1", "2.4", "5".
    static func label(for zoom: CGFloat) -> String {
        let tenths = (zoom * 10).rounded() / 10
        return tenths == tenths.rounded() ? String(Int(tenths)) : String(format: "%.1f", tenths)
    }
}
