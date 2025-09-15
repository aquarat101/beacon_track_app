import UIKit
import Flutter
import CoreBluetooth
import CoreLocation

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
    var centralManager: CBCentralManager?
    var locationManager: CLLocationManager?
    
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
        let beaconChannel = FlutterMethodChannel(name: "beacon_channel", binaryMessenger: controller.binaryMessenger)
        
        beaconChannel.setMethodCallHandler({
            (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
            if call.method == "startScan" {
                self.startScan()
                result("started")
            }
        })
        
        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    func startScan() {
        centralManager = CBCentralManager(delegate: self, queue: nil)
        locationManager = CLLocationManager()
        locationManager?.delegate = self
        locationManager?.requestAlwaysAuthorization()
    }
}

extension AppDelegate: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            central.scanForPeripherals(withServices: nil, options: nil)
        }
    }
}

extension AppDelegate: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        print("Enter iBeacon region")
    }
    
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        print("Exit iBeacon region")
    }
}
