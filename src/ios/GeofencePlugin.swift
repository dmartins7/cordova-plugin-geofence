//
//  GeofencePlugin.swift
//  ionic-geofence
//
//  Created by tomasz on 07/10/14.
//  Updated by Andre Grillo on 22/04/2020 - OutSystems Experts
//

import Foundation
import AudioToolbox
import WebKit
import CoreLocation
import UserNotifications

let center = UNUserNotificationCenter.current()

func log(_ message: String){
    NSLog(">>> GeofencePlugin - \(message)")
}

func log(_ messages: [String]) {
    for message in messages {
        log(message);
    }
}

@objc(HWPGeofencePlugin) class GeofencePlugin : CDVPlugin {
    lazy var geoNotificationManager = GeoNotificationManager()
    
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
    
    @objc(initialize:) func initialize(_ command: CDVInvokedUrlCommand) {
        log(">>> Plugin initialization <<<")
        
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        
        promptForNotificationPermission()
        
        geoNotificationManager = GeoNotificationManager()
        geoNotificationManager.registerPermissions()
        
        let (ok, warnings, errors) = geoNotificationManager.checkRequirements()
        
        log(">>> Initialization Warnings: \(warnings.count)")
        log(">>> Initialization Errors: \(errors.count)")
        
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
    
    @objc(deviceReady:) func deviceReady(_ command: CDVInvokedUrlCommand) {
        let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK)
        commandDelegate!.send(pluginResult, callbackId: command.callbackId)
    }
    
    @objc(ping:) func ping(_ command: CDVInvokedUrlCommand) {
        log("Ping")
        let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK)
        commandDelegate!.send(pluginResult, callbackId: command.callbackId)
    }
    
    @objc func promptForNotificationPermission() {
        center.requestAuthorization(options: [.alert, .badge, .sound]) { (granted, error) in
            if ((error) == nil) {
                log(">>> Authorization: \(granted)")
            } else {
                log(">>> Error: \(String(describing: error?.localizedDescription))")
            }
        }
    }
    
    @objc(addOrUpdate:) func addOrUpdate(_ command: CDVInvokedUrlCommand) {
        DispatchQueue.global(qos: .background).async {
            // do some task
            for geo in command.arguments {
                self.geoNotificationManager.addOrUpdateGeoNotification(JSON(geo))
            }
            DispatchQueue.main.async {
                let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK)
                self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
            }
        }
    }
    
    @objc(getWatched:) func getWatched(_ command: CDVInvokedUrlCommand) {
        DispatchQueue.global(qos: .background).async {
            let watched = self.geoNotificationManager.getWatchedGeoNotifications()!
            let watchedJsonString = watched.description
            DispatchQueue.main.async {
                let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: watchedJsonString)
                self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
            }
        }
    }
    
    @objc(remove:) func remove(_ command: CDVInvokedUrlCommand) {
        DispatchQueue.global(qos: .background).async {
            for id in command.arguments {
                self.geoNotificationManager.removeGeoNotification(id as! String)
            }
            DispatchQueue.main.async {
                let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK)
                self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
            }
        }
    }
    
    @objc(removeAll:) func removeAll(_ command: CDVInvokedUrlCommand) {
        DispatchQueue.global(qos: .background).async {
            self.geoNotificationManager.removeAllGeoNotifications()
            DispatchQueue.main.async {
                let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK)
                self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
            }
        }
    }
    
    @objc(didReceiveTransition:) func didReceiveTransition (_ notification: Notification) {
        log("didReceiveTransition")
        if let geoNotificationString = notification.object as? String {
            
            let js = "setTimeout('geofence.onTransitionReceived([" + geoNotificationString + "])',0)"
            
            evaluateJs(js)
        }
    }
    
    @objc(didReceiveLocalNotification:) func didReceiveLocalNotification (_ notification: Notification) {
        log("didReceiveLocalNotification")
        if UIApplication.shared.applicationState != UIApplication.State.active {
            var data = "undefined"
            if let unNotification = notification.object as? UNNotificationContent {
                if let notificationData = unNotification.userInfo["geofence.notification.data"] as? String {
                    data = notificationData
                }
                let js = "setTimeout('geofence.onNotificationClicked(" + data + ")',0)"
                log(js)
                evaluateJs(js)
            }
        }
    }
    
    func evaluateJs (_ script: String) {
        if let webView = webView {
            if let wkWebView = webView as? WKWebView {
                wkWebView.evaluateJavaScript(script, completionHandler: nil)
            } else if let uiWebView = webView as? UIWebView{
                log(">>> UIWebView is deprecated! <<<")
                uiWebView.stringByEvaluatingJavaScript(from: script)
            }
        } else {
            log("webView is nil")
        }
    }
}


class GeoNotificationManager : NSObject, CLLocationManagerDelegate {
    let locationManager = CLLocationManager()
    let store = GeoNotificationStore()
    var lastEnter: Date!
    var lastExit: Date!
    
    override init() {
        log("GeoNotificationManager init")
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }
    
    func registerPermissions() {
        locationManager.requestAlwaysAuthorization()
    }
    
    func addOrUpdateGeoNotification(_ geoNotification: JSON) {
        log("GeoNotificationManager addOrUpdate")
        
        let (_, warnings, errors) = checkRequirements()
        
        log(">>> addOrUpdateGeoNotification Requirements Warnings: \(warnings).count")
        log(">>> addOrUpdateGeoNotification Requirements Errors: \(errors).count")
        
        let location = CLLocationCoordinate2DMake(
            geoNotification["latitude"].doubleValue,
            geoNotification["longitude"].doubleValue
        )
        log("AddOrUpdate geo: \(geoNotification)")
        let radius = geoNotification["radius"].doubleValue as CLLocationDistance
        let id = geoNotification["id"].stringValue
        
        let region = CLCircularRegion(center: location, radius: radius, identifier: id)
        
        var transitionType = 0
        if let i = geoNotification["transitionType"].int {
            transitionType = i
        }
        region.notifyOnEntry = 0 != transitionType & 1
        region.notifyOnExit = 0 != transitionType & 2
        
        //store
        store.addOrUpdate(geoNotification)
        locationManager.startMonitoring(for: region)
    }
    
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
            warnings.append("Warning: Location always permissions not granted")
        }
        
        UNUserNotificationCenter.current().getNotificationSettings { (settings) in
            log(">>> Checking notification settings <<<")
            if settings.authorizationStatus == .authorized {
                // Notifications are allowed
            }
            else {
                // Either denied or notDetermined
                errors.append("Error: notification permission missing")
            }
            
            if settings.soundSetting == .disabled {
                //Sound Either denied or not Determined
                warnings.append("Warning: notification settings - sound permission missing")
            }
            
            if settings.alertSetting == .disabled {
                //Alert Either denied or not Determined
                warnings.append("Warning: notification settings - alert permission missing")
            }
            
            if settings.badgeSetting == .disabled {
                warnings.append("Warning: notification settings - badge permission missing")
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
        if let error = error {
            log("deferred fail error: \(error.localizedDescription)")
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        log("Entering region \(region.identifier)")
        
        //Preventing notification to be showed twice
        let now = NSDate() as Date
        if lastEnter == nil {
            lastEnter = now
            handleTransition(region, transitionType: 1)
        } else {
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = [.second]
            let difference = formatter.string(from: lastEnter, to: now) ?? "0"
            log(">>> Last Notification Seconds ago: " + difference)
            
            if (Int(difference) ?? 0 > 5) {
                lastEnter = now
                handleTransition(region, transitionType: 1)
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        log("Exiting region \(region.identifier)")
        
        //Preventing notification to be showed twice
        let now = NSDate() as Date
        if lastExit == nil {
            lastExit = now
            handleTransition(region, transitionType: 2)
        } else {
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = [.second]
            let difference = formatter.string(from: lastExit, to: now) ?? "0"
            log(">>> Last Notification Seconds ago: " + difference)
            
            if (Int(difference) ?? 0 > 5) {
                lastExit = now
                handleTransition(region, transitionType: 2)
            }
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
        switch state{
        case .inside:
            log("State for region " + region.identifier + " INSIDE")
            break
        case .outside:
            log("State for region " + region.identifier + " OUTSIDE")
            break
        case .unknown:
            log("State for region " + region.identifier + " UNKNOWN")
            break
        }
    }
    
    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        log("Monitoring region " + region!.identifier + " failed \(error)" )
    }
    
    func handleTransition(_ region: CLRegion!, transitionType: Int) {
        if var geoNotification = store.findById(region.identifier) {
            geoNotification["transitionType"].int = transitionType
            
            if geoNotification["notification"].isExists() {
                log(" === Calling Notification Method ===")
                notifyAbout(geoNotification)
            }
            
            NotificationCenter.default.post(name: Notification.Name(rawValue: "handleTransition"), object: geoNotification.rawString(String.Encoding.utf8.rawValue, options: []))
        }
    }
    
    func notifyAbout(_ geo: JSON) {
        log(">>> Creating notification <<<")
        //Notification Content
        let content = UNMutableNotificationContent()
        content.body = geo["notification"]["text"].stringValue
        let uuid = UUID().uuidString
        
        //Register the request
        let request = UNNotificationRequest(identifier: uuid, content: content, trigger: nil)
        center.add(request) { (error) in
            log(">>> Notification added")
            if let error = error {
                log("Error adding local notification request: \(error.localizedDescription)")
            }
        }
    }
}

class GeoNotificationStore {
    init() {
        createDBStructure()
    }
    
    func createDBStructure() {
        let (tables, err) = SD.existingTables()
        
        if let error = err {
            log("Cannot fetch sqlite tables: \(error)")
            return
        }
        
        if (tables.filter { $0 == "GeoNotifications" }.count == 0) {
            if let err = SD.executeChange("CREATE TABLE GeoNotifications (ID TEXT PRIMARY KEY, Data TEXT)") {
                //there was an error during this function, handle it here
                log("Error while creating GeoNotifications table: \(err)")
            } else {
                //no error, the table was created successfully
                log("GeoNotifications table was created successfully")
            }
        }
    }
    
    func addOrUpdate(_ geoNotification: JSON) {
        if (findById(geoNotification["id"].stringValue) != nil) {
            update(geoNotification)
        }
        else {
            add(geoNotification)
        }
    }
    
    func add(_ geoNotification: JSON) {
        let id = geoNotification["id"].stringValue
        let err = SD.executeChange("INSERT INTO GeoNotifications (Id, Data) VALUES(?, ?)",
                                   withArgs: [id as AnyObject, geoNotification.description as AnyObject])
        
        if let err = err{
            log("Error while adding \(id) GeoNotification: \(err)")
        }
    }
    
    func update(_ geoNotification: JSON) {
        let id = geoNotification["id"].stringValue
        let err = SD.executeChange("UPDATE GeoNotifications SET Data = ? WHERE Id = ?",
                                   withArgs: [geoNotification.description as AnyObject, id as AnyObject])
        
        if let err = err {
            log("Error while adding \(id) GeoNotification: \(err)")
        }
    }
    
    func findById(_ id: String) -> JSON? {
        let (resultSet, err) = SD.executeQuery("SELECT * FROM GeoNotifications WHERE Id = ?", withArgs: [id as AnyObject])
        
        if let err = err {
            //there was an error during the query, handle it here
            log("Error while fetching \(id) GeoNotification table: \(err)")
            return nil
        } else {
            if (resultSet.count > 0) {
                let jsonString = resultSet[0]["Data"]!.asString()!
                return JSON(data: jsonString.data(using: String.Encoding.utf8)!)
            }
            else {
                return nil
            }
        }
    }
    
    func getAll() -> [JSON]? {
        let (resultSet, err) = SD.executeQuery("SELECT * FROM GeoNotifications")
        
        if let err = err {
            //there was an error during the query, handle it here
            log("Error while fetching from GeoNotifications table: \(err)")
            return nil
        } else {
            var results = [JSON]()
            for row in resultSet {
                if let data = row["Data"]?.asString() {
                    results.append(JSON(data: data.data(using: String.Encoding.utf8)!))
                }
            }
            return results
        }
    }
    
    func remove(_ id: String) {
        let err = SD.executeChange("DELETE FROM GeoNotifications WHERE Id = ?", withArgs: [id as AnyObject])
        
        if let err = err {
            log("Error while removing \(id) GeoNotification: \(err)")
        }
    }
    
    func clear() {
        let err = SD.executeChange("DELETE FROM GeoNotifications")
        
        if let err = err {
            log("Error while deleting all from GeoNotifications: \(err)")
        }
    }
}
