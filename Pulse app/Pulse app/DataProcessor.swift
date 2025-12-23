//
//  DataProcessor.swift
//  Pulse app
//
//  Created by Noé Cornu on 20/10/2025.
//

import Foundation
import Combine

// MARK: - Helper Structures

struct SensorDataPoint {
    let timestamp: Date
    let heartRate: Double
    let vectorMagnitude: Double
}

struct SleepReport {
    let bedTime: String
    let wakeTime: String
    let sleepDuration: String
    let efficiency: String
    // NEW: Store actual dates to help filter the chart
    let sessionStartDate: Date
    let sessionEndDate: Date
}

struct ChartDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

// MARK: - Main Processor Class

class DataProcessor: ObservableObject {
    
    // --- Live Data ---
    @Published var currentHeartRate: Double = 0.0
    @Published var currentVectorMagnitude: Double = 0.0
    @Published var featureVector: [Double] = []
    
    // --- Chart & Report ---
    @Published var hrHistory: [ChartDataPoint] = [] // This will now hold ONLY sleep data
    @Published var lastSleepReport: SleepReport? = nil
    @Published var isAnalyzing: Bool = false
    
    // --- Internal ---
    private var dataPoints: [SensorDataPoint] = []
    private let predictor = SleepPredictor()

    // MARK: - 1. Live Data Input
    public func add(heartRate: Double, accelX: Double, accelY: Double, accelZ: Double) {
        let magnitude = sqrt(pow(accelX, 2) + pow(accelY, 2) + pow(accelZ, 2))
        
        DispatchQueue.main.async {
            self.currentHeartRate = heartRate
            self.currentVectorMagnitude = magnitude
        }
        
        let newDataPoint = SensorDataPoint(timestamp: Date(), heartRate: heartRate, vectorMagnitude: magnitude)
        dataPoints.append(newDataPoint)
        
        let fifteenMinutesAgo = Date().addingTimeInterval(-15 * 60)
        dataPoints.removeAll { $0.timestamp < fifteenMinutesAgo }
        
        processNewFeatures()
    }
    
    private func processNewFeatures() {
        guard !dataPoints.isEmpty else { return }
        
        // Rolling window logic
        let now = Date()
        let sixtySecondsAgo = now.addingTimeInterval(-60)
        let fiveMinutesAgo = now.addingTimeInterval(-5 * 60)
        
        let last60s = dataPoints.filter { $0.timestamp > sixtySecondsAgo }
        let last5m = dataPoints.filter { $0.timestamp > fiveMinutesAgo }
        
        let hr60 = last60s.map { $0.heartRate }
        let vm60 = last60s.map { $0.vectorMagnitude }
        let hr5 = last5m.map { $0.heartRate }
        let vm5 = last5m.map { $0.vectorMagnitude }
        let hr15 = dataPoints.map { $0.heartRate }
        let vm15 = dataPoints.map { $0.vectorMagnitude }
        
        let newVector = [
            hr60.mean(), hr60.stdDev(),
            hr5.mean(), hr5.stdDev(),
            hr15.mean(), hr15.stdDev(),
            vm60.mean(), vm60.stdDev(),
            vm5.mean(),
            vm15.mean(), vm15.stdDev()
        ]
        
        DispatchQueue.main.async { self.featureVector = newVector }
    }

    // MARK: - 2. Batch Analysis
    func analyzeFullSession(csvContent: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            self.runBatchProcess(csv: csvContent)
        }
    }
    
    private func runBatchProcess(csv: String) {
        DispatchQueue.main.async { self.isAnalyzing = true }
        
        let lines = csv.components(separatedBy: .newlines)
        var tempBuffer: [(date: Date, hr: Double, vm: Double)] = []
        var sleepPredictions: [(date: Date, isAsleep: Bool)] = [] // Changed to store Date directly
        
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        var referenceDate = Calendar.current.startOfDay(for: Date())
        var lastTimeInterval: TimeInterval = -1

        // 1. Parse Data
        for line in lines.dropFirst() {
            let cols = line.components(separatedBy: ",")
            if cols.count >= 5,
               let hr = Double(cols[1]),
               let ax = Double(cols[2]),
               let ay = Double(cols[3]),
               let az = Double(cols[4]),
               let datePart = formatter.date(from: cols[0]) {
                
                let timeInterval = datePart.timeIntervalSince(Calendar.current.startOfDay(for: datePart))
                if timeInterval < lastTimeInterval {
                    referenceDate = referenceDate.addingTimeInterval(86400)
                }
                lastTimeInterval = timeInterval
                
                let actualDate = referenceDate.addingTimeInterval(timeInterval)
                let vm = sqrt(pow(ax, 2) + pow(ay, 2) + pow(az, 2))
                tempBuffer.append((actualDate, hr, vm))
            }
        }
        
        // 2. Generate Predictions
        for i in stride(from: 900, to: tempBuffer.count, by: 60) {
            let startIndex = i - 900
            let windowIndices = tempBuffer[startIndex...i]
            let rawWindow = windowIndices.map { (timestamp: "", hr: $0.hr, vm: $0.vm) }
            
            let vector = calculateBatchFeatures(window: rawWindow)
            let prediction = predictor.predict(features: vector)
            
            sleepPredictions.append((date: tempBuffer[i].date, isAsleep: prediction == 1))
        }
        
        // 3. Generate Report (Logic extracts start/end dates)
        let report = generateReport(from: sleepPredictions, stepSize: 60)
        
        // 4. CHART: Filter data to ONLY include the sleep session
        var smoothedChartPoints: [ChartDataPoint] = []
        let averageWindow = 300 // 5 minutes
        
        // Optimization: Only loop through the part of buffer that matches the sleep session
        // We add a small buffer (30 mins) before/after to make the chart look nice
        let chartStart = report.sessionStartDate.addingTimeInterval(-1800)
        let chartEnd = report.sessionEndDate.addingTimeInterval(1800)
        
        // Filter buffer first
        let sessionBuffer = tempBuffer.filter { $0.date >= chartStart && $0.date <= chartEnd }
        
        for i in stride(from: 0, to: sessionBuffer.count, by: averageWindow) {
            let endIndex = min(i + averageWindow, sessionBuffer.count)
            let chunk = sessionBuffer[i..<endIndex]
            
            if !chunk.isEmpty {
                let avgHR = chunk.map { $0.hr }.reduce(0, +) / Double(chunk.count)
                let midIndex = chunk.startIndex + (chunk.count / 2)
                let midDate = chunk[midIndex].date
                smoothedChartPoints.append(ChartDataPoint(date: midDate, value: avgHR))
            }
        }
        
        DispatchQueue.main.async {
            self.lastSleepReport = report
            self.hrHistory = smoothedChartPoints
            self.isAnalyzing = false
        }
    }
    
    private func calculateBatchFeatures(window: [(timestamp: String, hr: Double, vm: Double)]) -> [Double] {
        let hrs = window.map { $0.hr }
        let vms = window.map { $0.vm }
        
        let idx60 = max(0, window.count - 60)
        let idx300 = max(0, window.count - 300)
        
        // FIX: Explicitly convert slices to Array before calling .mean()
        let hrs60 = Array(hrs[idx60...])
        let hrs300 = Array(hrs[idx300...])
        
        let vms60 = Array(vms[idx60...])
        let vms300 = Array(vms[idx300...])
        
        return [
            hrs60.mean(), hrs60.stdDev(),
            hrs300.mean(), hrs300.stdDev(),
            hrs.mean(), hrs.stdDev(),
            
            vms60.mean(), vms60.stdDev(),
            vms300.mean(),
            vms.mean(), vms.stdDev()
        ]
    }
    
    private func generateReport(from predictions: [(date: Date, isAsleep: Bool)], stepSize: Int) -> SleepReport {
        // Smart Session Logic
        var bestSession: (start: Int, end: Int, sleepCount: Int) = (0, 0, 0)
        var currentStart = -1
        var currentEnd = -1
        var currentSleepCount = 0
        var wakeGapCounter = 0
        let maxGapSteps = 3600 / stepSize
        
        for (index, item) in predictions.enumerated() {
            if item.isAsleep {
                if currentStart == -1 { currentStart = index }
                currentEnd = index
                currentSleepCount += 1
                wakeGapCounter = 0
            } else {
                if currentStart != -1 {
                    wakeGapCounter += 1
                    if wakeGapCounter > maxGapSteps {
                        if (currentEnd - currentStart) > (bestSession.end - bestSession.start) {
                            bestSession = (currentStart, currentEnd, currentSleepCount)
                        }
                        currentStart = -1
                        currentSleepCount = 0
                    }
                }
            }
        }
        
        if currentStart != -1 && (currentEnd - currentStart) > (bestSession.end - bestSession.start) {
            bestSession = (currentStart, currentEnd, currentSleepCount)
        }
        
        // Fallback dates if nothing found
        let startD = bestSession.end > 0 ? predictions[bestSession.start].date : Date()
        let endD = bestSession.end > 0 ? predictions[bestSession.end].date : Date()
        
        // Calculations
        let secondsInBed = Double(bestSession.end - bestSession.start) * Double(stepSize)
        let actualSleepSeconds = Double(bestSession.sleepCount * stepSize)
        let efficiency = secondsInBed > 0 ? (actualSleepSeconds / secondsInBed) * 100 : 0
        let hours = Int(secondsInBed) / 3600
        let minutes = (Int(secondsInBed) % 3600) / 60
        
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        
        return SleepReport(
            bedTime: bestSession.end > 0 ? timeFormatter.string(from: startD) : "--:--",
            wakeTime: bestSession.end > 0 ? timeFormatter.string(from: endD) : "--:--",
            sleepDuration: "\(hours)h \(minutes)m",
            efficiency: String(format: "%.1f%%", efficiency),
            sessionStartDate: startD,
            sessionEndDate: endD
        )
    }
}

// MARK: - Math Extensions
extension Array where Element == Double {
    func mean() -> Double {
        guard !isEmpty else { return 0.0 }
        return reduce(0, +) / Double(count)
    }

    func stdDev() -> Double {
        guard count > 1 else { return 0.0 }
        let meanValue = self.mean()
        let sumOfSquaredDiffs = self.map { pow($0 - meanValue, 2.0) }.reduce(0, +)
        return sqrt(sumOfSquaredDiffs / Double(count - 1))
    }
}
