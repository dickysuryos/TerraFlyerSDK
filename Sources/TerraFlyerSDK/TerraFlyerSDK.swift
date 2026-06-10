import Foundation
import UIKit

/// Delegate protocol to receive deep-link routing callbacks and error logs.
public protocol TerraFlyerDelegate: AnyObject {
    /// Triggered when a deep link is successfully resolved (either direct Universal Link or Deferred Deep Link).
    func didReceiveDeepLink(_ url: URL, clickId: String?)
    
    /// Triggered if resolving a deferred link fails or returns no match.
    func didFailToResolveLink(error: Error)
}

public class TerraFlyerSDK {
    /// Singleton access instance.
    public static let shared = TerraFlyerSDK()
    
    /// Delegate receiver.
    public weak var delegate: TerraFlyerDelegate?
    
    private var backendURL: URL?
    private var activeClickId: String?
    
    private init() {}
    
    /// Configures the SDK with your self-hosted deep linking base URL.
    /// - Parameter backendURL: The base URL of your Modal/FastAPI deployment (e.g. `http://100.93.237.81:8088`).
    public func configure(backendURL: URL) {
        self.backendURL = backendURL
        print("[TerraFlyerSDK] SDK configured with backend URL: \(backendURL)")
    }
    
    /// Returns the currently active click session identifier, if attributed.
    public func getClickId() -> String? {
        return activeClickId
    }
    
    /// Handles direct Universal Links clicked when the app is already installed.
    /// Call this from `application(_:continue:restorationHandler:)` in your AppDelegate,
    /// or from SceneDelegate's `scene(_:continue:)`.
    ///
    /// - Parameter userActivity: The user activity containing the universal link webpageURL.
    /// - Returns: `true` if the URL belongs to your campaign links domain and is handled; `false` otherwise.
    @discardableResult
    public func handleUniversalLink(_ userActivity: NSUserActivity) -> Bool {
        guard let incomingURL = userActivity.webpageURL else { return false }
        print("[TerraFlyerSDK] Processing incoming Universal Link: \(incomingURL.absoluteString)")
        
        // Parse click_id if appended directly (or extract from slug if backend provides deep-link payload)
        // For standard universal links routing, we trigger callback immediately
        DispatchQueue.main.async {
            self.delegate?.didReceiveDeepLink(incomingURL, clickId: self.activeClickId)
        }
        return true
    }
    
    /// Queries the self-hosted backend to perform fuzzy IP + UserAgent fingerprint matching.
    /// Call this on app startup. It automatically prevents double-counting by storing a launch flag in `UserDefaults`.
    ///
    /// - Parameters:
    ///   - value: Optional numeric value associated with the install conversion event.
    ///   - forceCheck: Set to `true` to bypass the local launch flag and force a check (e.g. for testing).
    public func checkForDeferredLink(value: Double = 0.0, forceCheck: Bool = false) {
        let userDefaultsKey = "TerraFlyerSDK_hasTrackedInstall"
        if UserDefaults.standard.bool(forKey: userDefaultsKey) && !forceCheck {
            print("[TerraFlyerSDK] Install already tracked. Skipping deferred check.")
            return
        }
        
        guard let backendURL = self.backendURL else {
            let configError = NSError(domain: "TerraFlyerSDK", code: -1, userInfo: [NSLocalizedDescriptionKey: "SDK not configured. Call configure(backendURL:) first."])
            self.delegate?.didFailToResolveLink(error: configError)
            return
        }
        
        let url = backendURL.appendingPathComponent("api/conversion")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Fetch current device OS details and User Agent
        let userAgent = getDeviceUserAgent()
        
        // Build payload matching backend ConversionCreate schema
        let payload: [String: Any] = [
            "deviceType": "ios",
            "eventType": "install",
            "value": value,
            "userAgent": userAgent
        ]
        
        print("[TerraFlyerSDK] Querying deferred deep link attribution with fingerprint UA: \(userAgent)")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            self.delegate?.didFailToResolveLink(error: error)
            return
        }
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                print("[TerraFlyerSDK] Connection error during fingerprint check: \(error.localizedDescription)")
                self.delegate?.didFailToResolveLink(error: error)
                return
            }
            
            guard let data = data,
                  let httpResponse = response as? HTTPURLResponse else {
                let connectionError = NSError(domain: "TerraFlyerSDK", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
                self.delegate?.didFailToResolveLink(error: connectionError)
                return
            }
            
            guard httpResponse.statusCode == 200 else {
                let status = httpResponse.statusCode
                let reason = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("[TerraFlyerSDK] Attribution server returned status code: \(status). Reason: \(reason)")
                let serverError = NSError(domain: "TerraFlyerSDK", code: status, userInfo: [NSLocalizedDescriptionKey: "Attribution not found (Status \(status)): \(reason)"])
                self.delegate?.didFailToResolveLink(error: serverError)
                return
            }
            
            // Mark install as successfully tracked to prevent double-counting on next startup
            UserDefaults.standard.set(true, forKey: "TerraFlyerSDK_hasTrackedInstall")
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let clickId = json["click_id"] as? String {
                        self.activeClickId = clickId
                    }
                    
                    // Route using deep link custom scheme, or fall back to universal link URL if custom scheme is omitted
                    var resolvedURL: URL? = nil
                    if let deepLinkStr = json["deep_link"] as? String, !deepLinkStr.isEmpty, let url = URL(string: deepLinkStr) {
                        resolvedURL = url
                    } else if let universalLinkStr = json["universal_link"] as? String, !universalLinkStr.isEmpty, let url = URL(string: universalLinkStr) {
                        resolvedURL = url
                    }
                    
                    if let routingURL = resolvedURL {
                        print("[TerraFlyerSDK] Deferred link successfully attributed! Routing URL: \(routingURL.absoluteString)")
                        DispatchQueue.main.async {
                            self.delegate?.didReceiveDeepLink(routingURL, clickId: self.activeClickId)
                        }
                    } else {
                        print("[TerraFlyerSDK] Fingerprint matched, but no routing URL (deep link or universal link) configured.")
                        let error = NSError(domain: "TerraFlyerSDK", code: 204, userInfo: [NSLocalizedDescriptionKey: "No routing URL was configured for matched campaign"])
                        self.delegate?.didFailToResolveLink(error: error)
                    }
                }
            } catch {
                print("[TerraFlyerSDK] Error parsing response JSON: \(error.localizedDescription)")
                self.delegate?.didFailToResolveLink(error: error)
            }
        }
        task.resume()
    }
    
    /// Tracks post-install campaign conversion metrics (e.g. signup, purchase, subscriptions).
    /// - Parameters:
    ///   - eventType: The type of event (e.g. "signup", "purchase", "subscription").
    ///   - value: Numeric value, such as purchase price/revenue (e.g. 9.99).
    public func trackEvent(eventType: String, value: Double = 0.0) {
        guard let backendURL = self.backendURL else {
            print("[TerraFlyerSDK] Error: Cannot track event. SDK not configured.")
            return
        }
        
        guard let clickId = self.activeClickId else {
            print("[TerraFlyerSDK] Warning: Cannot track event '\(eventType)'. No active click attribution found for this session.")
            return
        }
        
        let url = backendURL.appendingPathComponent("api/events")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "clickId": clickId,
            "eventType": eventType,
            "value": value
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            print("[TerraFlyerSDK] Tracking custom event '\(eventType)' with value: \(value) for ClickID: \(clickId)")
        } catch {
            print("[TerraFlyerSDK] Error serializing event payload: \(error)")
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("[TerraFlyerSDK] Failed to dispatch event tracking: \(error.localizedDescription)")
                return
            }
            if let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 {
                print("[TerraFlyerSDK] Event '\(eventType)' tracked successfully on backend server.")
            }
        }.resume()
    }
    
    // MARK: - Private Utilities
    
    private func getDeviceUserAgent() -> String {
        let model = UIDevice.current.model // "iPhone" or "iPad"
        let sysVersion = UIDevice.current.systemVersion.replacingOccurrences(of: ".", with: "_")
        // Build standard Safari/WebKit User-Agent for iOS
        return "Mozilla/5.0 (\(model); CPU OS \(sysVersion) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"
    }
}
