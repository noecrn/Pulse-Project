//
//  BLEManager.swift
//  Pulse app
//
//  Created by Noé Cornu on 20/10/2025.
//

import Foundation
import CoreBluetooth
import Combine

// Rend notre classe observable par SwiftUI pour que l'interface se mette à jour.
class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    // MARK: - Propriétés
    
    // Le "chef d'orchestre" du Bluetooth. Il scanne, se connecte, etc.
    var centralManager: CBCentralManager!
    // L'appareil Pulse auquel nous sommes connectés.
    var pulsePeripheral: CBPeripheral?
    // Contient la référence vers notre DataProcessor.
    var dataProcessor: DataProcessor?

    // @Published permet à SwiftUI de réagir automatiquement aux changements de ces variables.
    @Published var connectionStatus: String = "Déconnecté"
    @Published var isConnected: Bool = false
    @Published var heartRate: Int? = nil
    
    
    let heartRateCharacteristicUUID = CBUUID(string: "2A37")
    
    // MARK: - Initialisation
    
    override init() {
        super.init()
        // On initialise le chef d'orchestre. Le "delegate: self" signifie que
        // cette classe (BLEManager) recevra tous les événements Bluetooth.
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Logique de Scan et Connexion

    // Cette fonction est appelée automatiquement quand l'état du Bluetooth change (allumé, éteint...).
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            connectionStatus = "Bluetooth activé. Recherche..."
            // Le Bluetooth est prêt, on lance le scan pour trouver notre appareil.
            centralManager.scanForPeripherals(withServices: nil, options: nil)
        } else {
            connectionStatus = "Bluetooth non disponible."
            isConnected = false
        }
    }

    // Cette fonction est appelée chaque fois qu'un appareil BLE est trouvé.
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // NOTE: Il faudra adapter cette condition au nom de ton appareil.
        // Pour l'instant, on se connecte au premier appareil trouvé qui a un nom.
        if let peripheralName = peripheral.name, peripheralName.contains("Forerunner 255") {
            print("Appareil Pulse trouvé: \(peripheralName)")
            
            self.pulsePeripheral = peripheral
            self.pulsePeripheral?.delegate = self
            
            // On a trouvé notre appareil, on arrête de scanner.
            centralManager.stopScan()
            
            // On se connecte à l'appareil.
            centralManager.connect(peripheral, options: nil)
            connectionStatus = "Connexion à \(peripheralName)..."
        }
    }

    // Cette fonction est appelée quand la connexion réussit.
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectionStatus = "Connecté à \(peripheral.name ?? "Pulse")"
        isConnected = true
        print("Connexion réussie !")
        
        // Maintenant qu'on est connecté, on cherche les "services" qu'il propose.
        peripheral.discoverServices(nil)
    }

    // Cette fonction est appelée si la connexion échoue ou est perdue.
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectionStatus = "Déconnecté"
        isConnected = false
        print("Appareil déconnecté. Reprise du scan...")
        // On relance le scan pour le retrouver.
        centralManager.scanForPeripherals(withServices: nil, options: nil)
    }
    
    // MARK: - Découverte des Services et Caractéristiques

    // Cette fonction est appelée quand les services de l'appareil ont été trouvés.
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            print("Service trouvé: \(service.uuid.uuidString)")
            // Pour chaque service, on cherche les "caractéristiques" (les canaux de communication).
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    // Cette fonction est appelée quand les caractéristiques d'un service ont été trouvées.
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            print("Caractéristique trouvée: \(characteristic.uuid.uuidString)")
            
            // On vérifie si c'est la caractéristique qui nous intéresse (celle qui envoie des données).
            // On s'abonne aux notifications pour recevoir les données en temps réel.
            if characteristic.properties.contains(.notify) {
                print("Abonnement aux données de la caractéristique \(characteristic.uuid.uuidString)...")
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }
    
    // MARK: - Réception des Données

    // Cette fonction est appelée chaque fois que l'appareil envoie de nouvelles données.
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        
        // On vérifie si les données proviennent de la caractéristique de Fréquence Cardiaque (2A37)
        if characteristic.uuid == heartRateCharacteristicUUID {
            
            // On décode les octets bruts pour obtenir la fréquence cardiaque
            let hrValue = parseHeartRate(from: data)
            print(">>> Fréquence Cardiaque (Garmin): \(hrValue) BPM")

            DispatchQueue.main.async {
                self.heartRate = hrValue
                self.dataProcessor?.add(heartRate: Double(hrValue), accelX: 0.0, accelY: 0.0, accelZ: 0.0)
            }
            
        } else {
            // C'est une autre caractéristique, on l'ignore pour l'instant
            print("Données reçues (Autre): \(characteristic.uuid.uuidString) - \(data.count) octets")
        }
    }
    
    /// Décode les données brutes (raw bytes) de la caractéristique 2A37.
    private func parseHeartRate(from data: Data) -> Int {
        // Convertit l'objet Data en un tableau d'octets [UInt8]
        let bytes = [UInt8](data)
        
        // Le premier octet (bytes[0]) contient les drapeaux (flags)
        let flags = bytes[0]
        
        // On vérifie le premier bit (Bit 0) des drapeaux.
        // S'il est à 0, la fréquence est sur 8 bits (1 octet).
        // S'il est à 1, la fréquence est sur 16 bits (2 octets).
        let is16Bit = (flags & 0x01) != 0
        
        if is16Bit {
            // La fréquence est sur 2 octets (bytes[1] et bytes[2])
            let heartRate: UInt16 = (UInt16(bytes[1]) & 0xFF) | (UInt16(bytes[2]) << 8)
            return Int(heartRate)
        } else {
            // La fréquence est sur 1 octet (bytes[1])
            let heartRate: UInt8 = bytes[1]
            return Int(heartRate)
        }
    }
}
