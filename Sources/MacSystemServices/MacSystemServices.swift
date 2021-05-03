//
//  SystemServices.swift
//  BatteryNurse
//
//  Created by Marcin Maciukiewicz on 30/08/2020.
//

import Foundation

public protocol MacSystemServices {
    
    var chargingMonitorService: ChargingMonitorService { get }
    
}

public let SharedMacSystemServices: MacSystemServices = DefaultSystemServices()

fileprivate struct DefaultSystemServices {
    
    fileprivate init() {}
    
}

extension DefaultSystemServices: MacSystemServices {
    
    var chargingMonitorService: ChargingMonitorService {
        return DefaultChargingMonitorService.shared
    }
    
}
