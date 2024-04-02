//
//  GeofencePlugin.swift
//  ionic-geofence
//
//  Created by tomasz on 07/10/14.
//
//

import Foundation
import AudioToolbox
import WebKit
import RealmSwift
import CoreLocation

let TAG = "GeofencePlugin"
let iOS8 = floor(NSFoundationVersionNumber) > floor(NSFoundationVersionNumber_iOS_7_1)
let iOS7 = floor(NSFoundationVersionNumber) <= floor(NSFoundationVersionNumber_iOS_7_1)

func log(_ message: String){
    NSLog("%@ - %@", TAG, message)
}

func log(_ messages: [String]) {
    for message in messages {
        log(message);
    }
}

@available(iOS 8.0, *)
@objc(HWPGeofencePlugin)
class GeofencePlugin : CDVPlugin {
    
    var geoNotificationManager = GeoNotificationManager()
    let priority = DispatchQueue.GlobalQueuePriority.default
    var callbackId : String?
    
    override func pluginInitialize () {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(GeofencePlugin.didReceiveLocalNotification(_:)),
            name: NSNotification.Name(rawValue: "CDVLocalNotification"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(GeofencePlugin.didReceiveTransition(_:)),
            name: NSNotification.Name(rawValue: "handleTransition"),
            object: nil
        )
    }
    
    @objc
    func handleNotificationReceived(_ notification: Notification) {
        guard let notiicationBody = notification.object as? String else { return }
        
        let result: CDVPluginResult
        result = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: notiicationBody)
        result.setKeepCallbackAs(true)
        commandDelegate!.send(result, callbackId: callbackId)
    }
    
    @objc
    func didReceiveGeofenceSetCallback(_ command: CDVInvokedUrlCommand) {
        // remove observer if already exist
        NotificationCenter.default.removeObserver(self, name: .sendForegroundOSNotification, object: nil)
        
        // Add new observe to handleNotificationReceived (use to notification app when is closed, foreground)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(GeofencePlugin.handleNotificationReceived(_:)),
            name: .sendForegroundOSNotification,
            object: nil
        )
        
        callbackId = command.callbackId
        let result: CDVPluginResult
        result = CDVPluginResult(status: CDVCommandStatus_OK)
        commandDelegate!.send(result, callbackId: command.callbackId)
    }
    
    
    @objc(requestPushNotificationPermission:)
    func requestPushNotificationPermission(command: CDVInvokedUrlCommand) {
        geoNotificationManager.registerPermissions()
        
        // Requestion notifications, alert, sound, if necessary
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            var pluginResult: CDVPluginResult
            if let error = error {
                pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: error.localizedDescription)
            } else {
                if granted {
                    DispatchQueue.main.async {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                    pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: true)
                } else {
                    pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: false)
                }
            }
            self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
        }
    }
    
    @objc(checkPushNotificationPermission:)
    func checkPushNotificationPermission(command: CDVInvokedUrlCommand) {
        var pluginResult: CDVPluginResult

        switch CLLocationManager.authorizationStatus() {
        case .authorizedWhenInUse, .authorizedAlways:
            pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: true)
        case .denied, .restricted, .notDetermined:
            pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: false)
        @unknown default:
            pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Unknown authorization status")
        }
        
        self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
    }
    
    @objc
    func requestPermissions(_ command: CDVInvokedUrlCommand) {
        log("Plugin requestPermissions")
        
        if iOS8 {
            promptForNotificationPermission()
        }
        
        geoNotificationManager = GeoNotificationManager()
        geoNotificationManager.registerPermissions()
        
        let (ok, warnings, errors) = geoNotificationManager.checkRequirements()
        
        log(warnings)
        log(errors)
        
        let result: CDVPluginResult
        
        if ok {
            result = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: warnings.joined(separator: "\n"))
        } else {
            result = CDVPluginResult(
                status: CDVCommandStatus_ILLEGAL_ACCESS_EXCEPTION,
                messageAs: (errors + warnings).joined(separator: "\n")
            )
        }
        
        commandDelegate!.send(result, callbackId: command.callbackId)
    }
    
    @objc
    func deviceReady(_ command: CDVInvokedUrlCommand) {
        let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK)
        commandDelegate!.send(pluginResult, callbackId: command.callbackId)
    }
    
    @objc
    func ping(_ command: CDVInvokedUrlCommand) {
        log("Ping")
        let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK)
        commandDelegate!.send(pluginResult, callbackId: command.callbackId)
    }
    
    func promptForNotificationPermission() {
        UIApplication.shared.registerUserNotificationSettings(UIUserNotificationSettings(
            types: [UIUserNotificationType.sound, UIUserNotificationType.alert, UIUserNotificationType.badge],
            categories: nil
        )
        )
    }
    
    @objc
    func addOrUpdate(_ command: CDVInvokedUrlCommand) {
        for geo in command.arguments {
            self.geoNotificationManager.addOrUpdateGeoNotification(JSON(geo))
        }
        DispatchQueue.main.async {
            let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK)
            self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
        }
    }
    
    @objc
    func getWatched(_ command: CDVInvokedUrlCommand) {
        let watched = self.geoNotificationManager.getWatchedGeoNotifications()!
        let watchedJsonString = watched.description
        DispatchQueue.main.async {
            let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: watchedJsonString)
            self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
        }
    }
    
    @objc
    func remove(_ command: CDVInvokedUrlCommand) {
        for id in command.arguments {
            self.geoNotificationManager.removeGeoNotification(id as! String)
        }
        DispatchQueue.main.async {
            let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK)
            self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
        }    }
    
    @objc
    func removeAll(_ command: CDVInvokedUrlCommand) {
        self.geoNotificationManager.removeAllGeoNotifications()
        DispatchQueue.main.async {
            let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK)
            self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
        }
    }
    
    @objc
    func didReceiveTransition (_ notification: Notification) {
        log("didReceiveTransition")
        if let geoNotificationString = notification.object as? String {
            
            let js = "setTimeout('geofence.onTransitionReceived([" + geoNotificationString + "])',0)"
            
            evaluateJs(js)
        }
    }
    
    @objc
    func didReceiveLocalNotification (_ notification: Notification) {
        log("didReceiveLocalNotification")
        if UIApplication.shared.applicationState != UIApplication.State.active {
            var data = "undefined"
            if let uiNotification = notification.object as? UILocalNotification {
                if let notificationData = uiNotification.userInfo?["geofence.notification.data"] as? String {
                    data = notificationData
                }
                let js = "setTimeout('geofence.onNotificationClicked(" + data + ")',0)"
                
                evaluateJs(js)
            }
        }
    }
    
    func evaluateJs (_ script: String) {
        if let webView = webView {
            if let uiWebView = webView as? UIWebView {
                uiWebView.stringByEvaluatingJavaScript(from: script)
            } else if let wkWebView = webView as? WKWebView {
                wkWebView.evaluateJavaScript(script, completionHandler: nil)
            }
        } else {
            log("webView is nil")
        }
    }
}

@available(iOS 8.0, *)
class GeoNotificationManager : NSObject, CLLocationManagerDelegate {
    let locationManager = CLLocationManager()
    var store = GeoNotificationStore()
    
    override init() {
        log("GeoNotificationManager init")
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }
    
    func registerPermissions() {
        if #available(iOS 14, *) {
            let status = locationManager.authorizationStatus
            switch status {
            case .notDetermined:
                locationManager.requestWhenInUseAuthorization()
            case .authorizedWhenInUse:
                locationManager.requestAlwaysAuthorization()
            default:
                break
            }
        } else {
            let status = CLLocationManager.authorizationStatus()
            switch status {
            case .notDetermined:
                locationManager.requestWhenInUseAuthorization()
            case .authorizedWhenInUse:
                locationManager.requestAlwaysAuthorization()
            default:
                break
            }
        }
    }
    
    func addOrUpdateGeoNotification(_ geoNotificationJSON: JSON) {
        log("GeoNotificationManager addOrUpdate")
        
        let (_, warnings, errors) = checkRequirements()
        
        log(warnings)
        log(errors)
        
        let location = CLLocationCoordinate2DMake(
            geoNotificationJSON["latitude"].doubleValue,
            geoNotificationJSON["longitude"].doubleValue
        )
        log("AddOrUpdate geo: \(geoNotificationJSON)")
        let radius = geoNotificationJSON["radius"].doubleValue as CLLocationDistance
        let id = geoNotificationJSON["id"].stringValue
        
        let region = CLCircularRegion(center: location, radius: radius, identifier: id)
        
        var transitionType = 0
        if let i = geoNotificationJSON["transitionType"].int {
            transitionType = i
        }
        region.notifyOnEntry = 0 != transitionType & 1
        region.notifyOnExit = 0 != transitionType & 2
        
        //store
        store.addOrUpdate(geoNotificationJSON)
        locationManager.startMonitoring(for: region)
    }
    
    // TODO Make notification settings synchronous
    func checkRequirements() -> (Bool, [String], [String]) {
        var errors = [String]()
        var warnings = [String]()
        
        if (!CLLocationManager.isMonitoringAvailable(for: CLRegion.self)) {
            errors.append("Geofencing not available")
        }
        
        if (!CLLocationManager.locationServicesEnabled()) {
            errors.append("Error: Locationservices not enabled")
        }
        
        let authStatus = CLLocationManager.authorizationStatus()
        
        if (authStatus != CLAuthorizationStatus.authorizedAlways) {
            errors.append("Warning: Location always permissions not granted")
        }
        
        if (iOS8) {
            DispatchQueue.main.async { // Due to async, the return of checkRequirements is not ok
                if let notificationSettings = UIApplication.shared.currentUserNotificationSettings {
                    if notificationSettings.types == UIUserNotificationType() {
                        errors.append("Error: notification permission missing")
                    } else {
                        if !notificationSettings.types.contains(.sound) {
                            warnings.append("Warning: notification settings - sound permission missing")
                        }
                        
                        if !notificationSettings.types.contains(.alert) {
                            warnings.append("Warning: notification settings - alert permission missing")
                        }
                        
                        if !notificationSettings.types.contains(.badge) {
                            warnings.append("Warning: notification settings - badge permission missing")
                        }
                    }
                } else {
                    errors.append("Error: notification permission missing")
                }
            }
        }
        
        let ok = (errors.count == 0)
        
        return (ok, warnings, errors)
    }
    
    func getWatchedGeoNotifications() -> [JSON]? {
        return store.getAll()
    }
    
    func getMonitoredRegion(_ id: String) -> CLRegion? {
        for object in locationManager.monitoredRegions {
            let region = object
            
            if (region.identifier == id) {
                return region
            }
        }
        return nil
    }
    
    func removeGeoNotification(_ id: String) {
        store.remove(id)
        let region = getMonitoredRegion(id)
        if (region != nil) {
            log("Stoping monitoring region \(id)")
            locationManager.stopMonitoring(for: region!)
        }
    }
    
    func removeAllGeoNotifications() {
        store.clear()
        for object in locationManager.monitoredRegions {
            let region = object
            log("Stoping monitoring region \(region.identifier)")
            locationManager.stopMonitoring(for: region)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        log("update location")
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        log("fail with error: \(error)")
    }
    
    func locationManager(_ manager: CLLocationManager, didFinishDeferredUpdatesWithError error: Error?) {
        log("deferred fail error: \(String(describing: error))")
    }
    
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        log("Entering region \(region.identifier)")
        handleTransition(region, transitionType: 1)
    }
    
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        log("Exiting region \(region.identifier)")
        handleTransition(region, transitionType: 2)
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if status == .authorizedWhenInUse {
            log("---  Permission requestAlwaysAuthorization granted ---- ")
            locationManager.requestAlwaysAuthorization()
        } else if status == .authorizedAlways {
            log("---  Permission authorizedAlways granted ---- ")
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
        if region is CLCircularRegion {
            let lat = (region as! CLCircularRegion).center.latitude
            let lng = (region as! CLCircularRegion).center.longitude
            let radius = (region as! CLCircularRegion).radius
            
            log("Starting monitoring for region \(region) lat \(lat) lng \(lng) of radius \(radius)")
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        log("--- 📦 --- State for region " + region.identifier)
    }
    
    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        log("Monitoring region " + region!.identifier + " failed \(error)" )
    }
    
    func handleTransition(_ region: CLRegion!, transitionType: Int) {
        if var geoNotification = store.findById(region.identifier) {
            geoNotification["transitionType"].int = transitionType
            
            if geoNotification["notification"].isExists() {
                notifyAbout(geoNotification)
            }
            
            if geoNotification["url"].isExists() {
                log("Should post to " + geoNotification["url"].stringValue)
                let url = URL(string: geoNotification["url"].stringValue)!
                
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
                dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
                //formatter.locale = Locale(identifier: "en_US")
                
                let jsonDict = ["geofenceId": geoNotification["id"].stringValue, "transition": geoNotification["transitionType"].intValue == 1 ? "ENTER" : "EXIT", "date": dateFormatter.string(from: Date())]
                let jsonData = try! JSONSerialization.data(withJSONObject: jsonDict, options: [])
                
                var request = URLRequest(url: url)
                request.httpMethod = "post"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue(geoNotification["authorization"].stringValue, forHTTPHeaderField: "Authorization")
                request.httpBody = jsonData
                
                let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
                    if let error = error {
                        print("error:", error)
                        return
                    }
                    
                    do {
                        guard let data = data else { return }
                        guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: AnyObject] else { return }
                        print("json:", json)
                    } catch {
                        print("error:", error)
                    }
                }
                
                task.resume()
            }
            
            NotificationCenter.default.post(name: Notification.Name(rawValue: "handleTransition"), object: geoNotification.rawString(String.Encoding.utf8.rawValue, options: []))
        }
    }
    
    func notifyAbout(_ geo: JSON) {
        log("Creating notification")
        let notification = UILocalNotification()
        notification.timeZone = TimeZone.current
        let dateTime = Date()
        notification.fireDate = dateTime
        notification.soundName = UILocalNotificationDefaultSoundName
        notification.alertBody = geo["notification"]["text"].stringValue
        
        let notificationForegroundBody = geo["notification"]["text"].stringValue
        NotificationCenter.default.post(name: Notification.Name(rawValue: "sendForegroundOSNotification"), object: notificationForegroundBody)
        
        if let json = geo["notification"]["data"] as JSON? {
            notification.userInfo = ["geofence.notification.data": json.rawString(String.Encoding.utf8.rawValue, options: [])!]
        }
        UIApplication.shared.scheduleLocalNotification(notification)
        
        if let vibrate = geo["notification"]["vibrate"].array {
            if (!vibrate.isEmpty && vibrate[0].intValue > 0) {
                AudioServicesPlayAlertSound(SystemSoundID(kSystemSoundID_Vibrate))
            }
        }
    }
}

class GeoNotification: Object {
    @objc dynamic var id: String = ""
    @objc dynamic var data: String = ""
    
    override static func primaryKey() -> String? {
        return "id"
    }
}

class GeoNotificationStore {
    
    let realm = try! Realm()
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func addOrUpdate(_ geoNotificationJSON: JSON) {
        try! self.realm.write {
            let geoNotification = GeoNotification()
            geoNotification.id = geoNotificationJSON["id"].stringValue
            geoNotification.data = geoNotificationJSON.description
            self.realm.add(geoNotification, update: .modified)
        }
    }
    
    func findById(_ id: String) -> JSON? {
        guard let geoNotification = realm.object(ofType: GeoNotification.self, forPrimaryKey: id) else { return nil }
        if let data = geoNotification.data.data(using: .utf8) {
            return JSON(data: data)
        }
        return nil
    }
    
    func getAll() -> [JSON]? {
        let geoNotifications = self.realm.objects(GeoNotification.self)
        return geoNotifications.map { JSON(data: $0.data.data(using: .utf8)!) }
    }
    
    func remove(_ id: String) {
        guard let geoNotification = self.realm.object(ofType: GeoNotification.self, forPrimaryKey: id) else { return }
        try! self.realm.write {
            self.realm.delete(geoNotification)
        }
    }
    
    func clear() {
        try! self.realm.write {
            self.realm.delete(self.realm.objects(GeoNotification.self))
        }
    }
}

extension Notification.Name {
    static let sendForegroundOSNotification = Notification.Name("sendForegroundOSNotification")
}
