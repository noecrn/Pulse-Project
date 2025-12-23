//
//  DashboardView.swift
//  Pulse app
//
//  Created by Noé Cornu on 23/12/2025.
//

import SwiftUI
import Charts

struct DashboardView: View {
    @ObservedObject var bleManager: BLEManager
    @ObservedObject var dataProcessor: DataProcessor
    
    // Logic
    private let predictor = SleepPredictor()
    @State private var isSleeping: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                // 1. GLOBAL BACKGROUND (Deep Night Theme)
                LinearGradient(
                    colors: [Color(red: 0.05, green: 0.05, blue: 0.15), Color.black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                // 2. MAIN CONTENT SWITCHER
                if dataProcessor.isAnalyzing {
                    // STATE A: LOADING
                    LoadingView()
                    
                } else if isDataAvailable {
                    // STATE B: DASHBOARD (Data Present)
                    ScrollView {
                        VStack(spacing: 25) {
                            
                            // 1. LIVE HEART RATE (Only show if live data exists)
                            if !dataProcessor.featureVector.isEmpty {
                                MetricCard(
                                    title: "Heart Rate",
                                    value: String(format: "%.0f", dataProcessor.currentHeartRate),
                                    unit: "BPM",
                                    icon: "heart.fill",
                                    color: .red
                                )
                                .padding(.top, 20)
                            }

                            // 2. SLEEP REPORT & CHART (Only show if report exists)
                            if let report = dataProcessor.lastSleepReport {
                                SleepReportCard(report: report, data: dataProcessor.hrHistory)
                                    .padding(.top, dataProcessor.featureVector.isEmpty ? 20 : 0)
                            }
                            
                            // REMOVED: DebugFooter (ML Feature Vector is gone)
                        }
                        .padding()
                    }
                    
                } else {
                    // STATE C: EMPTY STATE (No Data)
                    EmptyStateView()
                }
            }
            .navigationTitle("Pulse Monitor")
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        // Keep the prediction logic running in the background for live updates
        .onReceive(dataProcessor.$featureVector) { newFeatures in
            guard !newFeatures.isEmpty else { return }
            let result = predictor.predict(features: newFeatures)
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                self.isSleeping = (result == 1)
            }
        }
    }
    
    // Helper to check if we should show ANY content
    private var isDataAvailable: Bool {
        return !dataProcessor.featureVector.isEmpty || dataProcessor.lastSleepReport != nil
    }
}

// MARK: - SUBVIEWS

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "sensor.tag.radiowaves.forward")
                .font(.system(size: 60))
                .foregroundStyle(.white.opacity(0.3))
                .padding(.bottom, 10)
            
            Text("No Device Synced")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.white)
            
            Text("Try to sync the bracelet or import manually a CSV file")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial.opacity(0.3))
    }
}

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 15) {
            ProgressView()
                .tint(.white)
                .scaleEffect(1.5)
            Text("Processing Night Data...")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.5))
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: icon)
                        .foregroundStyle(color)
                        .font(.title3)
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(value)
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    
                    Text(unit)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(25)
        .background(.ultraThinMaterial)
        .cornerRadius(25)
    }
}

struct SleepReportCard: View {
    let report: SleepReport
    let data: [ChartDataPoint]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            Text("Last Session Analysis")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.top, .leading, .trailing])
            
            // Chart
            ModernChart(data: data)
                .frame(height: 200)
                .padding(.vertical)
            
            Divider().background(Color.white.opacity(0.1))
            
            // Stats Grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                StatItem(label: "Bedtime", value: report.bedTime, icon: "moon.zzz.fill", color: .indigo)
                StatItem(label: "Wake Up", value: report.wakeTime, icon: "sun.max.fill", color: .orange)
                StatItem(label: "Duration", value: report.sleepDuration, icon: "hourglass", color: .teal)
                StatItem(label: "Efficiency", value: report.efficiency, icon: "percent", color: .green)
            }
            .padding()
        }
        .background(.ultraThinMaterial)
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

struct ModernChart: View {
    let data: [ChartDataPoint]
    
    @State private var selectedDate: Date?
    @State private var selectedHR: Double?
    
    var minHR: Double { data.map { $0.value }.min() ?? 40 }
    var maxHR: Double { data.map { $0.value }.max() ?? 140 }
    
    var body: some View {
        VStack(alignment: .leading) {
            if let selectedHR, let selectedDate {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Int(selectedHR)) BPM")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("at " + selectedDate.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
                .transition(.opacity)
            } else {
                Text("Swipe to see details")
                    .font(.caption)
                    .foregroundStyle(.gray.opacity(0.5))
            }
            
            Chart {
                ForEach(data) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("BPM", point.value)
                    )
                    .foregroundStyle(Color.red)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 3))
                }
                
                if let selectedDate, let selectedHR {
                    RuleMark(x: .value("Selected Time", selectedDate))
                        .foregroundStyle(Color.white.opacity(0.3))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                        .annotation(position: .top) {
                            VStack(spacing: 0) {
                                Text("\(Int(selectedHR))")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.white)
                                    .cornerRadius(8)
                                Image(systemName: "arrowtriangle.down.fill")
                                    .font(.system(size: 6))
                                    .foregroundStyle(.white)
                                    .offset(y: -1)
                            }
                        }
                    
                    PointMark(
                        x: .value("Selected Time", selectedDate),
                        y: .value("Value", selectedHR)
                    )
                    .foregroundStyle(.white)
                    .symbolSize(50)
                }
            }
            .chartYScale(domain: (minHR - 5)...(maxHR + 5))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) {
                    AxisValueLabel(format: .dateTime.hour().minute(), centered: true)
                        .foregroundStyle(Color.white.opacity(0.5))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) {
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.1))
                    AxisValueLabel().foregroundStyle(Color.white.opacity(0.5))
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    let startX = value.location.x
                                    if let currentXDate: Date = proxy.value(atX: startX) {
                                        if let closestPoint = data.min(by: { abs($0.date.timeIntervalSince(currentXDate)) < abs($1.date.timeIntervalSince(currentXDate)) }) {
                                            self.selectedDate = closestPoint.date
                                            self.selectedHR = closestPoint.value
                                        }
                                    }
                                }
                                .onEnded { _ in
                                    withAnimation {
                                        self.selectedDate = nil
                                        self.selectedHR = nil
                                    }
                                }
                        )
                }
            }
            .frame(height: 200)
        }
        .padding(.horizontal)
    }
}

struct StatItem: View {
    let label: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.2))
                .clipShape(Circle())
            
            VStack(spacing: 2) {
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                
                Text(label)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.gray)
            }
        }
    }
}
