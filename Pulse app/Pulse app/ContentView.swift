//
//  ContentView.swift
//  Pulse app
//
//  Created by Noé Cornu on 20/10/2025.
//

import SwiftUI

struct ContentView: View {
    
    //MARK: - Properties
    
    // Manage the Bluetooth Low Energy (BLE) connection and state
    @StateObject private var bleManager = BLEManager()
    
    // Processes incoming raw data (either from BLE or simulation)
    @StateObject private var dataProcessor = DataProcessor()
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Projet Pulse ⚡️")
                .font(.largeTitle)
                .fontWeight(.bold)

            // Affiche une icône qui change de couleur en fonction de l'état de la connexion.
            Image(systemName: "wave.3.right.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(bleManager.isConnected ? .green : .gray)
            
            // Affiche le message de statut de notre BLEManager.
            // Ce texte se mettra à jour automatiquement !
            Text(bleManager.connectionStatus)
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding()
            
            if let bpm = bleManager.heartRate {
                Text("\(bpm) BPM")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .transition(.opacity)
            }

            Spacer()
        }
        .onAppear {
            // On connecte les deux modules comme avant
            bleManager.dataProcessor = self.dataProcessor
        }
        .padding()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
