# SpatialFlow: AI-Powered Spatial Continuity Engine

## 1. Project Overview
**SpatialFlow** is a self-aware, intelligent software architecture designed to eliminate digital boundaries between devices. It creates a **unified, smart spatial canvas** across Mobile, Desktop, and Laptop devices.

Unlike traditional tools, SpatialFlow possesses a **Neural Core**. It learns user habits, predicts gestures, and autonomously optimizes data streams to ensure zero-latency "presence" of content across devices.

### Core Philosophy
* **AI-First Foundation:** The system is "self-aware"—constantly monitoring network health, device proximity, and user intent.
* **Presence over Ownership:** We transfer the *live view* and state of content, utilizing AI to predictively buffer content on target devices before the user finishes the gesture.
* **Fluidity:** Interaction is driven by natural gestures and AI-assisted automation.

---

## 2. Key Features & Mechanics

### 2.1 The "Split-View" Mechanics
* **Visual Continuity:** Content renders across devices as if they are one physical screen.
* **Omni-Directional Flow:** Seamless movement between Mobile-to-Mobile, Mobile-to-PC, and PC-to-PC.

### 2.2 The "Neural Core" (AI Architecture)
* **Predictive Buffering:** The AI analyzes cursor/finger velocity. If you are moving fast toward the right edge, the AI wakes up the right-side device and pre-loads the content *before* you cross the border.
* **Context Awareness:** The system understands *what* is being moved.
    * *Video:* Prioritizes low-latency UDP streaming.
    * *Text/Code:* Prioritizes lossless TCP transfer.
* **Auto-Calibration:** Uses device sensors and historical signal strength to "guess" the physical layout (e.g., "The laptop is likely on the right because the signal is stronger on that side").

### 2.3 User Interaction
* **Smart Gestures:** "Throw" a file to the side, and the AI calculates the trajectory to land it on the correct device.
* **Haptic & Visual Feedback:** AI-driven feedback intensity based on transfer weight (heavy vibration for large files).

---

## 3. Technical Architecture

### 3.1 The Tech Stack
* **Frontend:** **Flutter** (UI & Rendering).
* **AI Edge Layer:** **TensorFlow Lite (TFLite)** (On-device gesture prediction & content classification).
* **Networking:** **Node.js + Socket.io** (Signaling & "Neural Nervous System").
* **Data Transport:** **WebRTC** (P2P Media Stream).

### 3.2 System Logic (The "Brain")
1.  **Sensation:** Devices report telemetry (signal strength, battery, screen content) to the Neural Core.
2.  **Perception:** The Core analyzes velocity and direction.
    * *Example:* "User is swiping video fast to the right."
3.  **Inference:** "Target is likely Device B. Network is congested."
4.  **Action:** "Lower video bitrate for transfer. Tell Device B to open a receive socket NOW."

---

## 4. Roadmap

### Phase 1: The Awake Foundation
* [x] Setup Node.js Signaling Server with AI Hooks.
* [ ] Build Flutter App.
* [ ] **Milestone:** Devices connect and "sense" each other's status (Battery, Load).

### Phase 2: The Visual & Neural Engine
* [ ] Implement "Split Rendering."
* [ ] Integrate TFLite for velocity prediction.
* [ ] **Milestone:** Predictive pre-loading (screen lights up before content arrives).

### Phase 3: Self-Awareness
* [ ] Auto-healing network (switching between WiFi/Bluetooth if one fails).
* [ ] Content content-aware optimization.

---


# SpatialFlow: AI-Powered Spatial Continuity Engine

## 1. Project Overview
**SpatialFlow** is a self-aware, intelligent software architecture designed to eliminate digital boundaries between devices. It creates a **unified, smart spatial canvas** across Mobile, Desktop, and Laptop devices.

## 2. Key Features & Mechanics

### 2.1 The "Split-View" Mechanics
* **Visual Continuity:** Content renders across devices as if they are one physical screen.
* **Omni-Directional Flow:** Seamless movement between Mobile-to-Mobile, Mobile-to-PC, and PC-to-PC.

### 2.2 The "Neural Core" (AI Architecture)
* **Spatial Topology (New):** The system maintains a virtual map of physical device locations.
    * *Routing:* Swiping "Right" on Device A sends content specifically to Device B, because the map knows B is to the right of A.
* **Predictive Buffering:** The AI analyzes cursor/finger velocity to pre-load content.
* **Context Awareness:** The system optimizes transfer protocols based on file type (UDP for video, TCP for text).

### 2.3 User Interaction
* **Calibration Mode:** A drag-and-drop interface to arrange devices physically (e.g., placing the phone icon to the left of the laptop icon).
* **Smart Gestures:** "Throw" a file to the side, and the AI calculates the trajectory.

---

## 3. Technical Architecture

### 3.1 The Tech Stack
* **Frontend:** **Flutter** (UI & Rendering).
* **AI Edge Layer:** **TensorFlow Lite** (Velocity prediction).
* **Networking:** **Node.js + Socket.io** (Signaling & Topology Management).
* **Data Transport:** **WebRTC** (P2P Media Stream).

### 3.2 System Logic (Topology Routing)
1.  **Calibration:** User arranges devices in the UI. Server stores this map (e.g., `Device A [Right] -> Device B`).
2.  **Action:** User swipes "Right" on Device A.
3.  **Routing:** Server looks up the neighbor to the right of A.
4.  **Delivery:** Server routes the ghost data *only* to Device B, ignoring Device C (which might be on the left).

---