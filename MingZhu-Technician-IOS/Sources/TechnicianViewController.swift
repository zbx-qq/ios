import CoreLocation
import UIKit
import WebKit

final class TechnicianViewController: UIViewController {
    private let appURL = URL(string: "https://ymz.taimingzhu.com/technician/login")!
    private var webView: WKWebView!
    private var locationBridge: NativeLocationBridge!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        configureWebView()
        webView.load(URLRequest(url: appURL))
    }

    private func configureWebView() {
        let userContentController = WKUserContentController()
        let bridgeScript = """
        (function () {
          if (window.MingZhuNativeLocation) return;
          window.MingZhuNativeLocation = {
            isAvailable: function () { return 'true'; },
            getBestLocation: function (requestId) {
              window.webkit.messageHandlers.MingZhuNativeLocation.postMessage({
                method: 'getBestLocation',
                requestId: String(requestId || '')
              });
            }
          };
          var meta = document.querySelector('meta[name="viewport"]');
          if (!meta) {
            meta = document.createElement('meta');
            meta.setAttribute('name', 'viewport');
            document.head.appendChild(meta);
          }
          meta.setAttribute('content', 'width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover');
          var style = document.createElement('style');
          style.textContent = 'html,body{touch-action:manipulation;-webkit-text-size-adjust:100%;}';
          document.head.appendChild(style);
        })();
        """
        userContentController.addUserScript(WKUserScript(
            source: bridgeScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = userContentController
        configuration.allowsInlineMediaPlayback = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.scrollView.delegate = self
        webView.scrollView.bounces = false
        webView.scrollView.pinchGestureRecognizer?.isEnabled = false
        webView.customUserAgent = "MingZhuTechnicianIOS/1.0"
        view.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        locationBridge = NativeLocationBridge(webView: webView)
        userContentController.add(locationBridge, name: "MingZhuNativeLocation")
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        webView.scrollView.contentInsetAdjustmentBehavior = .never
    }
}

extension TechnicianViewController: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            decisionHandler(.allow)
            return
        }
        UIApplication.shared.open(url)
        decisionHandler(.cancel)
    }
}

extension TechnicianViewController: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }
}

extension TechnicianViewController: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        nil
    }
}

private final class NativeLocationBridge: NSObject, WKScriptMessageHandler, CLLocationManagerDelegate {
    private weak var webView: WKWebView?
    private let manager = CLLocationManager()
    private var pendingRequestId: String?
    private var bestLocation: CLLocation?
    private var locationCount = 0
    private var timeoutWorkItem: DispatchWorkItem?
    private let targetCount = 5
    private let minCount = 3

    init(webView: WKWebView) {
        self.webView = webView
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "MingZhuNativeLocation" else { return }
        guard
            let body = message.body as? [String: Any],
            (body["method"] as? String) == "getBestLocation"
        else { return }
        let requestId = body["requestId"] as? String ?? ""
        startBestLocation(requestId: requestId)
    }

    private func startBestLocation(requestId: String) {
        stopLocation()
        pendingRequestId = requestId
        bestLocation = nil
        locationCount = 0

        if !CLLocationManager.locationServicesEnabled() {
            finishError(code: "LOCATION_SERVICE_OFF", message: "手机定位服务未开启")
            return
        }

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            finishError(code: "PERMISSION_DENIED", message: "定位权限未开启")
        case .authorizedAlways, .authorizedWhenInUse:
            beginUpdatingLocation()
        @unknown default:
            finishError(code: "PERMISSION_UNKNOWN", message: "定位权限状态异常")
        }
    }

    private func beginUpdatingLocation() {
        let timeout = DispatchWorkItem { [weak self] in
            self?.finishBestOrError()
        }
        timeoutWorkItem = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.5, execute: timeout)
        manager.startUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard pendingRequestId != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            beginUpdatingLocation()
        case .restricted, .denied:
            finishError(code: "PERMISSION_DENIED", message: "定位权限未开启")
        case .notDetermined:
            break
        @unknown default:
            finishError(code: "PERMISSION_UNKNOWN", message: "定位权限状态异常")
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard pendingRequestId != nil else { return }
        for location in locations {
            guard location.horizontalAccuracy >= 0 else { continue }
            locationCount += 1
            if bestLocation == nil || location.horizontalAccuracy < (bestLocation?.horizontalAccuracy ?? .greatestFiniteMagnitude) {
                bestLocation = location
            }
        }
        guard let bestLocation else { return }
        if (locationCount >= minCount && bestLocation.horizontalAccuracy <= 50) || locationCount >= targetCount {
            finishSuccess(location: bestLocation)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard pendingRequestId != nil else { return }
        finishError(code: "LOCATION_FAILED", message: error.localizedDescription)
    }

    private func finishBestOrError() {
        if let bestLocation {
            finishSuccess(location: bestLocation)
        } else {
            finishError(code: "LOCATION_FAILED", message: "未获取到有效定位")
        }
    }

    private func finishSuccess(location: CLLocation) {
        let gcj = CoordinateConverter.wgs84ToGcj02(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        let accuracy = max(location.horizontalAccuracy, 0)
        let payload: [String: Any] = [
            "requestId": pendingRequestId ?? "",
            "success": true,
            "source": "amap-native",
            "coordinateSystem": "GCJ-02",
            "rawCoordinateSystem": "WGS84",
            "rawLatitude": location.coordinate.latitude,
            "rawLongitude": location.coordinate.longitude,
            "latitude": gcj.latitude,
            "longitude": gcj.longitude,
            "accuracy": accuracy,
            "locationType": "ios-corelocation",
            "provider": "corelocation",
            "province": "",
            "city": "",
            "district": "",
            "address": "",
            "name": "",
            "finePermission": isPreciseLocationEnabled(),
            "coarsePermission": true,
            "locationServiceEnabled": CLLocationManager.locationServicesEnabled(),
            "powerSaveMode": ProcessInfo.processInfo.isLowPowerModeEnabled,
            "isLowAccuracy": accuracy > 150,
            "requiresManualConfirm": accuracy > 200
        ]
        complete(payload)
    }

    private func finishError(code: String, message: String) {
        let payload: [String: Any] = [
            "requestId": pendingRequestId ?? "",
            "success": false,
            "code": code,
            "message": message,
            "finePermission": isPreciseLocationEnabled(),
            "coarsePermission": false,
            "locationServiceEnabled": CLLocationManager.locationServicesEnabled(),
            "powerSaveMode": ProcessInfo.processInfo.isLowPowerModeEnabled
        ]
        complete(payload)
    }

    private func complete(_ payload: [String: Any]) {
        stopLocation()
        guard
            let data = try? JSONSerialization.data(withJSONObject: payload),
            let json = String(data: data, encoding: .utf8)
        else {
            pendingRequestId = nil
            return
        }
        let script = "window.__MingZhuNativeLocationCallback&&window.__MingZhuNativeLocationCallback(\(json));"
        webView?.evaluateJavaScript(script)
        pendingRequestId = nil
    }

    private func stopLocation() {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        manager.stopUpdatingLocation()
    }

    private func isPreciseLocationEnabled() -> Bool {
        if #available(iOS 14.0, *) {
            return manager.accuracyAuthorization == .fullAccuracy
        }
        return true
    }
}

private enum CoordinateConverter {
    private static let a = 6378245.0
    private static let ee = 0.00669342162296594323

    static func wgs84ToGcj02(latitude: Double, longitude: Double) -> (latitude: Double, longitude: Double) {
        if outOfChina(latitude: latitude, longitude: longitude) {
            return (latitude, longitude)
        }
        var dLat = transformLat(x: longitude - 105.0, y: latitude - 35.0)
        var dLon = transformLon(x: longitude - 105.0, y: latitude - 35.0)
        let radLat = latitude / 180.0 * Double.pi
        var magic = sin(radLat)
        magic = 1 - ee * magic * magic
        let sqrtMagic = sqrt(magic)
        dLat = (dLat * 180.0) / ((a * (1 - ee)) / (magic * sqrtMagic) * Double.pi)
        dLon = (dLon * 180.0) / (a / sqrtMagic * cos(radLat) * Double.pi)
        return (latitude + dLat, longitude + dLon)
    }

    private static func outOfChina(latitude: Double, longitude: Double) -> Bool {
        longitude < 72.004 || longitude > 137.8347 || latitude < 0.8293 || latitude > 55.8271
    }

    private static func transformLat(x: Double, y: Double) -> Double {
        var ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * Double.pi) + 20.0 * sin(2.0 * x * Double.pi)) * 2.0 / 3.0
        ret += (20.0 * sin(y * Double.pi) + 40.0 * sin(y / 3.0 * Double.pi)) * 2.0 / 3.0
        ret += (160.0 * sin(y / 12.0 * Double.pi) + 320 * sin(y * Double.pi / 30.0)) * 2.0 / 3.0
        return ret
    }

    private static func transformLon(x: Double, y: Double) -> Double {
        var ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * Double.pi) + 20.0 * sin(2.0 * x * Double.pi)) * 2.0 / 3.0
        ret += (20.0 * sin(x * Double.pi) + 40.0 * sin(x / 3.0 * Double.pi)) * 2.0 / 3.0
        ret += (150.0 * sin(x / 12.0 * Double.pi) + 300.0 * sin(x / 30.0 * Double.pi)) * 2.0 / 3.0
        return ret
    }
}
