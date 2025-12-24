# Pulse Project

This document outlines the high-level architecture, data flow, and key components of the Pulse project. It serves as a central reference for how the hardware, firmware, and software interact.

## System Architecture

The system follows a **data streaming architecture**. A low-power wearable device is responsible for raw data acquisition, while a companion iOS application handles all the intensive computation, machine learning inference, and user-facing logic.

The main components are:
1.  **Wearable Device**: A custom-designed PCB with sensors (HR + Accelerometer) and an ESP32 microcontroller.
2.  **iOS Companion App**: A Swift application that processes data in real-time (BLE) or offline (CSV), runs a Core ML model, and visualizes sleep sessions.

---

## Workflow & Data Flow

The end-to-end process for detecting sleep is as follows:

1.  **Data Acquisition**:
    * **Live**: The firmware transmits raw sensor data via Bluetooth Low Energy (BLE).
    * **Offline**: The app imports a CSV simulation file (`.csv`) via the file picker.
2.  **Feature Engineering (`DataProcessor.swift`)**:
    * Incoming raw data (HR, Accel X/Y/Z) is stored in a rolling buffer.
    * The app calculates **11 statistical features** over rolling windows (1 min, 5 min, 15 min).
    * **Features**: `hr60_mean`, `hr60_std`, `hr5_mean`, `hr5_std`, `hr15_mean`, `hr15_std`, `vm60_mean`, `vm60_std`, `vm5_mean`, `vm15_mean`, `vm15_std`.
3.  **Inference (`SleepPredictor.swift`)**:
    * The feature vector (1x11 matrix) is passed to the **Core ML model** (`PulseClassifier`).
    * The model outputs a class label: `0` (Awake) or `1` (Asleep).
4.  **Post-Processing ("Smart Session")**:
    * The app aggregates predictions to identify the "Main Sleep Session".
    * It filters out short naps and bridges small "wake gaps" (up to 60 mins) to form a continuous sleep block.
5.  **Visualization (`DashboardView.swift`)**:
    * The results are displayed on a modern, dark-themed dashboard with interactive charts.

---

## Component Breakdown

### 1. Wearable Device Hardware

The wearable device is a custom-designed Printed Circuit Board (PCB) engineered for minimal size and low power consumption, making it suitable for continuous wear.

* **Design Philosophy**: The hardware design prioritizes a compact form factor and energy efficiency. Component selection was driven by the need for reliable data acquisition and efficient wireless transmission over Bluetooth Low Energy (BLE).

* **Core Components**:
    * **Microcontroller (MCU)**: An **ESP32-WROOM-32E (U1)** serves as the main processor. It was selected for its dual-core architecture, integrated Wi-Fi and BLE capabilities, and extensive low-power modes, which are critical for managing battery life.
    * **Accelerometer & Magnetometer**: An **FXOS8700CQR1 (U8)** is used for motion tracking. This 6-axis sensor provides the raw accelerometer data needed to detect movement and activity levels.
    * **Heart Rate Sensor**: The board integrates a dedicated heart rate sensor IC (**U3**) to capture cardiovascular data.
    * **Power Management**: The power subsystem is managed by dedicated ICs (**U4**, **U5**) that regulate voltage and handle battery charging via a **USB-C connector (U7)**. This ensures stable power delivery to all components.

    ![SCH_Schematic](https://i.imgur.com/c2dHO15.png$0)

* **Connectivity**:
    * **Primary (Data)**: Bluetooth Low Energy (BLE) for streaming sensor data to the companion iOS application.
    * **Secondary (Service)**: 
      * A USB-C port provides the physical interface for battery charging and initial firmware programming.
      * A 3-pin header (H1) is also included on the board, exposing GND, TX, and RX pins for low-level hardware debugging.

    ![3D_render_PCB](https://i.imgur.com/XnQge40.png$0)

* **PCB Layout & Component Placement Strategy**: The PCB utilizes a two-sided component placement strategy to optimize for size, sensor performance, and signal integrity.

    * **Top Side**: As shown in the 2D render, this side houses the main digital and power components. This includes the ESP32 MCU (**U1**), the accelerometer (**U8**), power management ICs (**U4, U5**), and the USB-C connector (**U7**). Placing these components together contains digital noise and simplifies the routing of power and high-speed signals.

    <p align="center">
        <img src="https://i.imgur.com/bLLGVY8.png$0" alt="2D_render" width="500"/>
    </p>

    * **Bottom (Skin-Facing) Side**: This side is dedicated to sensors that require direct proximity or contact with the user's skin. It contains the heart rate sensor (**U3**) and the sensor **U9**. This physical separation isolates the sensitive analog sensors from the noisy digital logic on the top side, ensuring cleaner and more reliable data acquisition.

    <p align="center">
        <img src="https://i.imgur.com/wSPXkMZ.png$0" alt="2D_render" width="500"/>
    </p>

* **Status**: Design complete, awaiting fabrication and assembly.

* **Firmware**: The embedded software responsible for initializing sensors, managing power, and handling BLE communication. It does **not** perform any feature calculation.

### 2. iOS Companion App Structure

* **`BLEManager.swift`**: Handles scanning, connecting, and parsing standard BLE characteristics.
    * *Protocol*: Uses Standard Heart Rate Service (UUID `0x180D`) and Characteristic (UUID `0x2A37`).
* **`DataProcessor.swift`**: The core logic engine. It manages the data buffers, calculates math features (mean/stdDev), and generates `SleepReport` objects.
* **`SleepPredictor.swift`**: A wrapper around the `PulseClassifier.mlmodel`. It handles the conversion from Swift arrays to `MLMultiArray`.
* **`DashboardView.swift`**: The main UI.
    * *Style*: Dark-first "Deep Night" theme, Glassmorphism cards.
    * *Charts*: Interactive Swift Charts with scrubbable touch gestures.
 
      
    <p align="center">
        <img src="https://i.imgur.com/YtVjlis.png" alt="Pulse_app_preview" height="500"/>
    </p>

---

## Sleep Detection Algorithm

The core of the sleep detection logic is a supervised machine learning model. It was trained to recognize the subtle patterns in physiological data that distinguish sleep from wakefulness. The model does not make decisions on raw sensor data directly; instead, it uses a set of carefully crafted features that summarize the user's state over time.

### 1. Key Features

The model's performance relies on **feature engineering**, where raw data is transformed into meaningful inputs. The most important features include:

* **Windowed Statistics**: Basic statistics like the mean and standard deviation of heart rate and the "Vector Magnitude" (overall movement) calculated over 60-second intervals.
* **Rolling Statistics (Temporal Context)**: This is the most critical feature set. The model considers the **mean and standard deviation of heart rate and movement over longer, overlapping windows (5 and 15 minutes)**. These features give the model a sense of trend and context. For example, it can learn that a sustained period of low movement and a gradually decreasing heart rate is a strong indicator of falling asleep.

### 2. The Model: Tuned XGBoost

After comparing several algorithms (including Logistic Regression and Random Forest), a **Tuned XGBoost (Extreme Gradient Boosting) Classifier** was selected as the final model.

```
              precision    recall  f1-score   support

   False           0.99      0.93      0.96      4893
    True           0.76      0.95      0.85      1182

accuracy                               0.93      6075

macro avg          0.87      0.94      0.90      6075
weighted avg       0.94      0.93      0.94      6075
```

* **Why XGBoost?** XGBoost is a powerful and efficient tree-based algorithm known for its high performance in classification tasks. It builds a series of decision trees, where each new tree corrects the errors of the previous one, resulting in a highly accurate predictive model.
* **Tuning**: The model's hyperparameters were optimized using `RandomizedSearchCV` to find the best settings for this specific problem, maximizing its F1-score.

### 3. Training & Output

* **Training Data**: The model was trained and validated on the public **MMASH (Multilevel Monitoring of Activity and Sleep in Healthy People) dataset**.
* **Final Output**: For each 60-second window of incoming sensor data, the algorithm processes the features and outputs a single prediction: `0` (AWAKE) or `1` (SLEEPING).

---

## Current Implementation Status

* **BLE Protocol**: Implemented for Standard Heart Rate (UUID `2A37`).
* **Model**: Fully integrated via Core ML (`.mlpackage`).
* **Feature Parity**: Swift implementation of rolling statistics matches the Python training pipeline.
* **UI/UX**: "App Store Ready" design implemented with SwiftUI Charts and dynamic gradients.
* **Offline Mode**: CSV Import is fully functional for testing and validation.
