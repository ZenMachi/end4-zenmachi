import Qt5Compat.GraphicalEffects
import QtMultimedia
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Rectangle {
    id: phoneRoot

    property bool showStatusOverlay: false
    property string statusTitle: ""
    property string statusSubtitle: ""
    property bool busy: false
    property bool mirrorFeedEnabled: true
    property bool showHomeIndicator: true
    property bool interactiveScreen: true
    property string mirrorDeviceIdMatch: ""
    property string mirrorDeviceDescriptionMatch: ""
    property int mirrorContentWidth: 432
    property int mirrorContentHeight: 960
    property string mirrorFeedError: ""
    property bool mirrorFeedAvailable: false
    property bool mirrorFeedHasRenderedFrame: false
    readonly property var dev: AndroidConnect.mainDevice
    readonly property bool hasDevice: (dev !== null && dev.reachable) || AndroidConnect.resolvedAdbSerial() !== ""
    readonly property bool isAirplaneMode: AndroidConnect.adbAirplaneMode || Boolean(dev && dev.airplaneMode)
    readonly property string wifiSsid: AndroidConnect.adbWifiSsid || (dev ? dev.wifiSsid : "")
    readonly property string deviceName: AndroidConnect.adbDeviceName || (dev && dev.name) || qsTr("Android Phone")
    readonly property int deviceBattery: (dev && dev.battery !== undefined && dev.battery >= 0) ? dev.battery : (AndroidConnect.adbBatteryLevel >= 0 ? AndroidConnect.adbBatteryLevel : -1)
    readonly property bool deviceCharging: (dev && dev.isCharging) || AndroidConnect.adbIsCharging
    readonly property string deviceNetwork: AndroidConnectUtils.getNetworkTypeText((dev && dev.cellularNetworkType) ? dev.cellularNetworkType : AndroidConnect.adbNetworkType, isAirplaneMode, wifiSsid)
    readonly property int deviceSignal: (dev && dev.cellularNetworkStrength !== undefined) ? dev.cellularNetworkStrength : AndroidConnect.adbSignalStrength
    property string currentTimeString: "12:00"
    readonly property real deviceArtWidth: 597
    readonly property real deviceArtHeight: 1241
    readonly property real scaleFactor: Math.min(width / deviceArtWidth, height / deviceArtHeight)
    readonly property real screenRadius: 52 * scaleFactor
    readonly property real videoFrameRadius: 52 * scaleFactor
    readonly property real insetLeftRatio: 25.5 / 597
    readonly property real insetRightRatio: 34.5 / 597
    readonly property real insetTopRatio: 26 / 1241
    readonly property real insetBottomRatio: 25 / 1241
    readonly property real screenWidth: deviceArtWidth * scaleFactor
    readonly property real screenHeight: deviceArtHeight * scaleFactor
    // Stream state
    readonly property bool isVideoStreaming: AndroidConnect.scrcpyRunning && AndroidConnect.scrcpyStreamReady && GlobalStates.androidConnectOpen
    readonly property bool isLaunching: AndroidConnect.scrcpyLaunching || (AndroidConnect.scrcpyRunning && !AndroidConnect.scrcpyStreamReady)

    signal clicked()
    signal startMirrorRequested()
    signal stopMirrorRequested()
    signal tapRequested(real x, real y)
    signal swipeRequested(real x1, real y1, real x2, real y2, int durationMs)
    signal scrollRequested(real x, real y, real deltaX, real deltaY)
    signal textRequested(string text)
    signal keyRequested(int keyCode)
    signal homeRequested()
    signal recentsRequested()
    signal backRequested()


    color: "transparent"

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            let now = new Date();
            let h = String(now.getHours()).padStart(2, '0');
            let m = String(now.getMinutes()).padStart(2, '0');
            phoneRoot.currentTimeString = h + ":" + m;
        }
    }

    MediaDevices {
        id: mediaDevicesInstance
    }

    function findScrcpyDevice() {
        let inputs = mediaDevicesInstance.videoInputs || [];
        for (let i = 0; i < inputs.length; i++) {
            let d = inputs[i];
            let desc = String(d.description || "").toLowerCase();
            let id = String(d.id || "").toLowerCase();
            if (desc.indexOf("scrcpy") !== -1 || id.indexOf("video10") !== -1)
                return d;
        }
        return null;
    }

    property int cameraRetryCount: 0
    property bool captureActive: false

    // Dynamic Capture Graph Loader
    // Only instantiated when isVideoStreaming is true.
    // Unloads immediately when stream ends to completely free /dev/video10.
    Loader {
        id: captureLoader
        active: phoneRoot.captureActive && phoneRoot.isVideoStreaming && phoneRoot.findScrcpyDevice() !== null
        sourceComponent: Component {
            Item {
                CaptureSession {
                    id: session
                    videoOutput: mirrorVideoOutput.videoSink
                    camera: cam
                }

                Camera {
                    id: cam
                    active: true
                    cameraDevice: phoneRoot.findScrcpyDevice()
                    onErrorOccurred: (err, errStr) => {
                        console.warn("[PhoneDisplay Camera Error]", err, errStr);
                        if (phoneRoot.isVideoStreaming && phoneRoot.cameraRetryCount < 4) {
                            cameraRetryTimer.restart();
                        }
                    }
                }
            }
        }
    }

    Timer {
        id: cameraRetryTimer
        interval: 400
        repeat: false
        onTriggered: {
            if (phoneRoot.isVideoStreaming && phoneRoot.cameraRetryCount < 4) {
                phoneRoot.cameraRetryCount += 1;
                console.log("[PhoneDisplay] Retrying camera connection (attempt " + phoneRoot.cameraRetryCount + "/4)...");
                phoneRoot.captureActive = false;
                captureReloadTimer.restart();
            }
        }
    }

    Timer {
        id: captureReloadTimer
        interval: 200
        repeat: false
        onTriggered: {
            if (phoneRoot.isVideoStreaming) {
                phoneRoot.captureActive = true;
            }
        }
    }

    Connections {
        target: mirrorVideoOutput.videoSink
        enabled: target !== null && target !== undefined
        function onVideoFrameChanged(frame) {
            if (!phoneRoot.mirrorFeedHasRenderedFrame) {
                console.log("[PhoneDisplay] First video frame rendered successfully!");
                phoneRoot.mirrorFeedHasRenderedFrame = true;
                frameStallTimer.stop();
            }
        }
    }

    Timer {
        id: frameStallTimer
        interval: 4000
        repeat: false
        running: phoneRoot.isVideoStreaming && !phoneRoot.mirrorFeedHasRenderedFrame
        onTriggered: {
            if (phoneRoot.isVideoStreaming && !phoneRoot.mirrorFeedHasRenderedFrame && phoneRoot.cameraRetryCount < 4) {
                phoneRoot.cameraRetryCount += 1;
                console.warn("[PhoneDisplay] No frames received after 4s, retrying camera stream (attempt " + phoneRoot.cameraRetryCount + "/4)...");
                phoneRoot.captureActive = false;
                captureReloadTimer.restart();
            }
        }
    }

    onIsVideoStreamingChanged: {
        if (!isVideoStreaming) {
            phoneRoot.captureActive = false;
            mirrorFeedHasRenderedFrame = false;
            cameraRetryCount = 0;
            cameraRetryTimer.stop();
            captureReloadTimer.stop();
            frameStallTimer.stop();
        } else {
            phoneRoot.captureActive = false;
            mirrorFeedHasRenderedFrame = false;
            cameraRetryCount = 0;
            captureReloadTimer.restart();
        }
    }

    Item {
        id: phoneRect

        anchors.fill: parent

        // 1. The Phone Chassis Frame (Background, z: 0)
        Image {
            id: phoneFrameImage

            source: Qt.resolvedUrl("./assets/Celu_clean.png")
            fillMode: Image.PreserveAspectFit
            anchors.fill: parent
            z: 0
            antialiasing: true
            smooth: true
        }

        // 2. The Screen Bounds (Sits precisely within chassis screen area, z: 1)
        Rectangle {
            id: screenBounds

            anchors {
                fill: parent
                leftMargin: Math.round(phoneRect.width * phoneRoot.insetLeftRatio)
                rightMargin: Math.round(phoneRect.width * phoneRoot.insetRightRatio)
                topMargin: Math.round(phoneRect.height * phoneRoot.insetTopRatio)
                bottomMargin: Math.round(phoneRect.height * phoneRoot.insetBottomRatio)
            }
            radius: phoneRoot.screenRadius
            clip: true
            color: "#000000"
            z: 1

            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: screenBounds.width
                    height: screenBounds.height
                    radius: screenBounds.radius
                }
            }

            // Live Video Output
            VideoOutput {
                id: mirrorVideoOutput

                anchors.fill: parent
                fillMode: VideoOutput.Stretch
                visible: phoneRoot.isVideoStreaming && phoneRoot.mirrorFeedHasRenderedFrame
                z: 1
            }

            // Idle Screen (Shown when not streaming or waiting for first frame)
            Rectangle {
                id: idleScreen

                anchors.fill: parent
                visible: !phoneRoot.isVideoStreaming || !phoneRoot.mirrorFeedHasRenderedFrame
                color: Appearance.colors.colLayer0
                z: 2

                // Top Android Status Bar
                Item {
                    id: statusBar

                    anchors.top: parent.top
                    anchors.topMargin: Math.max(8, 14 * phoneRoot.scaleFactor)
                    anchors.left: parent.left
                    anchors.leftMargin: Math.max(12, 20 * phoneRoot.scaleFactor)
                    anchors.right: parent.right
                    anchors.rightMargin: Math.max(12, 20 * phoneRoot.scaleFactor)
                    height: 22

                    // Left: Clock
                    StyledText {
                        id: clockText

                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: phoneRoot.currentTimeString
                        font.pixelSize: Math.max(10, Math.round(12 * phoneRoot.scaleFactor))
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer0
                    }

                    // Right: Status Icons (Signal, Network, Battery)
                    RowLayout {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4

                        MaterialSymbol {
                            text: AndroidConnectUtils.getSignalStrengthIcon(phoneRoot.deviceSignal, phoneRoot.isAirplaneMode)
                            iconSize: Math.max(12, Math.round(14 * phoneRoot.scaleFactor))
                            color: Appearance.colors.colOnLayer0
                        }

                        MaterialSymbol {
                            visible: phoneRoot.wifiSsid !== ""
                            text: "wifi"
                            iconSize: Math.max(12, Math.round(14 * phoneRoot.scaleFactor))
                            color: Appearance.colors.colOnLayer0
                        }

                        StyledText {
                            text: phoneRoot.deviceNetwork
                            font.pixelSize: Math.max(8, Math.round(10 * phoneRoot.scaleFactor))
                            font.weight: Font.Bold
                            color: Appearance.colors.colPrimary
                            visible: text !== ""
                        }

                        StyledText {
                            text: phoneRoot.deviceBattery >= 0 ? (phoneRoot.deviceBattery + "%") : ""
                            font.pixelSize: Math.max(9, Math.round(11 * phoneRoot.scaleFactor))
                            font.weight: Font.DemiBold
                            color: phoneRoot.deviceBattery <= 20 ? Appearance.colors.colError : Appearance.colors.colOnLayer0
                            visible: text !== ""
                        }

                        MaterialSymbol {
                            text: phoneRoot.deviceCharging ? "battery_charging_full" : (phoneRoot.deviceBattery <= 20 ? "battery_alert" : "battery_full")
                            iconSize: Math.max(12, Math.round(14 * phoneRoot.scaleFactor))
                            color: phoneRoot.deviceCharging ? Appearance.colors.colPrimary : (phoneRoot.deviceBattery <= 20 ? Appearance.colors.colError : Appearance.colors.colOnLayer0)
                        }

                    }

                }

                // Central Content
                ColumnLayout {
                    anchors.centerIn: parent
                    width: parent.width - Math.max(24, 36 * phoneRoot.scaleFactor)
                    spacing: Math.max(10, 16 * phoneRoot.scaleFactor)

                    // Phone Brand Icon
                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        width: Math.max(48, Math.round(64 * phoneRoot.scaleFactor))
                        height: width
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colLayer1

                        Image {
                            anchors.centerIn: parent
                            width: Math.max(26, Math.round(34 * phoneRoot.scaleFactor))
                            height: width
                            fillMode: Image.PreserveAspectFit
                            source: AndroidConnectUtils.getBrandBadgeSource(phoneRoot.deviceName)
                        }

                    }

                    // Device Model Name
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: phoneRoot.deviceName !== "" ? phoneRoot.deviceName : qsTr("Android Device")
                        font.pixelSize: Math.max(12, Math.round(16 * phoneRoot.scaleFactor))
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnLayer0
                        elide: Text.ElideRight
                        Layout.maximumWidth: parent.width
                    }

                    // Connection status pill
                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: statusRow.implicitWidth + 16
                        implicitHeight: Math.max(22, Math.round(26 * phoneRoot.scaleFactor))
                        radius: Appearance.rounding.full
                        color: phoneRoot.hasDevice ? Qt.rgba(0.2, 0.8, 0.4, 0.15) : Qt.rgba(1, 0.3, 0.3, 0.15)

                        RowLayout {
                            id: statusRow

                            anchors.centerIn: parent
                            spacing: 6

                            Rectangle {
                                width: 7
                                height: 7
                                radius: 3.5
                                color: phoneRoot.hasDevice ? "#4efa90" : "#ff5555"
                            }

                            StyledText {
                                text: phoneRoot.hasDevice ? qsTr("Wired ADB Connected") : qsTr("No Device Detected")
                                font.pixelSize: Math.max(9, Math.round(11 * phoneRoot.scaleFactor))
                                font.weight: Font.DemiBold
                                color: phoneRoot.hasDevice ? "#4efa90" : "#ff8888"
                            }

                        }

                    }

                    // Resolution tag
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: phoneRoot.hasDevice ? (AndroidConnect.adbScreenWidth + " × " + AndroidConnect.adbScreenHeight) : ""
                        font.pixelSize: Math.max(8, Math.round(10 * phoneRoot.scaleFactor))
                        color: Appearance.colors.colSubtext
                        visible: text !== ""
                    }

                    // Main Action Card: Start Mirror
                    Rectangle {
                        id: mirrorActionCard

                        Layout.alignment: Qt.AlignHCenter
                        Layout.fillWidth: true
                        implicitHeight: Math.max(48, Math.round(58 * phoneRoot.scaleFactor))
                        radius: Appearance.rounding.normal
                        color: Appearance.colors.colPrimary

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 10

                            MaterialSymbol {
                                text: "screen_share"
                                iconSize: Math.max(18, Math.round(24 * phoneRoot.scaleFactor))
                                color: Appearance.colors.colOnPrimary
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                StyledText {
                                    text: qsTr("Start Mirror")
                                    font.pixelSize: Math.max(11, Math.round(13 * phoneRoot.scaleFactor))
                                    font.weight: Font.Bold
                                    color: Appearance.colors.colOnPrimary
                                }

                                StyledText {
                                    text: qsTr("Stream inside phone frame")
                                    font.pixelSize: Math.max(8, Math.round(10 * phoneRoot.scaleFactor))
                                    color: Qt.rgba(Appearance.colors.colOnPrimary.r, Appearance.colors.colOnPrimary.g, Appearance.colors.colOnPrimary.b, 0.8)
                                }

                            }

                            MaterialSymbol {
                                text: "arrow_forward"
                                iconSize: Math.max(14, Math.round(18 * phoneRoot.scaleFactor))
                                color: Appearance.colors.colOnPrimary
                            }

                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: phoneRoot.startMirrorRequested()
                        }

                    }

                }

                // Bottom Android Navigation Gesture Pill
                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Math.max(6, 10 * phoneRoot.scaleFactor)
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.max(50, Math.round(72 * phoneRoot.scaleFactor))
                    height: 4
                    radius: 2
                    color: Appearance.colors.colOnLayer0
                    opacity: 0.35
                }

                gradient: Gradient {
                    GradientStop {
                        position: 0
                        color: "#16171d"
                    }

                    GradientStop {
                        position: 0.5
                        color: "#0f1013"
                    }

                    GradientStop {
                        position: 1
                        color: "#14151a"
                    }

                }

            }

            // Launching / Connecting Loading Overlay
            Rectangle {
                id: loadingOverlay

                anchors.fill: parent
                visible: phoneRoot.isLaunching || (phoneRoot.isVideoStreaming && !phoneRoot.mirrorFeedHasRenderedFrame)
                color: "#121318"
                z: 5

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 12

                    BusyIndicator {
                        Layout.alignment: Qt.AlignHCenter
                        running: loadingOverlay.visible
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: phoneRoot.cameraRetryCount > 0
                            ? qsTr("Connecting stream (attempt %1)...").arg(phoneRoot.cameraRetryCount + 1)
                            : qsTr("Starting live display...")
                        font.pixelSize: Math.max(11, Math.round(14 * phoneRoot.scaleFactor))
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnLayer0
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("Connecting to ") + phoneRoot.deviceName
                        font.pixelSize: Math.max(9, Math.round(11 * phoneRoot.scaleFactor))
                        color: Appearance.colors.colSubtext
                    }

                }

            }

        }

        // 3. Top-Level Touch & Gesture Surface (Anchored to screenBounds, z: 30)
        MouseArea {
            id: touchSurface

            property real startX: 0
            property real startY: 0
            property real startTime: 0
            property bool isDragging: false

            anchors.fill: screenBounds
            z: 30
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            cursorShape: phoneRoot.isVideoStreaming ? Qt.ArrowCursor : Qt.PointingHandCursor
            onPressed: (mouse) => {
                if (mouse.button === Qt.RightButton) {
                    phoneRoot.backRequested();
                    return ;
                }
                if (mouse.button === Qt.MiddleButton) {
                    phoneRoot.recentsRequested();
                    return ;
                }
                if (!phoneRoot.isVideoStreaming) {
                    phoneRoot.startMirrorRequested();
                    return ;
                }
                startX = mouse.x;
                startY = mouse.y;
                startTime = Date.now();
                isDragging = false;
            }
            onPositionChanged: (mouse) => {
                if (!phoneRoot.isVideoStreaming)
                    return ;

                let dx = mouse.x - startX;
                let dy = mouse.y - startY;
                if (!isDragging && (Math.abs(dx) > 10 || Math.abs(dy) > 10))
                    isDragging = true;

            }
            onReleased: (mouse) => {
                if (!phoneRoot.isVideoStreaming)
                    return ;

                if (mouse.button !== Qt.LeftButton)
                    return ;

                let boundW = screenBounds.width;
                let boundH = screenBounds.height;
                if (boundW <= 0 || boundH <= 0)
                    return ;

                let endX = mouse.x;
                let endY = mouse.y;
                let duration = Math.max(60, Math.min(800, Date.now() - startTime));
                let dx = endX - startX;
                let dy = endY - startY;
                let screenW = AndroidConnect.adbScreenWidth || 1080;
                let screenH = AndroidConnect.adbScreenHeight || 2388;
                if (isDragging || Math.abs(dx) > 12 || Math.abs(dy) > 12) {
                    let ax1 = Math.max(0, Math.min(screenW, Math.round((startX / boundW) * screenW)));
                    let ay1 = Math.max(0, Math.min(screenH, Math.round((startY / boundH) * screenH)));
                    let ax2 = Math.max(0, Math.min(screenW, Math.round((endX / boundW) * screenW)));
                    let ay2 = Math.max(0, Math.min(screenH, Math.round((endY / boundH) * screenH)));
                    phoneRoot.swipeRequested(ax1, ay1, ax2, ay2, duration);
                } else {
                    let ax = Math.max(0, Math.min(screenW, Math.round((endX / boundW) * screenW)));
                    let ay = Math.max(0, Math.min(screenH, Math.round((endY / boundH) * screenH)));
                    phoneRoot.tapRequested(ax, ay);
                }
                isDragging = false;
            }
            onWheel: (wheel) => {
                // Scroll up -> swipe downwards
                // Scroll down -> swipe upwards

                if (!phoneRoot.isVideoStreaming)
                    return ;

                let screenW = AndroidConnect.adbScreenWidth || 1080;
                let screenH = AndroidConnect.adbScreenHeight || 2388;
                let centerX = Math.round(screenW / 2);
                let centerY = Math.round(screenH / 2);
                let scrollDistance = Math.round(screenH * 0.22);
                if (wheel.angleDelta.y > 0)
                    phoneRoot.swipeRequested(centerX, centerY - scrollDistance, centerX, centerY + scrollDistance, 140);
                else if (wheel.angleDelta.y < 0)
                    phoneRoot.swipeRequested(centerX, centerY + scrollDistance, centerX, centerY - scrollDistance, 140);
            }
        }

    }

}
