//
//  PowerManagementService.swift
//  BatteryNurse
//
//  Created by Marcin Maciukiewicz on 30/08/2020.
//

import Foundation
import Combine
import IOKit

struct PowerManagementEvent {

    // minutes
    let avgTimeToEmpty: TimeInterval?
    // minutes
    let avgTimeToFull: TimeInterval?
    let cellVoltageArray: [Float]?
//    let chargeLevel: Int?
    let chargerConnected: Bool?
//    let charging: Int?
    let currentCapacity: Int?
    let cycleCount: Int?
    let designCapacity: Int?
    let fullyCharged: Int?
    let maxCapacity: Int?
    let temperature: Float?
    let recordedAt: Date?
    let isCharging: Bool?
    
    init(fromDict dict: Dictionary<String, Any>) {
        
        recordedAt = Date()
        
        let chargingStatus = dict["IsCharging"] as? Bool
        isCharging = chargingStatus
        currentCapacity = dict["CurrentCapacity"] as? Int
        designCapacity = dict["DesignCapacity"] as? Int
        maxCapacity = dict["MaxCapacity"] as? Int
        cycleCount = dict["CycleCount"] as? Int
        fullyCharged = dict["FullyCharged"] as? Int
        
        if let v = dict["Temperature"] as? Int {
            temperature = Float(v) / 100.0
        } else {
            temperature = nil
        }
        
        if let v = dict["CellVoltage"] as? [Int] {
            cellVoltageArray = v.map {(Float($0) / 1000.0)}
        } else {
            cellVoltageArray = nil
        }
        
        if let v = dict["AvgTimeToEmpty"] as? Int {
            if (v > 999 || chargingStatus ?? false) {
                avgTimeToEmpty = -1;
            } else {
                avgTimeToEmpty = TimeInterval(v * 60)
            }
        } else {
            avgTimeToEmpty = nil
        }
        
        if let v = dict["AvgTimeToFull"] as? Int {
            if (v > 999 || !(chargingStatus ?? true)) {
                avgTimeToFull = -1;
            } else {
                avgTimeToFull = TimeInterval(v * 60)
            }
        } else {
            avgTimeToFull = nil
        }
        
        chargerConnected = dict["ExternalConnected"] as? Bool
    }
}

enum PowerManagementError: Error {
    case serviceNotFound
    case generalProblem
}

protocol SystemServiceAccessDelegate {

/* Power management notification received */
//-(void)serviceAccess:(CSSystemServiceAccess*)serviceAccess pmNotificationDataReceived:(CSPowerManagementEvent*)data;

/* System Power notification received */
//-(void)serviceAccess:(CSSystemServiceAccess*)serviceAccess spNotificationDataReceived:(NSDictionary*)data;

}

var gNotifyPort: IONotificationPortRef? = nil
var systemPowerNotifyPort: IONotificationPortRef? = nil
var gRunLoop: CFRunLoop? = nil

// a reference to IOPMPowerSource notification subscription
// release to loose notifications
var ioPMPowerSourceNotification: io_object_t? = nil
var ioSystemPowerNotification: io_object_t? = nil
var ioSystemPowerSession: io_connect_t? = nil

protocol EventConsumer {
    
    func trigger(_ output: PowerManagementEvent)
    
    func fail(_ error: PowerManagementError)
}

class PowerManagementService: ConnectablePublisher {

    typealias Output = PowerManagementEvent
    typealias Failure = PowerManagementError
    
    private var subscriptions = Array<Any>()

    final class PowerManagementSubscription<S: Subscriber> : Subscription, EventConsumer where S.Input == Output, S.Failure == Failure {
        
        private var subscriber: S?
        
        init(subscriber: S) {
            self.subscriber = subscriber
        }
        
        func trigger(_ output: Output) {
            let _ = /*let demand: Subscribers.Demand? =*/ subscriber?.receive(output)
        }

        func fail(_ error: PowerManagementError) {
            subscriber?.receive(completion: Subscribers.Completion<PowerManagementError>.failure(error))
        }

        func request(_ demand: Subscribers.Demand) {
            
        }
        
        func cancel() {
            
        }
        
    }
    
    func connect() -> Cancellable {
        
       return self
    }

    func receive<S>(subscriber: S) where S : Subscriber, S.Failure == Failure , S.Input == Output {
        let subscription: PowerManagementSubscription = PowerManagementSubscription(subscriber: subscriber)
        subscriptions.append(subscription)
        subscriber.receive(subscription: subscription)
    }

    // -
    let kIO_PowerManagement_PowerSourceService = "IOPMPowerSource"
    func locateSystemService(serviceName: String) throws -> io_registry_entry_t  {
        let result: io_registry_entry_t = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching(serviceName))
        guard (result != 0) else {
            throw PowerManagementError.serviceNotFound
        }
        return result
    }
    
    func locateServiceAndReadPowerManagementData() throws -> PowerManagementEvent {
    
        let result: PowerManagementEvent
    
        let service: io_registry_entry_t = try locateSystemService(serviceName: kIO_PowerManagement_PowerSourceService)
            
        defer {
            IOObjectRelease(service)
        }
        
        let mutableDict:NSMutableDictionary = NSMutableDictionary()
        var unmanagedMutableDict: Unmanaged<CFMutableDictionary>? = Unmanaged.passUnretained(mutableDict)
        readPowerManagementData(service: service, data: &unmanagedMutableDict);
        
        guard let values = unmanagedMutableDict else { throw PowerManagementError.generalProblem }
        
        let dict = values.takeRetainedValue() as NSDictionary
        result = PowerManagementEvent(fromDict: dict.swiftDictionary)
        
        return result
    }
    
    /*
       Read data from provided IOPMPowerSource service
     */
    func readPowerManagementData(service: io_registry_entry_t, data: inout Unmanaged<CFMutableDictionary>?)
    {
        // http://stackoverflow.com/questions/3290395/how-to-get-the-battery-charge-level-specifically-in-mwh-not-percentage-for-mac
        // also:
        // http://developer.apple.com/library/mac/#documentation/Darwin/Reference/IOKit/index.html
        // http://blog.coriolis.ch/2009/02/14/reading-the-battery-level-programmatically/

        IORegistryEntryCreateCFProperties(service, &data, nil, 0);
    }
    
    struct SystemServiceAccess {
        let isRegistered: Bool
        let delegate: SystemServiceAccessDelegate
        let usesMockBattery: Bool
    }
    
    struct MyPrivateData {
        let notification: io_object_t? = nil
        let callback: SystemServiceAccess
    }
    
    var bag = Array<AnyCancellable>()
    var systemNotificationsCancellable: Cancellable?
    var systemNotificationsPublisher: Timer.TimerPublisher?
    
    func registerForNotifications() throws {
        
        // workaround implementation
        let snp = Timer.TimerPublisher(interval: 1.0, runLoop: RunLoop.main, mode: RunLoop.Mode.default)
        systemNotificationsPublisher = snp
        
        systemNotificationsCancellable = snp.connect()
        snp.sink { [weak self] _ in
            guard let strongSelf = self else { return }
            do {
                let event = try strongSelf.locateServiceAndReadPowerManagementData()
                strongSelf
                    .subscriptions
                    .compactMap { $0 as? EventConsumer }
                    .forEach{ $0.trigger(event) }
            } catch {
                
                let error = PowerManagementError.generalProblem
                
                strongSelf
                    .subscriptions
                    .compactMap { $0 as? EventConsumer }
                    .forEach{ $0.fail(error) }
            }
        }.store(in: &bag)
    }
    
//    func registerForNotifications() throws {
//        let pmService: io_registry_entry_t = try locateSystemService(serviceName: kIO_PowerManagement_PowerSourceService)
//
//        defer {
//            IOObjectRelease(pmService)
//        }
//
//        // Create a notification port and add its run loop event source to our run loop
//        // This is how async notifications get set up.
//        gNotifyPort = IONotificationPortCreate(kIOMasterPortDefault)
//        let runLoopSource: CFRunLoopSource = IONotificationPortGetRunLoopSource(gNotifyPort).takeRetainedValue()
//        gRunLoop = CFRunLoopGetCurrent()
//        CFRunLoopAddSource(gRunLoop, runLoopSource, CFRunLoopMode.defaultMode)
//
//        let s = SystemServiceAccess(isRegistered: true,
//                                      delegate: self,
//                                      usesMockBattery: true)
//
//        var privateData = MyPrivateData(callback: s)
////        var privateDataRef: UnsafeMutablePointer<MyPrivateData> = privateData
////        var privateDataRef: UnsafeMutablePointer<MyPrivateData>? = nil //
////        privateDataRef = UnsafeMutablePointer.allocate(capacity:MemoryLayout<MyPrivateData>.size)
////        bzero( privateDataRef, MemoryLayout<MyPrivateData>.size)
////        privateDataRef->callback = self
//
//        let callback: IOServiceInterestCallback = {(refCon: UnsafeMutableRawPointer?,
//                                                    service: io_service_t,
//                                                    messageType: natural_t,
//                                                    messageArgument: UnsafeMutableRawPointer?) in
//            powerManagementNotification(refCon: refCon, service: service, messageType: messageType, messageArgument: messageArgument)
//        }
//        /*kr = */ IOServiceAddInterestNotification(gNotifyPort,          // notifyPort
//                                                   pmService,         // service
//                                                   kIOGeneralInterest, // interestType
//                                                   callback, // callback
//                                                   &privateData,  // refCon
//                                                   &(ioPMPowerSourceNotification!)   // notification
//                                                   )
//
//        IOObjectRelease(pmService)
//
////        let callback: IOServiceInterestCallback = {
////            SystemPowerNotification(refCon: <#T##UnsafeMutableRawPointer?#>, service: <#T##io_service_t#>, messageType: <#T##natural_t#>, messageArgument: <#T##UnsafeMutableRawPointer?#>)
////        }
//        ioSystemPowerSession = IORegisterForSystemPower(refcon: &privateData, thePortRef: thePortRef, callback: callback, notifier: notifier);
////        ioSystemPowerSession = IORegisterForSystemPower( &privateData, &systemPowerNotifyPort, SystemPowerNotification, &(ioSystemPowerNotification) );
//        if (ioSystemPowerSession! == MACH_PORT_NULL)
//        {
//            NSLog("A problem");
//        }
//    }
}

extension PowerManagementService: SystemServiceAccessDelegate {
    

//void SystemPowerNotification(void *refCon, io_service_t service, natural_t messageType, void *messageArgument)
    func SystemPowerNotification(refCon: UnsafeMutableRawPointer?, service: io_service_t, messageType: natural_t, messageArgument: UnsafeMutableRawPointer?) {
//{
//    MyPrivateData   *privateDataRef = (MyPrivateData *)refCon;
//    //    - kIOMessageSystemWillSleep is delivered at the point the system is initiating a
//    //    non-abortable sleep.
//    //    Callers MUST acknowledge this event by calling @link IOAllowPowerChange @/link.
//    //    If a caller does not acknowledge the sleep notification, the sleep will continue anyway after
//    //    a 30 second timeout (resulting in bad user experience).
//    //    Delivered before any hardware is powered off.
//
//    //    - kIOMessageSystemWillPowerOn is delivered at early wakeup time, before most hardware has been
//    //    powered on. Be aware that any attempts to access disk, network, the display, etc. may result
//    //    in errors or blocking your process until those resources become avaiable.
//    //    Caller must NOT acknowledge kIOMessageSystemWillPowerOn; the caller must simply return from its handler.
//
//    //    - kIOMessageSystemHasPoweredOn is delivered at wakeup completion time, after all device drivers and
//    //    hardware have handled the wakeup event. Expect this event 1-5 or more seconds after initiating
//    //    system awkeup.
//    //    Caller must NOT acknowledge kIOMessageSystemHasPoweredOn; the caller must simply return from its handler.
//
//    //    - kIOMessageCanSystemSleep indicates the system is pondering an idle sleep, but gives apps the
//    //    chance to veto that sleep attempt.
//    //    Caller must acknowledge kIOMessageCanSystemSleep by calling @link IOAllowPowerChange @/link
//    //    or @link IOCancelPowerChange @/link. Calling IOAllowPowerChange will not veto the sleep; any
//    //    app that calls IOCancelPowerChange will veto the idle sleep. A kIOMessageCanSystemSleep
//    //    notification will be followed up to 30 seconds later by a kIOMessageSystemWillSleep message.
//    //    or a kIOMessageSystemWillNotPowerOn message.
//
//    //    - kIOMessageSystemWillNotPowerOn is delivered when some app client has voted an idle sleep
//    //    request. kIOMessageSystemWillNotPowerOn may follow a kIOMessageCanSystemSleep notification,
//    //    but will not otherwise be sent.
//    //    Caller must NOT acknowledge kIOMessageSystemWiillNotPowerOn; the caller must simply return from its handler.
//
//    [privateDataRef->callback systemPowerNotificationDataReceived:nil];
}

//void PMNotification(void *refCon, io_service_t service, natural_t messageType, void *messageArgument)
//    func powerManagementNotification(refCon: UnsafeMutableRawPointer?, service: io_service_t, messageType: natural_t, messageArgument: UnsafeMutableRawPointer?) {
//{
//    MyPrivateData   *privateDataRef = (MyPrivateData *)refCon;
//    //    free(privateDataRef);
//
//    // http://www.apple.com/batteries/notebooks.html
//    // http://www.apple.com/batteries/
//
//    CFMutableDictionaryRef pRef = NULL;
//    CSReadPowerManagementData2(service, &pRef);
//    NSMutableDictionary *properties = (NSMutableDictionary *)pRef;
//
//    [privateDataRef->callback powerManagementNotificationDataReceived:properties];
//
//    CFRelease(pRef);
//    pRef = NULL;
//
}

extension PowerManagementService: Cancellable {
    
    func cancel() {}
    
}

extension NSDictionary {
    var swiftDictionary: Dictionary<String, Any> {
        var swiftDictionary = Dictionary<String, Any>()

        for key : Any in self.allKeys {
            let stringKey = key as! String
            if let keyValue = self.value(forKey: stringKey){
                swiftDictionary[stringKey] = keyValue
            }
        }

        return swiftDictionary
    }
}
