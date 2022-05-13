//
//  BLE_Controller.swift
//  BLE_MVC_Template
//
//  Created by Mark Brady Ingle on 3/19/22.
//

import Foundation
import CoreBluetooth
import os

private let Cork_Service_CBUUID = CBUUID(string: "4FAFC201-1FB5-459E-8FCC-C5C9C3319141")

private let Peripheral1_UUID = UUID(uuidString: "4FAFC201-1FB5-459E-8FCC-C5C9C3319141")
private let Peripheral2_UUID = UUID(uuidString: "4FAFC201-1FB5-459E-8FCC-C5C9C3319141")

internal let nc = NotificationCenter.default        // Application scope

private let subsystem = Bundle.main.bundleIdentifier ?? "Unamed"

struct Log {
    static let ble = OSLog(subsystem: subsystem, category: "bluetooth")
    static let model = OSLog(subsystem: subsystem, category: "model")
    static let ui = OSLog(subsystem: subsystem, category: "ui")
}

// MARK: - Publication topics
//
public extension Notification.Name {
    static let bleStatus = Notification.Name("bleStatus")
}

//
// Statuses
//
internal enum BleStatus: CustomStringConvertible {
    case onLine
    case offLine
    case ready
    
    var description: String {
        switch self {
        case .offLine: return "off-line"
        case .onLine: return "on-line"
        case .ready: return "ready"
        }
    }
}

//
// Notification Payloads
//
internal struct BleStatusPayload {
    var status: BleStatus
}

// Error management
//
internal enum BleError: Error {
    case UninitialisedProperty

    var description: String {
        switch self {
        case .UninitialisedProperty: return "Required property is nil"
        }
    }
}



let restoreIdKey = "MyBluetoothManager"


    
// MARK: - Core Bluetooth service IDs

class BLE_Controller: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate{
    
    static let shared = BLE_Controller()
    
    private let initOptions = [CBCentralManagerScanOptionAllowDuplicatesKey : NSNumber(value: false)]
    
    private let peripheralIdDefaultsKey = "MyBluetoothManagerPeripheralId"
    
    // Last attached peripheral
    //private struct LastAttachedPeripheral: Codable {
    //    var peripheral: UUID
    //    var suuidData: Data
    //}
    
    // Last attached peripheral
        private struct LastAttachedPeripheral: Codable {
            var peripherals: UUID
        }
    
    //private var peripheralArray : [LastAttachedPeripheral] = []
    
    private var peripheralArray : Array<LastAttachedPeripheral> = Array()
    
    private let kLastAttachedPeripheralKey = "lap"
    private var UD: UserDefaults
    
    private var centralManager: CBCentralManager?
    
    var connectedPeripheral: CBPeripheral?
    var discoveredPeripheral: CBPeripheral?
    var WHITE: CBPeripheral?
    var peripherals: [CBPeripheral] = []
    
    // Queues
    private let cmdQueue = DispatchQueue(label: "com.iotcourse.cmdq", qos: .userInitiated)
    
    
    // State machine
    private var machine: Machine? = nil
    
    // State maps
    // TODO: state action map init - is an entry per state really needed? Can poss. init with [:]??
    private var stateActionMap: StateActionMap = Dictionary.init(uniqueKeysWithValues: BState.allCases.map { ($0, (nil, nil))})
    private var actionMap: ActionMap = Dictionary.init(uniqueKeysWithValues: BState.allCases.map { ($0, [:])})
    private var errorMap: ErrorMap = Dictionary.init(uniqueKeysWithValues: BState.allCases.map { ($0, (nil, .Start))})
    //private var discoveredPeripheral: CBPeripheral?
    private var attachingWith: (peripheral: CBPeripheral?, suuid: CBUUID?, isAttached: Bool) = (nil, nil, false)
    
    private var PeripheralCount = 0
    
    init(defaults: UserDefaults = UserDefaults.standard) {
        self.UD = defaults
        super.init()
        setupStateMaps()
        machine = Machine.init(actionMap: actionMap, stateActionMap: stateActionMap, errorMap: errorMap)
        //Apple recommends checking to retrieve peripherals that may already exist....then falling back to scanning if retrieve fails
        // - Retrieve process will query the bluetooth cache.  Mainly to see if the core bluetooth is already aware of the peripheral
        // - The UUID for the peripheral is passed to core bluetooth and core bluetooth syncronously returns a CBPeripheral instance or NIL.  If core bluetooth already knows about the peri then we can attempt to connect to it.
        // - The peripheral may or may not be powered up so we need to connect to it to find out
        // - Successful connect. then we go to that attached state and start work......if it fails we need to fall back to a scan
        //centralManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionRestoreIdentifierKey: restoreIdKey,])
        //centralManager = CBCentralManager(delegate: self, queue: nil, options: nil)
        centralManager = CBCentralManager(delegate: self, queue: DispatchQueue(label: "com.iotCourse.bleq", qos: .userInitiated), options: initOptions)
    }
    
    
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        os_log("Central Manager state: %s", log: Log.ble, type: .info, central.state.rawValue.description)
        
        var status: BleStatus
        
        switch central.state {
            
        case .poweredOn:
            print("Powered On")
            status = .onLine
            //central.scanForPeripherals(withServices: [Cork_Service_CBUUID], options: initOptions)
            //print("SCanning")
            
        case .poweredOff, .resetting, .unknown, .unsupported:
            status = .offLine
                
        /*if central.state == .poweredOn {
            // Are we transitioning from BT off to BT ready?
            print("Powered On")
            status = .onLine
            central.scanForPeripherals(withServices: [Cork_Service_CBUUID], options: initOptions)
            print("SCanning")
        }
        if central.state == .poweredOff {
            // Are we transitioning from BT off to BT ready?
            status = .offLine
            print("Powered Off")*/
        case .unauthorized:
            status = .offLine
            
        @unknown default:
            status = .offLine
        }
        
        nc.post(name: .bleStatus, object:BleStatusPayload(status: status))
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        os_log("In didDiscoverPeripheral: %s", log: Log.ble, type: .info, peripheral.identifier.uuidString)
        
        //Corks.append(Cork_Model(peripheral: peripheral, name: peripheral.name ?? "NoName", type: CMCorkType,  isConnected: false))
        //Corks.append(Cork_Model(peripheral: peripheral, name: peripheral.name ?? "No Name", type: nil, characteristic: nil, isConnected: false))
        //print(Cork_Model.init(peripheral: peripheral, name: peripheral.name ?? "No Name", type: nil, characteristic: nil, isConnected: false))
        
        //central.stopScan()
        //print("didDiscover completed...")
        //print("Cork name ", peripheral)
        peripherals.append(peripheral)
        discoveredPeripheral = peripherals[PeripheralCount]
        peripheral.delegate = self
        //print("Peri Count = ", PeripheralCount)
        //print("name = ", peripherals[PeripheralCount].name ?? "No Peripheral Name")
        if PeripheralCount == 4 {
            centralManager?.stopScan()
            cmdQueue.async {self.handleEvent(event: .ScanSuccess) }
        }
        PeripheralCount = PeripheralCount + 1
    }//.......END func didDiscover.......
    
    func centralManager(_ central: CBCentralManager, didConnect peripherals: CBPeripheral) {
        os_log("In didConnect: %s", log: Log.ble, type: .info, peripherals.identifier.uuidString)

        cmdQueue.async { self.handleEvent(event: .ConnectSuccess) }
       //print("Stopping Scan for Peripherals")
       //centralManager?.stopScan()
        
        // STEP 8: look for services of interest on peripheral
        
       
        //print("peripheral", peripherals)
        // Remember the ID for startup reconnecting.
        //UserDefaults.standard.set(peripherals.identifier.uuidString,forKey: peripheralIdDefaultsKey)
        //UserDefaults.standard.synchronize()
        
        //let peripheralIdStr = UserDefaults.standard.object(forKey: peripheralIdDefaultsKey)
        //let peripheralId = UUID(uuidString: peripheralIdStr as! String)
        //print("peripheralId is ...", peripheralId ?? "No UD Peri")
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        os_log("In didFailToConnect: %s", log: Log.ble, type: .info, peripheral.identifier.uuidString)

        cmdQueue.async { self.handleEvent(event: .ConnectFail) }
            
        }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        os_log("In didFailToConnect: %s", log: Log.ble, type: .info, peripheral.identifier.uuidString)
            
        if error == nil {
            // Intentional disconnect
            cmdQueue.async { self.handleEvent(event: .Disconnected) }
        }
        else {
            // Unexpected disconnect
            os_log("Peripheral disconnected with error", log: Log.ble, type: .error)
            cmdQueue.async { self.handleEvent(event: .DisconnectedWithError) }
        }
        
    }


// MARK: - Private functions
   
//
private func setupStateMaps() {
    
    // State ACtion Map
    stateActionMap[.Scanning] = (onEntry: performScan, onExit: nil)
    //stateActionMap[.Ready] = (onEntry: performConnect, onExit: nil)
    stateActionMap[.Ready] = (onEntry: performNotifyAttached, onExit: nil)
    stateActionMap[.Retrieving] = (onEntry: performRetrieve, onExit: nil)
    
    //ActionMap
    actionMap[.Start]?[.Scan] = (action: performNullAction, nextState: .Scanning)
    actionMap[.Start]?[.Retrieve] = (action: performNullAction, nextState: .Retrieving)
    actionMap[.Start]?[.OffLine] = (action: performNullAction, nextState: nil)
    
    //
    actionMap[.Scanning]?[.ScanSuccess] = (action: performNullAction, nextState: .Ready)
    actionMap[.Scanning]?[.OffLine] = (action: performNullAction, nextState: .Start)
    
    //
    actionMap[.Retrieving]?[.RetrieveFail] = (action: performNullAction, nextState: .Scanning)
    actionMap[.Retrieving]?[.ConnectSuccess] = (action: performNullAction, nextState: .Ready)
    actionMap[.Retrieving]?[.ConnectFail] = (action: performNullAction, nextState: .Start)
    actionMap[.Retrieving]?[.OffLine] = (action: performNullAction, nextState: .Start)
    
    actionMap[.Ready]?[.OffLine] = (action: performNullAction, nextState: .Start)
    actionMap[.Ready]?[.Disconnected] = (action: performNullAction, nextState: nil)
    actionMap[.Ready]?[.DisconnectedWithError] = (action: performNullAction, nextState: nil)
    
    //
    errorMap[.Scanning] = (action: performNullAction, nextState: .Start)
    errorMap[.Retrieving] = (action: performNullAction, nextState: .Start)
    errorMap[.Ready] = (action: performNullAction, nextState: .Start)
}

private func handleEvent(event: BEvent) {
    if let mac = machine {
        mac.handleEvent(event: event)
    }
}

private func setLastAttachedPeripheral(defaults: UserDefaults, peripheral: CBPeripheral) {
    
    let cork = LastAttachedPeripheral(peripherals: peripheral.identifier)
    peripheralArray.append(cork)
    
   
  
    print("corks before encoding .. ", peripheralArray)
    
    
    //let per = centralManager?.retrievePeripherals(withIdentifiers: [peripheralArray]).first
    
    //print("peri Array", peripheralArray[0])
    
    do  {
        let encoder = JSONEncoder()
        
        let data = try encoder.encode(peripheralArray)
        
        defaults.set(data, forKey: kLastAttachedPeripheralKey)
    } catch {
        print("Unable to encode array (\(error))")
    }

    
    /*if let data = defaults.data(forKey: kLastAttachedPeripheralKey) {
        do {
            let decoder = JSONDecoder()
            
            let corks = try decoder.decode([LastAttachedPeripheral].self, from: data)
            print("Peripheral: ", corks.last?.peripherals ?? "No Corks in UD")
        } catch {
            print("Unable to decode array (\(error))")
        }
     
    }*/
    
    var retValue: Array<LastAttachedPeripheral>? = nil
    
    
    if let peri = defaults.object(forKey: kLastAttachedPeripheralKey) as? Data
    {
        retValue = try? JSONDecoder().decode([LastAttachedPeripheral].self, from: peri)
        print("retValue = ", retValue as Any)
        let per = centralManager?.retrievePeripherals(withIdentifiers: [retValue]).map {$0.peripheral}
        
    }
  
    
   
    
    

    //if let data = defaults.object(forKey: kLastAttachedPeripheralKey) {
    //    do {
    //        let decoder = JSONDecoder()
    //        let corks2 = try? decoder.decode([LastAttachedPeripheral].self, from: strings)
    //        print("Corks AKA Peripherals ... ", corks2 ?? "No Peri in UD")
    //    }
    //}
    
    //if let data2 = defaults.data(forKey: kLastAttachedPeripheralKey) {
    //    if let corks2 = try? PropertyListDecoder().decode([LastAttachedPeripheral].self, from: data2) {
     //       print("Corks retrieved > ", corks2)
     //   }
    //}
    
    //let UD_String = defaults.object(forKey: kLastAttachedPeripheralKey)
    //print("UD > ", UD_String ?? "NO UD Peri")
}

/*private func getLastAttachedPeripheral(defaults: UserDefaults) -> LastAttachedPeripheral? {
    let retValue: LastAttachedPeripheral? = nil
    
    let data = defaults.data(forKey: kLastAttachedPeripheralKey)!
        do {
            let decoder = JSONDecoder()
            
            let retValue = try decoder.decode([LastAttachedPeripheral].self, from: data)
            print("GLAP - Peripheral: ", retValue )
        } catch {
            print("Unable to decode array (\(error))")
        }
    return retValue
}*/

    private func getPeripherals(defaults: UserDefaults) -> [LastAttachedPeripheral]? {
        var retValue: [LastAttachedPeripheral]? = []
        
        if let data = defaults.data(forKey: kLastAttachedPeripheralKey) {
            let decoder = JSONDecoder()
            retValue = try? decoder.decode([LastAttachedPeripheral].self, from: data)
            print("GLAP - Peripheral: ", retValue ?? "No Corks in UD" )
        }
    return retValue
}
    

//private func save(_ corks: [LastAttachedPeripheral], defaults: UserDefaults) {
//        let data = corks.map { try? JSONEncoder().encode($0) }
//    defaults.array(data, forKey: kLastAttachedPeripheralKey)
//    }

private func load(defaults: UserDefaults) -> [LastAttachedPeripheral] {
    guard let encodedData = defaults.object(forKey: kLastAttachedPeripheralKey) as? [Data] else {
            return []
        }
        return encodedData.map { try! JSONDecoder().decode(LastAttachedPeripheral.self, from: $0) }
    }
    
    


// MARK: - Public (Internal) API
//
func attachPeripheral(suuid: CBUUID, forceScan: Bool = false) {
    //func attachPeripheral(suuid: CBUUID) {
    //
    attachingWith = (nil, suuid, false)
    //cmdQueue.async {self.handleEvent(event: forceScan ? .Retrieve : .Scan) }
    cmdQueue.async {self.handleEvent(event: forceScan ? .Scan : .Retrieve) }
}
    
func read(suuid: CBUUID, cuuid: CBUUID) {
    //
}
    
func write(suuid: CBUUID, cuuid: CBUUID, data: Data, response: Bool) {
    //
}
    
func setNotify(suuid: CBUUID, cuuid: CBUUID, state: Bool) {
    //
}
    
func readRssi() {
    //
}

}


// MARK: - Actions
//
extension BLE_Controller { //This fucntion traces what is going on during development....remove this later if you want too.

// Actions handlers are always passed event and state.  Event always has an associated payload that is extracted and passed.  Other than this Action Handlers are used for debug tracing..the state vaule should not be used in the handler logic. if you start using "if" statement for the state you need to backup and rethink your logic because that is the purose of the state machine,

func performNullAction(event: BEvent, state: BState) {
    os_log("Trace: event %s, state: %s", log: Log.ble, type: .info, event.description, state.description)
}

func performScan(event: BEvent, state: BState) throws {
        os_log("In performScan, event: %s state %s", log: Log.ble, type: .info, event.description, state.description)
    guard let cm = centralManager, let suuid = attachingWith.suuid else {
           throw BleError.UninitialisedProperty
        }
    cm.scanForPeripherals(withServices: [suuid], options: nil)
    performNullAction(event: event, state: state)
}

func performConnect(event: BEvent, state: BState) throws {
    os_log("In performConnect, event: %s state %s", log: Log.ble, type: .info, event.description, state.description)
    let cm = centralManager
    //let per = peripherals[0]                                                                                          //<<<<<<<<< THIS NEEDS ERROR CONTROL
    for peripheral in peripherals {
    cm!.connect(peripheral, options: nil)
    }
}

func performNotifyAttached(thisEvent: BEvent, thisState: BState) {
    os_log("In performNotifyAttached, event: %s state: %s", log: Log.ble, type: .info, thisEvent.description, thisState.description)

    attachingWith.isAttached = true
    //if let per = attachingWith.peripheral, let suuid = attachingWith.suuid {
    //let suuid = attachingWith.suuid                                                                                      //<<<<<<<<< THIS NEEDS ERROR CONTROL
    for peripheral in peripherals {
        setLastAttachedPeripheral(defaults: UD, peripheral: peripheral)
        //setLastAttachedPeripheral(defaults: UD, peripheral: per, suuid: suuid)
    
    }
    nc.post(name: .bleStatus, object: BleStatusPayload(status: .ready))
}

func performRetrieve(event: BEvent, state: BState) throws {
    os_log("In performRetrieve, event: %s state %s", log: Log.ble, type: .info, event.description, state.description)
    //var lap: [CBPeripheral] = []
    guard let cm = centralManager, let suuid = attachingWith.suuid else {
        throw BleError.UninitialisedProperty }
    
    //let peri = UserDefaults.standard.data(forKey: kLastAttachedPeripheralKey) as? [UUID]
    //let per = cm.retrievePeripherals(withIdentifiers: peri)
    
    //let uuid = UUID(uuidString: "ASDFASDFASDF-ASDF-ASDF-ASDFASDFASDF")
    //let per = cm.retrievePeripherals(withIdentifiers: [uuid]).first
    
    }
}
    


    
// MARK: - State Machine
//
// MARK: State Map Aliases
//
typealias StateActionMap = Dictionary<BState, (onEntry: ((BEvent, BState) throws ->())?, onExit: ((BEvent, BState) throws ->())?)>
typealias ActionMap = Dictionary<BState, Dictionary<BEvent, (action: ((BEvent, BState) throws ->())?, nextState: BState?)>>
typealias ErrorMap = Dictionary<BState, (action: ((BEvent, BState) -> ())?, nextState: BState)>

// MARK: State, Event, Action Enumerations
//

//
// Valid states
//
enum BState: Int, CaseIterable {
    case Start
    case Scanning
    case Ready
    case Retrieving
}

extension BState: CustomStringConvertible {

    var description: String {
        switch self {
        case .Start: return "Start"
        case .Scanning: return "Scanning"
        case .Ready: return "Ready"
        case .Retrieving: return "Retrieving"
        }
    }
}

//
// Valid events
//
enum BEvent {
    case OnLine             // Bluetooth is powered on and available
    case OffLine            // Bluetooth is not available (several possible reasons)
    case Scan
    case ScanSuccess
    case Retrieve
    case RetrieveFail
    case ConnectSuccess
    case ConnectFail
    case Disconnected
    case DisconnectedWithError
}

extension BEvent: CustomStringConvertible {

    var description: String {
        switch self {
        case .OnLine: return "OnLine"
        case .OffLine: return "OffLine"
        case .Scan: return "Scan"
        case .ScanSuccess: return "ScanSuccess"
        case .Retrieve: return "Retrieve"
        case .RetrieveFail: return "RetrieveFail"
        case .ConnectSuccess: return "Connect Success"
        case .ConnectFail: return "Connect Fail"
        case .Disconnected: return "Disconnected"
        case .DisconnectedWithError: return "Disconnected With Error"
        }
    }
}

// MARK: Class Machine
//

fileprivate final class Machine {
    private var stateActionMap: StateActionMap = [:]
    private var actionMap: ActionMap = [:]
    private var errorMap: ErrorMap = [:]
    private var currentState:BState? = .Start
        
    // MARK: Initialisation
    //
    init(actionMap: ActionMap, stateActionMap: StateActionMap, errorMap: ErrorMap) {
        self.actionMap = actionMap
        self.stateActionMap = stateActionMap
        self.errorMap = errorMap
    }

    // MARK: Private functions
    //
    /**
    Handle nested event error
         State machine concurrently processes two events.  Queueing should ensure that this condition never occurs.  However, in production, if this situation does occur, probably no option but to discard the event and continue
         */
    private func nilStateError() {
        assertionFailure("ERROR: Nested event")
        os_log("ERROR: Nested event", log: Log.ble, type: .error)
    }

    // MARK: Public (Internal) functions
    /**
    Performs state transition and error management
         Action Map rules:
         - For a given event:
          - absence of an entry signifies an invalid event for this state
          - a valid entry with a nil action signifies no transition action to be taken but state entry/exit action should be taken
          - a valid entry with a nil nextState signifies staying in the same state without executing state entry or exit actions

         State Action Map rules:
         - A valid dictionary entry defines the state entry and/or exit actions
         - Entry and/or exit actions only occur if actionMap.nextState != nil
         - Either action may be nil which signifies no action to be taken
         
         Error Map rules:
         - For each state, an error handling function and a next state are specified
                     
         */
        internal func handleEvent(event: BEvent) {
            // Event processing cannot be nested
            // Ensure that machine is not currently processing an event
            guard let savedState = currentState else {
                nilStateError()
                return
            }
            //print("savedState....",savedState," - Event.... ",event)
            
            // Execute actions while in the "nil state" state
            // This prevents processing nested events
            currentState = nil

            // Check for valid event for this state
            guard let tr = actionMap[savedState]?[event] else {
                errorMap[savedState]?.action?(event, savedState)
                currentState = errorMap[savedState]?.nextState
                assertionFailure("Invalid event \(event) for state \(savedState)")
                return
            }
            
            do {
                // Execute state exit action
                if let _ = tr.nextState {
                    try stateActionMap[savedState]?.onExit?(event, savedState)
                    //print("stateActionMap hit")
                }
                
                // Execute transition action
                try tr.action?(event, savedState)
            

                // Enter next state, execute entry action
                if let ns = tr.nextState  {
                    currentState = ns
                    try stateActionMap[ns]?.onEntry?(event, ns)
                    //print("try stateActionMap from CS", ns)
                }
                else { currentState = savedState }
            }
            catch {
                os_log("ERROR: %s, Event: %s, State: %s", log: Log.ble, type: .error,
                       error.localizedDescription, event.description, savedState.description)
                assertionFailure(error.localizedDescription)
                errorMap[savedState]?.action?(event, savedState)
                currentState = errorMap[savedState]?.nextState
            }
        }

}

