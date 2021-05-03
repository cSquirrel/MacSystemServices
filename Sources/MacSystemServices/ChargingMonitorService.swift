//
//  ChargingMonitorService.swift
//  BatteryNurse
//
//  Created by Marcin Maciukiewicz on 28/08/2020.
//

import Foundation
import Combine

public class ChargingStatusData: ObservableObject {
    
    public static let zero = ChargingStatusData(batteryChargeCurrent: 0,
                                                batteryChargeMax: 0,
                                                batteryCapacityCurrent: 0,
                                                batteryCapacityDesigned: 0,
                                                recordedAt: Date.distantPast,
                                                isCharging: false)
    
    @Published public var recordedAt: Date
    @Published public var batteryChargeCurrent: Float
    @Published public var batteryChargeMax: Float
    @Published public var batteryCapacityCurrent: Float
    @Published public var batteryCapacityDesigned: Float
    @Published public var isCharging: Bool
    
    public init(
        batteryChargeCurrent: Float,
        batteryChargeMax: Float,
        batteryCapacityCurrent: Float,
        batteryCapacityDesigned: Float,
        recordedAt: Date = Date(),
        isCharging: Bool) {
        
        self.batteryChargeCurrent = batteryChargeCurrent
        self.batteryChargeMax = batteryChargeMax
        self.batteryCapacityCurrent = batteryCapacityCurrent
        self.batteryCapacityDesigned = batteryCapacityDesigned
        self.recordedAt = recordedAt
        self.isCharging = isCharging
    }
    
    convenience init(from event: ChargingSystemSource.Event) {
            
        self.init(batteryChargeCurrent: Float(event.batteryChargeCurrent),
                 batteryChargeMax: Float(event.batteryChargeMax),
                 batteryCapacityCurrent: Float(event.batteryCapacityCurrent),
                 batteryCapacityDesigned: Float(event.batteryCapacityDesigned),
                 isCharging: event.isCharging)
    }
}

struct ChargingSystemSource {

    struct Event {

        let batteryChargeCurrent: Int
        let batteryChargeMax: Int
        let batteryCapacityCurrent: Int
        let batteryCapacityDesigned: Int
        let isCharging: Bool

    }

}


public protocol ChargingMonitorService {
    
    var chargingData: AnyPublisher<ChargingStatusData, Never> { get }
    
}

public class DefaultChargingMonitorService: ChargingMonitorService {
    
    public static let shared = DefaultChargingMonitorService()
    
    public var chargingData: AnyPublisher<ChargingStatusData, Never>
    
    private var chargingDataSubject: PassthroughSubject<ChargingStatusData, Never>
    
    private var timer: Timer.TimerPublisher!
    private var bag = Array<AnyCancellable>()
    private let powerManagement: PowerManagementService
 
    private init () {
        
        chargingDataSubject = PassthroughSubject<ChargingStatusData, Never>()
        chargingData = chargingDataSubject.eraseToAnyPublisher()
        
        powerManagement = PowerManagementService()
        
        _ = powerManagement
            .connect()
        
        powerManagement
            .map { (evt: PowerManagementEvent) -> ChargingSystemSource.Event in
                let result: ChargingSystemSource.Event = ChargingSystemSource.Event(batteryChargeCurrent: evt.currentCapacity ?? 0,
                                                        batteryChargeMax: evt.maxCapacity ?? 0,
                                                        batteryCapacityCurrent: evt.maxCapacity ?? 0,
                                                        batteryCapacityDesigned: evt.designCapacity ?? 0,
                                                        isCharging: evt.chargerConnected ?? false)
                return result
            }
            .map{ ChargingStatusData(from: $0) }
            .sink(receiveCompletion: { (completion: Subscribers.Completion<PowerManagementService.Failure>) in

            }, receiveValue: { self.chargingDataSubject.send($0)})
            .store(in: &bag)
        
        try? powerManagement.registerForNotifications()
    }
    
}
