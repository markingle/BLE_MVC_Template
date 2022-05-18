//
//  Corks_Model.swift
//  BLE_MVC_Template
//
//  Created by Mark Brady Ingle on 3/22/22.
//

import Foundation
import CoreBluetooth
import os

private let Cork_Service_CBUUID = CBUUID(string: "4FAFC201-1FB5-459E-8FCC-C5C9C3319141")


private let Battery_Service_CBUUID = CBUUID(string: "180F")


private let myDesiredCharacteristicId = CBUUID(string: "BEB5483E-36E1-4688-B7F6-EA07361B26C8")

// MARK: - Model class
//
internal final class corkModel {
    
    private let bleService: BLE_Controller
    private let primaryService: CBUUID
    private var bleStatus: BleStatus = .offLine
    
    init(bleService: BLE_Controller, primaryService: CBUUID = Cork_Service_CBUUID) {
        self.bleService = bleService
        self.primaryService = primaryService
        setupSubscriptions()
    }

    // MARK: - Private functions
       //
       private func setupSubscriptions() {
           // Status
           nc.addObserver(forName: .bleStatus, object: nil, queue: nil, using: { notification in
               
               if let payload = notification.object as? BleStatusPayload {
                   self.bleStatus = payload.status
                   os_log("BleService is %s", log: Log.model, type: .info, payload.status.description)
                   switch payload.status {
                       case .onLine:
                           self.bleService.attachPeripheral(suuid: self.primaryService, forceScan: false)
                            //print("System is on-live from setupSub....")
                       case .offLine:
                           break
                       case .ready:
                           break
                   }
               }
           })
       }
}
