# PPT-Ready Architecture Diagrams

Copy any block into a Mermaid-enabled slide tool (e.g. Marp, Mermaid Live →
PNG/SVG, or the VS Code Mermaid export) to drop straight into the deck.

## Slide 1 — The pitch (one line)

```mermaid
flowchart LR
  RN["📱 Existing React Native<br/>NHAI App"]
  SDK["🧩 NHAI Biometric SDK<br/>(Flutter module)"]
  AI["🧠 MobileFaceNet · ML Kit<br/>SQLCipher · Offline Sync<br/><b>FROZEN — reused as-is</b>"]
  RN -->|"5 simple calls"| SDK
  SDK -->|"JSON results"| RN
  SDK --- AI
```

## Slide 2 — Packaging (no AI rewrite)

```mermaid
flowchart TB
  subgraph BIN["Shipped as a binary artifact"]
    AAR["Android AAR / iOS xcframework<br/>(flutter build aar)"]
    NPM["npm wrapper: @nhai/biometric"]
  end
  DEV["RN integrator"] -->|"add AAR + npm"| APP["NHAI RN App"]
  APP --> AAR
  APP --> NPM
  AAR -.->|"hosts"| ENGINE["FlutterEngine + AI pipeline"]
```

## Slide 3 — Five API methods

```mermaid
flowchart LR
  subgraph API["NHAI Biometric SDK"]
    M1["enrollEmployee()"]
    M2["authenticateEmployee()"]
    M3["markAttendance()"]
    M4["getAttendanceSummary()"]
    M5["syncRecords()"]
  end
  M1 --> ENR["Enrollment + multi-pose gallery"]
  M2 --> AUTH["Face + blink → match"]
  M3 --> ATT["Turnstile check-in/out"]
  M4 --> DASH["Present · Absent · Late · Pending · Auth%"]
  M5 --> DL["Datalake 3.0 sync + purge"]
```

## Slide 4 — Request/response across the channel

```mermaid
sequenceDiagram
  participant RN as React Native
  participant SDK as Flutter SDK
  RN->>SDK: invoke("markAttendance", args)
  SDK-->>RN: { ok, code, data } (JSON)
```

## Slide 5 — Offline-first → Datalake 3.0

```mermaid
flowchart LR
  FACE["Face verified"] --> LOCAL["SQLCipher<br/>(encrypted)"]
  LOCAL --> QUEUE["Sync Queue<br/>PENDING"]
  QUEUE -->|online| DL["Datalake 3.0"]
  DL -->|ack| SYNCED["SYNCED → purge"]
```

## Slide 6 — Trust boundary

```mermaid
flowchart TB
  subgraph HOST["Host (React Native) — sees only"]
    IDS["IDs · trust scores · counts · metadata"]
  end
  subgraph SECURE["Flutter module — never leaves"]
    BIO["Camera frames · face embeddings · model"]
  end
  HOST <-->|"JSON only"| SECURE
```

> Rendering tip: `mmdc -i DIAGRAMS_PPT.md -o slides.png` (Mermaid CLI) or paste
> into https://mermaid.live to export SVG/PNG for the deck.
