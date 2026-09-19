import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Scope {
    id: root

    readonly property bool isOpen: GlobalStates.androidConnectOpen
    readonly property var device: AndroidConnect.mainDevice
    readonly property bool hasDevice: (device !== null && device.reachable) || AndroidConnect.resolvedAdbSerial() !== ""
    // Phone sizing presets: Small (60%), Medium (75%), Large (100%)
    property int phoneSizePresetIndex: (Config.options.androidConnect && Config.options.androidConnect.phoneSizePresetIndex !== undefined) ? Config.options.androidConnect.phoneSizePresetIndex : 1
    readonly property var phoneSizePresets: [{
        "label": "S",
        "factor": 0.6
    }, {
        "label": "M",
        "factor": 0.75
    }, {
        "label": "L",
        "factor": 1
    }]
    readonly property real phoneSizeFactor: {
        var p = phoneSizePresets[phoneSizePresetIndex];
        return p ? p.factor : 0.75;
    }
    readonly property real phoneBaseHeight: 680
    readonly property real phoneBaseWidth: phoneBaseHeight * (597 / 1241)
    readonly property real phoneHeight: phoneBaseHeight * phoneSizeFactor
    readonly property real phoneWidth: phoneBaseWidth * phoneSizeFactor
    readonly property string currentDeviceName: {
        if (AndroidConnect.adbDeviceName && AndroidConnect.adbDeviceName !== "")
            return AndroidConnect.adbDeviceName;
        if (device && device.name && device.name !== "Android Phone")
            return device.name;
        return qsTr("Android Phone");
    }
    // Brand badge resolution
    readonly property string brandBadgeSource: {
        var brand = AndroidConnectUtils.getBrandName(root.currentDeviceName);
        switch (brand) {
        case "Google":
            return Qt.resolvedUrl("assets/brand-badges/google.svg");
        case "Xiaomi":
            return Qt.resolvedUrl("assets/brand-badges/xiaomi.svg");
        case "Motorola":
            return Qt.resolvedUrl("assets/brand-badges/motorola.svg");
        default:
            return Qt.resolvedUrl("assets/brand-badges/android.svg");
        }
    }
    readonly property string brandName: AndroidConnectUtils.getBrandName(root.currentDeviceName)

    readonly property bool isAirplaneMode: AndroidConnect.adbAirplaneMode || Boolean(device && device.airplaneMode)
    readonly property string wifiSsid: AndroidConnect.adbWifiSsid || (device ? device.wifiSsid : "")

    // scrcpy embedded mirror
    readonly property string embeddedVideoDevice: "/dev/video10"
    readonly property int mirrorMaxSize: (Config.options.androidConnect && Config.options.androidConnect.mirrorMaxSize) ? Config.options.androidConnect.mirrorMaxSize : 960
    readonly property int mirrorBitrate: (Config.options.androidConnect && Config.options.androidConnect.mirrorBitrateMbps) ? Config.options.androidConnect.mirrorBitrateMbps : 12
    readonly property int mirrorMaxFps: (Config.options.androidConnect && Config.options.androidConnect.mirrorMaxFps) ? Config.options.androidConnect.mirrorMaxFps : 60
    readonly property bool mirrorAudio: (Config.options.androidConnect && Config.options.androidConnect.embeddedMirrorAudioEnabled) ? true : false
    readonly property string embeddedMirrorCommand: {
        var audioFlag = mirrorAudio ? "" : "--no-audio ";
        return "scrcpy " + audioFlag + "--capture-orientation=@0 --max-size=" + mirrorMaxSize + " --max-fps=" + mirrorMaxFps + " --video-bit-rate=" + mirrorBitrate + "M --video-codec=h264 --v4l2-buffer=0";
    }
    // Telemetry helpers
    readonly property int batteryValue: hasDevice && device && device.battery !== undefined && device.battery >= 0 ? device.battery : (AndroidConnect.adbBatteryLevel >= 0 ? AndroidConnect.adbBatteryLevel : -1)
    readonly property bool isCharging: hasDevice && ((device && device.isCharging) || AndroidConnect.adbIsCharging)
    readonly property string networkType: hasDevice ? AndroidConnectUtils.getNetworkTypeText((device && device.cellularNetworkType) ? device.cellularNetworkType : AndroidConnect.adbNetworkType, isAirplaneMode, wifiSsid) : "--"
    readonly property string signalText: hasDevice ? AndroidConnectUtils.getSignalStrengthText((device && device.cellularNetworkStrength !== undefined) ? device.cellularNetworkStrength : AndroidConnect.adbSignalStrength, isAirplaneMode) : "--"
    readonly property string signalIcon: hasDevice ? AndroidConnectUtils.getSignalStrengthIcon((device && device.cellularNetworkStrength !== undefined) ? device.cellularNetworkStrength : AndroidConnect.adbSignalStrength, isAirplaneMode) : "signal_cellular_off"
    // Panel sizing
    readonly property real panelWidth: phoneWidth + infoColumnWidth + 60
    readonly property real infoColumnWidth: 330
    readonly property real panelHeight: phoneHeight + 140 // Header + nav buttons
    property bool isPinned: false
    property bool userStoppedMirror: false
    property bool hasCustomPosition: false
    property real customX: 0
    property real customY: 0
    property real lastTriggerX: -1
    property real lastTriggerY: -1

    // Bar positioning metrics
    readonly property bool barVertical: Config.options.bar.vertical
    readonly property string barEdge: {
        if (!barVertical) return Config.options.bar.bottom ? "bottom" : "top"
        return Config.options.bar.bottom ? "right" : "left"
    }
    readonly property real barGap: Config.options.bar.cornerStyle === 3 ? (Appearance.sizes.hyprlandGapsOut || 5) : 8
    readonly property real barThickness: barVertical ? Appearance.sizes.verticalBarWidth : Appearance.sizes.barHeight

    readonly property real defaultDialogX: {
        if (barVertical) {
            if (!Config.options.bar.bottom) {
                return Appearance.sizes.verticalBarWidth + 24;
            } else {
                return panelWindow.width - dialogWindow.width - Appearance.sizes.verticalBarWidth - 24;
            }
        } else {
            if (GlobalStates.androidConnectTriggerX >= 0) {
                let xPos = GlobalStates.androidConnectTriggerX - (dialogWindow.width / 2);
                return Math.max(16, Math.min(xPos, panelWindow.width - dialogWindow.width - 16));
            } else {
                return Math.max(16, (panelWindow.width - dialogWindow.width) / 2);
            }
        }
    }

    readonly property real defaultDialogY: {
        if (barVertical) {
            if (GlobalStates.androidConnectTriggerY >= 0) {
                let yPos = GlobalStates.androidConnectTriggerY - (dialogWindow.height / 2);
                return Math.max(16, Math.min(yPos, panelWindow.height - dialogWindow.height - 16));
            } else {
                return Math.max(16, (panelWindow.height - dialogWindow.height) / 2);
            }
        } else {
            if (barEdge === "top") {
                return barThickness + barGap + 8;
            } else {
                return panelWindow.height - dialogWindow.height - barThickness - barGap - 8;
            }
        }
    }

    function resetDialogPosition() {
        dialogWindow.x = root.defaultDialogX;
        dialogWindow.y = root.defaultDialogY;
    }

    function cyclePhoneSize() {
        phoneSizePresetIndex = (phoneSizePresetIndex + 1) % phoneSizePresets.length;
        Config.options.androidConnect.phoneSizePresetIndex = phoneSizePresetIndex;
    }

    Component.onCompleted: {
        GlobalStates.androidConnectOpen = false;
    }

    PanelWindow {
        id: panelWindow

        function hide() {
            GlobalStates.androidConnectOpen = false;
        }

        visible: GlobalStates.androidConnectOpen
        exclusiveZone: 0
        WlrLayershell.namespace: "quickshell:androidConnect"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: GlobalStates.androidConnectOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        color: "transparent"
        onVisibleChanged: {
            if (visible) {
                if (!root.isPinned) {
                    if (GlobalStates.androidConnectTriggerX !== root.lastTriggerX || GlobalStates.androidConnectTriggerY !== root.lastTriggerY) {
                        root.hasCustomPosition = false;
                        root.lastTriggerX = GlobalStates.androidConnectTriggerX;
                        root.lastTriggerY = GlobalStates.androidConnectTriggerY;
                    }
                    if (root.hasCustomPosition) {
                        dialogWindow.x = root.customX;
                        dialogWindow.y = root.customY;
                    } else {
                        root.resetDialogPosition();
                    }
                    GlobalFocusGrab.addDismissable(panelWindow);
                }

                closeStopTimer.stop();
                AndroidConnect.scrcpyStopRequested = false;

                // Refresh devices
                AndroidConnect.refreshDevices();
                AndroidConnect.refreshAdbDevices();
                // Auto-start embedded mirror if device is ready and user hasn't stopped it
                if (root.hasDevice && !AndroidConnect.scrcpyRunning && !AndroidConnect.scrcpyLaunching && !AndroidConnect.directScrcpyRunning)
                    autoStartTimer.restart();

            } else {
                GlobalFocusGrab.removeDismissable(panelWindow);
                closeStopTimer.restart();
            }
        }

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        Timer {
            id: autoStartTimer

            interval: 200
            onTriggered: {
                if (root.hasDevice && !AndroidConnect.scrcpyRunning && !AndroidConnect.scrcpyLaunching && !AndroidConnect.directScrcpyRunning && !root.userStoppedMirror) {
                    let serial = AndroidConnect.resolvedAdbSerial();
                    if (serial !== "")
                        AndroidConnect.launchScrcpySession(serial);

                }
            }
        }

        Timer {
            id: closeStopTimer

            interval: 30000
            onTriggered: {
                if (!GlobalStates.androidConnectOpen && AndroidConnect.scrcpyRunning) {
                    AndroidConnect.stopScrcpySession();
                    AndroidConnect.restoreDeviceScreenSettings();
                }
            }
        }

        Connections {
            function onDismissed() {
                if (!root.isPinned)
                    panelWindow.hide();

            }

            target: GlobalFocusGrab
        }

        Connections {
            target: AndroidConnect
            function onAnyDevicesConnectedChanged() {
                if (GlobalStates.androidConnectOpen && root.hasDevice && !AndroidConnect.scrcpyRunning && !AndroidConnect.scrcpyLaunching && !AndroidConnect.directScrcpyRunning && !root.userStoppedMirror) {
                    autoStartTimer.restart();
                }
            }
            function onAdbConnectedSerialsChanged() {
                if (GlobalStates.androidConnectOpen && root.hasDevice && !AndroidConnect.scrcpyRunning && !AndroidConnect.scrcpyLaunching && !AndroidConnect.directScrcpyRunning && !root.userStoppedMirror) {
                    autoStartTimer.restart();
                }
            }
        }

        // Click-to-dismiss background
        Rectangle {
            anchors.fill: parent
            color: "transparent"
            opacity: GlobalStates.androidConnectOpen ? 1 : 0
            z: 0
            visible: !root.isPinned

            MouseArea {
                anchors.fill: parent
                propagateComposedEvents: false
                onClicked: panelWindow.hide()
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutCubic
                }

            }

        }

        // Main floating dialog
        Rectangle {
            id: dialogWindow

            width: Math.min(parent.width - 80, root.panelWidth)
            height: Math.min(parent.height - 80, root.panelHeight)
            color: Appearance.colors.colLayer0
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
            radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 5
            z: 1
            x: root.defaultDialogX
            y: root.defaultDialogY
            opacity: GlobalStates.androidConnectOpen ? 1 : 0
            scale: GlobalStates.androidConnectOpen ? 1 : 0.95
            Keys.onPressed: (event) => {
                if (event.key === Qt.Key_Escape) {
                    panelWindow.hide();
                    event.accepted = true;
                }
            }

            // Drag handle
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 32
                color: "transparent"
                z: 2

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.SizeAllCursor
                    drag.target: dialogWindow
                    drag.axis: Drag.XAndYAxis
                    drag.minimumX: 8
                    drag.maximumX: Math.max(8, panelWindow.width - dialogWindow.width - 8)
                    drag.minimumY: 8
                    drag.maximumY: Math.max(8, panelWindow.height - dialogWindow.height - 8)
                    onDoubleClicked: {
                        root.hasCustomPosition = false;
                        root.resetDialogPosition();
                    }
                    onPositionChanged: {
                        if (drag.active) {
                            root.hasCustomPosition = true;
                            root.customX = dialogWindow.x;
                            root.customY = dialogWindow.y;
                        }
                    }
                }

            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                // ======== HEADER ROW ========
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    // Interactive Device Selector
                    MouseArea {
                        id: deviceSelectorArea
                        Layout.fillWidth: true
                        Layout.preferredHeight: 36
                        hoverEnabled: true
                        cursorShape: AndroidConnect.adbConnectedDevices.length > 1 ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            if (AndroidConnect.adbConnectedDevices.length > 1) {
                                if (deviceMenuPopup.visible) {
                                    deviceMenuPopup.close();
                                } else {
                                    deviceMenuPopup.open();
                                }
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: Appearance.rounding.small
                            color: (deviceSelectorArea.containsMouse && AndroidConnect.adbConnectedDevices.length > 1)
                                ? Appearance.colors.colLayer1
                                : "transparent"
                            Behavior on color { ColorAnimation { duration: 150 } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 4
                                anchors.rightMargin: 8
                                spacing: 10

                                // Brand badge
                                Image {
                                    source: root.brandBadgeSource
                                    sourceSize.height: 26
                                    sourceSize.width: 26
                                    fillMode: Image.PreserveAspectFit
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                // Device name
                                StyledText {
                                    text: root.hasDevice ? root.currentDeviceName : qsTr("No device connected")
                                    font.pixelSize: Appearance.font.pixelSize.large
                                    font.weight: Font.Bold
                                    color: Appearance.colors.colOnLayer0
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    elide: Text.ElideRight
                                }

                                // Dropdown chevron (visible if multiple devices)
                                MaterialSymbol {
                                    visible: AndroidConnect.adbConnectedDevices.length > 1
                                    text: deviceMenuPopup.visible ? "expand_less" : "expand_more"
                                    iconSize: 20
                                    color: Appearance.colors.colSubtext
                                    Layout.alignment: Qt.AlignVCenter
                                }
                            }
                        }

                        Popup {
                            id: deviceMenuPopup
                            y: parent.height + 4
                            x: 0
                            width: Math.max(parent.width, 280)
                            contentHeight: deviceMenuColumn.implicitHeight
                            padding: 8
                            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                            enter: Transition {
                                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 150; easing.type: Easing.OutCubic }
                            }
                            exit: Transition {
                                NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 150; easing.type: Easing.OutCubic }
                            }
                            background: Rectangle {
                                color: Appearance.colors.colLayer1Base
                                border.width: 1
                                border.color: Appearance.colors.colLayer0Border
                                radius: Appearance.rounding.normal
                            }
                            contentItem: ColumnLayout {
                                id: deviceMenuColumn
                                spacing: 4
                                StyledText {
                                    text: qsTr("Connected Devices")
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.Bold
                                    color: Appearance.colors.colSubtext
                                    Layout.leftMargin: 8
                                    Layout.topMargin: 4
                                    Layout.bottomMargin: 2
                                }
                                Repeater {
                                    model: AndroidConnect.adbConnectedDevices
                                    delegate: RippleButton {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        implicitHeight: 46
                                        buttonRadius: Appearance.rounding.small
                                        colBackground: (modelData.serial === AndroidConnect.resolvedAdbSerial())
                                            ? Appearance.colors.colPrimaryContainer
                                            : (hovered ? Appearance.colors.colLayer2 : "transparent")
                                        onClicked: {
                                            AndroidConnect.selectDevice(modelData.serial);
                                            deviceMenuPopup.close();
                                        }
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 10
                                            anchors.rightMargin: 10
                                            spacing: 10
                                            MaterialSymbol {
                                                text: modelData.isUsb ? "usb" : "wifi"
                                                iconSize: 18
                                                color: (modelData.serial === AndroidConnect.resolvedAdbSerial())
                                                    ? Appearance.colors.colOnPrimaryContainer
                                                    : Appearance.colors.colOnLayer1
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 1
                                                StyledText {
                                                    text: modelData.name || modelData.model || modelData.serial
                                                    font.pixelSize: Appearance.font.pixelSize.normal
                                                    font.weight: Font.Bold
                                                    color: (modelData.serial === AndroidConnect.resolvedAdbSerial())
                                                        ? Appearance.colors.colOnPrimaryContainer
                                                        : Appearance.colors.colOnLayer1
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                }
                                                StyledText {
                                                    text: modelData.serial + (modelData.isUsb ? " (USB)" : " (Wireless)")
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    color: (modelData.serial === AndroidConnect.resolvedAdbSerial())
                                                        ? Appearance.colors.colOnPrimaryContainer
                                                        : Appearance.colors.colSubtext
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                }
                                            }
                                            MaterialSymbol {
                                                visible: modelData.serial === AndroidConnect.resolvedAdbSerial()
                                                text: "check"
                                                iconSize: 18
                                                color: Appearance.colors.colOnPrimaryContainer
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Size cycle button
                    RippleButton {
                        implicitWidth: 36
                        implicitHeight: 36
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colLayer1
                        onClicked: root.cyclePhoneSize()

                        StyledText {
                            anchors.centerIn: parent
                            text: (root.phoneSizePresets[root.phoneSizePresetIndex] && root.phoneSizePresets[root.phoneSizePresetIndex].label) ? root.phoneSizePresets[root.phoneSizePresetIndex].label : "M"
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnLayer1
                        }

                    }

                    // Pin toggle button
                    RippleButton {
                        implicitWidth: 36
                        implicitHeight: 36
                        buttonRadius: Appearance.rounding.full
                        colBackground: root.isPinned ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer1
                        onClicked: {
                            root.isPinned = !root.isPinned;
                            if (root.isPinned)
                                GlobalFocusGrab.removeDismissable(panelWindow);
                            else
                                GlobalFocusGrab.addDismissable(panelWindow);
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: root.isPinned ? "push_pin" : "keep"
                            iconSize: Appearance.font.pixelSize.larger
                            color: root.isPinned ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
                        }

                    }

                    // Wireless ADB QR Code shortcut
                    RippleButton {
                        implicitWidth: 36
                        implicitHeight: 36
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colLayer1
                        onClicked: {
                            GlobalStates.settingsPage = "Android:Wireless ADB";
                            GlobalStates.settingsOpen = true;
                            AndroidConnect.startQrPairing();
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "qr_code_scanner"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnLayer1
                        }

                    }

                    // Close button
                    RippleButton {
                        implicitWidth: 36
                        implicitHeight: 36
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colLayer1
                        onClicked: panelWindow.hide()

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "close"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnLayer1
                        }

                    }

                }

                // ======== MAIN CONTENT ========
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 20

                    // Left: Phone mirror + nav buttons
                    ColumnLayout {
                        spacing: 8
                        Layout.alignment: Qt.AlignTop

                        // Phone display
                        PhoneDisplay {
                            id: phoneDisplay

                            Layout.preferredWidth: root.phoneWidth
                            Layout.preferredHeight: root.phoneHeight
                            onStartMirrorRequested: {
                                root.userStoppedMirror = false;
                                let serial = AndroidConnect.resolvedAdbSerial();
                                if (serial !== "")
                                    AndroidConnect.launchScrcpySession(serial);

                            }
                            onStopMirrorRequested: {
                                root.userStoppedMirror = true;
                                AndroidConnect.stopScrcpySession();
                            }
                            onTapRequested: (x, y) => {
                                let serial = AndroidConnect.resolvedAdbSerial();
                                if (serial !== "")
                                    AndroidConnect.runAdbTap(serial, x, y);

                            }
                            onSwipeRequested: (x1, y1, x2, y2, durationMs) => {
                                let serial = AndroidConnect.resolvedAdbSerial();
                                if (serial !== "")
                                    AndroidConnect.runAdbSwipe(serial, x1, y1, x2, y2, durationMs);

                            }
                            onBackRequested: {
                                let serial = AndroidConnect.resolvedAdbSerial();
                                if (serial !== "")
                                    AndroidConnect.runAdbKeyevent(serial, 4);

                            }
                            onHomeRequested: {
                                let serial = AndroidConnect.resolvedAdbSerial();
                                if (serial !== "")
                                    AndroidConnect.runAdbKeyevent(serial, 3);

                            }
                            onRecentsRequested: {
                                let serial = AndroidConnect.resolvedAdbSerial();
                                if (serial !== "")
                                    AndroidConnect.runAdbKeyevent(serial, 187);

                            }

                            Behavior on Layout.preferredWidth {
                                NumberAnimation {
                                    duration: 300
                                    easing.type: Easing.InOutCubic
                                }

                            }

                            Behavior on Layout.preferredHeight {
                                NumberAnimation {
                                    duration: 300
                                    easing.type: Easing.InOutCubic
                                }

                            }

                        }

                        // Android navigation buttons
                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 16

                            // Back
                            RippleButton {
                                implicitWidth: 44
                                implicitHeight: 44
                                buttonRadius: Appearance.rounding.full
                                colBackground: Appearance.colors.colLayer1
                                onClicked: {
                                    let serial = AndroidConnect.resolvedAdbSerial();
                                    if (serial !== "")
                                        AndroidConnect.runAdbKeyevent(serial, 4);

                                }

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "arrow_back"
                                    iconSize: 22
                                    color: Appearance.colors.colOnLayer1
                                }

                            }

                            // Home
                            RippleButton {
                                implicitWidth: 52
                                implicitHeight: 52
                                buttonRadius: Appearance.rounding.full
                                colBackground: Appearance.colors.colLayer2
                                onClicked: {
                                    let serial = AndroidConnect.resolvedAdbSerial();
                                    if (serial !== "")
                                        AndroidConnect.runAdbKeyevent(serial, 3);

                                }

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "circle"
                                    iconSize: 26
                                    color: Appearance.colors.colOnLayer2
                                }

                            }

                            // Recents
                            RippleButton {
                                implicitWidth: 44
                                implicitHeight: 44
                                buttonRadius: Appearance.rounding.full
                                colBackground: Appearance.colors.colLayer1
                                onClicked: {
                                    let serial = AndroidConnect.resolvedAdbSerial();
                                    if (serial !== "")
                                        AndroidConnect.runAdbKeyevent(serial, 187);

                                }

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "crop_square"
                                    iconSize: 22
                                    color: Appearance.colors.colOnLayer1
                                }

                            }

                        }

                    }

                    // Right: Device info + action buttons
                    ColumnLayout {
                        Layout.fillHeight: true
                        Layout.preferredWidth: root.infoColumnWidth
                        Layout.alignment: Qt.AlignTop
                        spacing: 16

                        // ---- Battery ----
                        ColumnLayout {
                            spacing: 2
                            visible: root.batteryValue >= 0

                            RowLayout {
                                spacing: 6

                                MaterialSymbol {
                                    text: root.isCharging ? "battery_charging_full" : (root.batteryValue <= 20 ? "battery_alert" : "battery_full")
                                    iconSize: 18
                                    color: Appearance.colors.colSubtext
                                }

                                StyledText {
                                    text: qsTr("Battery")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colSubtext
                                }

                            }

                            StyledText {
                                text: root.batteryValue + "%"
                                font.pixelSize: Appearance.font.pixelSize.huge
                                font.weight: Font.Bold
                                font.features: {
                                    "tnum": 1
                                }
                                color: root.batteryValue <= 20 ? Appearance.colors.colError : Appearance.colors.colOnLayer0
                            }

                        }

                        // ---- Network ----
                        ColumnLayout {
                            spacing: 2

                            RowLayout {
                                spacing: 6

                                MaterialSymbol {
                                    text: root.isAirplaneMode ? (root.wifiSsid !== "" ? "wifi" : "airplanemode_active") : "signal_cellular_alt"
                                    iconSize: 18
                                    color: Appearance.colors.colSubtext
                                }

                                StyledText {
                                    text: qsTr("Network")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colSubtext
                                }

                            }

                            StyledText {
                                text: root.networkType
                                font.pixelSize: Appearance.font.pixelSize.huge
                                font.weight: Font.Bold
                                color: Appearance.colors.colOnLayer0
                                elide: Text.ElideRight
                                Layout.maximumWidth: root.infoColumnWidth - 32
                            }

                        }

                        // ---- Signal ----
                        ColumnLayout {
                            spacing: 2

                            RowLayout {
                                spacing: 6

                                MaterialSymbol {
                                    text: root.signalIcon
                                    iconSize: 18
                                    color: Appearance.colors.colSubtext
                                }

                                StyledText {
                                    text: root.isAirplaneMode ? qsTr("Radio") : qsTr("Signal")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colSubtext
                                }

                            }

                            StyledText {
                                text: root.signalText
                                font.pixelSize: Appearance.font.pixelSize.huge
                                font.weight: Font.Bold
                                color: Appearance.colors.colOnLayer0
                            }

                        }

                        // Spacer
                        Item {
                            Layout.fillHeight: true
                        }

                        // ---- Quick Action Buttons ----
                        RowLayout {
                            Layout.alignment: Qt.AlignLeft
                            spacing: 5

                            // Screenshot
                            RippleButton {
                                implicitWidth: 36
                                implicitHeight: 36
                                buttonRadius: Appearance.rounding.normal
                                colBackground: Appearance.colors.colLayer1
                                onClicked: {
                                    let serial = AndroidConnect.resolvedAdbSerial();
                                    if (serial !== "")
                                        AndroidConnect.takeAdbScreenshot(serial);

                                }

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "photo_camera"
                                    iconSize: 18
                                    color: Appearance.colors.colOnLayer1
                                }

                                StyledToolTip {
                                    text: qsTr("Take screenshot")
                                }
                            }

                            // Screen recording
                            RippleButton {
                                implicitWidth: 36
                                implicitHeight: 36
                                buttonRadius: Appearance.rounding.normal
                                colBackground: AndroidConnect.adbScreenRecordingActive ? Appearance.colors.colError : Appearance.colors.colLayer1
                                onClicked: {
                                    let serial = AndroidConnect.resolvedAdbSerial();
                                    if (serial !== "") {
                                        if (AndroidConnect.adbScreenRecordingActive)
                                            AndroidConnect.stopAdbScreenRecording();
                                        else
                                            AndroidConnect.startAdbScreenRecording(serial);
                                    }
                                }

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: AndroidConnect.adbScreenRecordingActive ? "stop" : "videocam"
                                    iconSize: 18
                                    color: AndroidConnect.adbScreenRecordingActive ? Appearance.colors.colOnError : Appearance.colors.colOnLayer1
                                }

                                StyledToolTip {
                                    text: AndroidConnect.adbScreenRecordingActive ? qsTr("Stop recording") : qsTr("Start screen recording")
                                }
                            }

                            // Keep awake / Always On Display (Never auto lock)
                            RippleButton {
                                id: keepAwakeBtn

                                implicitWidth: 36
                                implicitHeight: 36
                                buttonRadius: Appearance.rounding.normal
                                colBackground: AndroidConnect.keepAwakeActive ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer1
                                onClicked: {
                                    let serial = AndroidConnect.resolvedAdbSerial();
                                    if (serial !== "")
                                        AndroidConnect.toggleKeepAwake(serial);

                                }

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: AndroidConnect.keepAwakeActive ? "alarm_on" : "nightlight"
                                    iconSize: 18
                                    color: AndroidConnect.keepAwakeActive ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
                                }

                                StyledToolTip {
                                    text: AndroidConnect.keepAwakeActive ? qsTr("Always On Display: Active (Never locks)") : qsTr("Always On Display: Inactive (Click to keep awake)")
                                }
                            }

                            // Turn physical phone screen off / on
                            RippleButton {
                                id: screenPowerBtn

                                implicitWidth: 36
                                implicitHeight: 36
                                buttonRadius: Appearance.rounding.normal
                                colBackground: AndroidConnect.physicalScreenOff ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer1
                                onClicked: {
                                    let serial = AndroidConnect.resolvedAdbSerial();
                                    if (serial !== "")
                                        AndroidConnect.togglePhysicalScreen(serial);
                                }

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: AndroidConnect.physicalScreenOff ? "visibility_off" : "visibility"
                                    iconSize: 18
                                    color: AndroidConnect.physicalScreenOff ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
                                }

                                StyledToolTip {
                                    text: AndroidConnect.physicalScreenOff ? qsTr("Phone screen is OFF (saving power) - Click to turn ON") : qsTr("Turn physical phone screen OFF")
                                }
                            }

                            // Embedded mirror toggle
                            RippleButton {
                                implicitWidth: 36
                                implicitHeight: 36
                                buttonRadius: Appearance.rounding.normal
                                colBackground: AndroidConnect.scrcpyRunning ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer1
                                onClicked: {
                                    if (AndroidConnect.scrcpyRunning) {
                                        root.userStoppedMirror = true;
                                        AndroidConnect.stopScrcpySession();
                                    } else {
                                        root.userStoppedMirror = false;
                                        let serial = AndroidConnect.resolvedAdbSerial();
                                        if (serial !== "")
                                            AndroidConnect.launchScrcpySession(serial);

                                    }
                                }

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: AndroidConnect.scrcpyRunning ? "screen_share" : "power_settings_new"
                                    iconSize: 18
                                    color: AndroidConnect.scrcpyRunning ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
                                }

                                StyledToolTip {
                                    text: AndroidConnect.scrcpyRunning ? qsTr("Stop embedded mirror") : qsTr("Start embedded mirror")
                                }
                            }

                            // Standalone floating window popout
                            RippleButton {
                                implicitWidth: 36
                                implicitHeight: 36
                                buttonRadius: Appearance.rounding.normal
                                colBackground: AndroidConnect.directScrcpyRunning ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer1
                                onClicked: {
                                    AndroidConnect.toggleDirectScrcpy();
                                }

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "desktop_windows"
                                    iconSize: 18
                                    color: AndroidConnect.directScrcpyRunning ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                                }

                                StyledToolTip {
                                    text: qsTr("Open standalone mirror window")
                                }
                            }

                            // QR Pairing button
                            RippleButton {
                                implicitWidth: 36
                                implicitHeight: 36
                                buttonRadius: Appearance.rounding.normal
                                colBackground: Appearance.colors.colLayer1
                                onClicked: {
                                    GlobalStates.settingsPage = "Android:Wireless ADB";
                                    GlobalStates.settingsOpen = true;
                                    AndroidConnect.startQrPairing();
                                }

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "qr_code_scanner"
                                    iconSize: 18
                                    color: Appearance.colors.colOnLayer1
                                }

                                StyledToolTip {
                                    text: qsTr("Pair device with QR code")
                                }
                            }

                            // Settings (opens settings page)
                            RippleButton {
                                implicitWidth: 36
                                implicitHeight: 36
                                buttonRadius: Appearance.rounding.normal
                                colBackground: Appearance.colors.colLayer1
                                onClicked: {
                                    GlobalStates.settingsPage = "Android";
                                    GlobalStates.settingsOpen = true;
                                }

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "settings"
                                    iconSize: 18
                                    color: Appearance.colors.colOnLayer1
                                }

                                StyledToolTip {
                                    text: qsTr("Open Android settings")
                                }
                            }
                        }

                    }

                }

            }

            Behavior on opacity {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutCubic
                }

            }

            Behavior on scale {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutCubic
                }

            }

        }

    }

    IpcHandler {
        function toggle() {
            GlobalStates.androidConnectOpen = !GlobalStates.androidConnectOpen;
            if (GlobalStates.androidConnectOpen) {
                if (root.hasDevice && !AndroidConnect.scrcpyRunning && !AndroidConnect.scrcpyLaunching && !AndroidConnect.directScrcpyRunning && !root.userStoppedMirror)
                    autoStartTimer.restart();
            }
        }

        function open() {
            GlobalStates.androidConnectOpen = true;
            if (root.hasDevice && !AndroidConnect.scrcpyRunning && !AndroidConnect.scrcpyLaunching && !AndroidConnect.directScrcpyRunning && !root.userStoppedMirror)
                autoStartTimer.restart();
        }

        function pin() {
            root.isPinned = true;
            GlobalFocusGrab.removeDismissable(panelWindow);
        }

        function unpin() {
            root.isPinned = false;
            GlobalFocusGrab.addDismissable(panelWindow);
        }

        function close() {
            GlobalStates.androidConnectOpen = false;
        }

        function startMirror() {
            AndroidConnect.launchDirectScrcpy();
        }

        function stopMirror() {
            AndroidConnect.stopDirectScrcpy();
        }

        function toggleMirror() {
            AndroidConnect.toggleDirectScrcpy();
        }

        function selectDevice(serial: string) {
            AndroidConnect.selectDevice(serial);
        }

        function restartEmbeddedMirror() {
            root.userStoppedMirror = false;
            AndroidConnect.restartScrcpySession();
        }

        function toggleEmbeddedMirror() {
            if (AndroidConnect.scrcpyRunning) {
                root.userStoppedMirror = true;
                AndroidConnect.stopScrcpySession();
            } else {
                root.userStoppedMirror = false;
                let serial = AndroidConnect.resolvedAdbSerial();
                if (serial !== "")
                    AndroidConnect.launchScrcpySession(serial);
            }
        }

        function startQrPair() {
            GlobalStates.settingsPage = "Android:Wireless ADB";
            GlobalStates.settingsOpen = true;
            AndroidConnect.startQrPairing();
        }

        function stopQrPair() {
            AndroidConnect.stopQrPairing();
        }

        function toggleKeepAwake() {
            AndroidConnect.toggleKeepAwake();
        }

        function togglePhysicalScreen() {
            AndroidConnect.togglePhysicalScreen();
        }

        function openDeviceMenu() {
            deviceMenuPopup.open();
        }

        target: "androidConnect"
    }

    CompositorGlobalShortcut {
        name: "androidConnectToggle"
        description: "Toggles Android Connect panel"
        onPressed: GlobalStates.androidConnectOpen = !GlobalStates.androidConnectOpen
    }

}
