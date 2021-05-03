//
//  File.swift
//  
//
//  Created by Marcin Maciukiewicz on 22/09/2020.
//

import XCTest
@testable import MacSystemServices

final class ChargingStatusDataTests: XCTestCase {
    
    func testExample() {
        
        // prepare
        let event = ChargingSystemSource.Event(batteryChargeCurrent: 1,
                                               batteryChargeMax: 2,
                                               batteryCapacityCurrent: 3,
                                               batteryCapacityDesigned: 4)
        
        // execute
        let result = ChargingStatusData(from: event)
        
        // verify
        XCTAssertEqual(result.batteryChargeCurrent, 1)
        XCTAssertEqual(result.batteryChargeMax, 2)
        XCTAssertEqual(result.batteryCapacityCurrent, 3)
        XCTAssertEqual(result.batteryCapacityDesigned, 4)
        
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
