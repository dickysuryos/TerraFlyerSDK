# TerraFlyerSDK iOS Integration Guide

`TerraFlyerSDK` is a lightweight Swift Package that provides direct Universal Link handling and Deferred Deep Linking via fingerprint matching for self-hosted TerraFlyer SaaS installations.

---

## 📦 Installation via SPM

To integrate `TerraFlyerSDK` locally in your iOS Xcode project:

1. Open your project in Xcode.
2. Go to **File ➜ Add Package Dependencies...**
3. Click **Add Local...** at the bottom.
4. Select the `TerraFlyerSDK` folder from your system.
5. Choose **TerraFlyerSDK** and add it to your app target.

---

## 🛠️ App Integration

### 1. Initialize the SDK in your `AppDelegate`

Import the package and configure the base API URL during startup:

```swift
import UIKit
import TerraFlyerSDK

@main
class AppDelegate: UIResponder, UIApplicationDelegate, TerraFlyerDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        // 1. Configure the SDK with your self-hosted TerraFlyer endpoint
        let backendURL = URL(string: "http://100.93.237.81:8088")!
        TerraFlyerSDK.shared.configure(backendURL: backendURL)
        
        // 2. Assign the delegate to receive resolved deep link events
        TerraFlyerSDK.shared.delegate = self
        
        // 3. Query the fingerprint attribution engine for deferred links
        TerraFlyerSDK.shared.checkForDeferredLink()
        
        return true
    }
    
    // MARK: - TerraFlyerDelegate Callbacks
    
    func didReceiveDeepLink(_ url: URL, clickId: String?) {
        print("[App] Received campaign deep link: \(url.absoluteString)")
        if let clickId = clickId {
            print("[App] Campaign click session ID: \(clickId)")
        }
        
        // Handle your custom routing logic here
        // Example: route user to specific products page
        // self.triggerDeepLink(url)
    }
    
    func didFailToResolveLink(error: Error) {
        print("[App] Deferred link attribution failed or no match found: \(error.localizedDescription)")
    }
}
```

---

### 2. Handle Direct Clicks (Universal Links)

To capture clicks when the app is **already installed** on the user's device, delegate incoming Universal Links inside `AppDelegate` or `SceneDelegate`:

#### AppDelegate:
```swift
func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
    // Let the SDK process the universal link activity
    return TerraFlyerSDK.shared.handleUniversalLink(userActivity)
}
```

#### SceneDelegate (if using Scene lifecycle):
```swift
func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    TerraFlyerSDK.shared.handleUniversalLink(userActivity)
}
```

---

### 3. Track Post-Install Activities (Purchase, Signup, etc.)

Once the app is attributed, you can track user actions (like subscriptions or purchases) directly. The SDK automatically matches these back to the original campaign click session:

```swift
// Trigger event when user successfully makes a purchase
func trackAppPurchase() {
    TerraFlyerSDK.shared.trackEvent(eventType: "purchase", value: 19.99)
}

// Trigger event when user signs up
func trackAppSignup() {
    TerraFlyerSDK.shared.trackEvent(eventType: "signup")
}
```
