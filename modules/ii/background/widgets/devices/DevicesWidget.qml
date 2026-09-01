import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Io
import Quickshell
import Quickshell.Wayland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root
    configEntryName: "devices"
    hoverEnabled: true

    property string sizeMode: root.configEntry.sizeMode ?? "2x2"

    implicitWidth: sizeMode === "1x4" ? 400 : 276
    implicitHeight: sizeMode === "1x4" ? 120 : 252

    Behavior on implicitWidth {
        NumberAnimation {
            duration: 250
            easing.type: Easing.InOutQuad
        }
    }
    Behavior on implicitHeight {
        NumberAnimation {
            duration: 250
            easing.type: Easing.InOutQuad
        }
    }

    property var devicesList: []
    property list<string> deviceErrors: []
    property bool loading: true
    property bool allDevicesOpen: false
    readonly property int activeWorkspaceId: WM.activeWorkspaceForMonitor(root.QsWindow?.screen?.name ?? "")?.id ?? 0

    onActiveWorkspaceIdChanged: root.allDevicesOpen = false

    Connections {
        target: WM
        function onActiveWorkspaceChanged() { root.allDevicesOpen = false }
    }

    function batteryColor(dev) {
        if (!dev.connected)
            return ColorUtils.mix(Appearance.colors.colOnPrimaryContainer, Appearance.colors.colPrimaryContainer, 0.4);
        if (dev.charging)
            return "#39d353";
        if (dev.battery !== null && dev.battery < 20)
            return "#f44336";
        if (dev.battery !== null && dev.battery < 40)
            return "#ffb300";
        return Appearance.colors.colOnPrimaryContainer;
    }

    function refreshDevices() {
        if (devicesProc.running) {
            devicesProc.running = false;
        }
        devicesProc.running = true;
    }

    function getDeviceIcon(type) {
        switch (type) {
        case "mouse":
            return "mouse";
        case "keyboard":
            return "keyboard";
        case "touchpad":
            return "trackpad";
        case "headphone":
            return "headphones";
        case "phone":
            return "smartphone";
        case "tablet":
            return "tablet";
        case "laptop":
            return "laptop";
        default:
            return "devices_other";
        }
    }

    function getDeviceSubtitle(dev) {
        if (!dev.connected)
            return "Disconnected";
        if (dev.charging)
            return "Charging • Main Station";
        if (dev.battery !== null) {
            if (dev.battery < 20)
                return "Battery Low";
            return "Connected • Active";
        }
        return "Connected • System";
    }

    function getDeviceColor(connected, battery, charging) {
        if (!connected) {
            return ColorUtils.mix(Appearance.colors.colOnPrimaryContainer, Appearance.colors.colPrimaryContainer, 0.4);
        }
        if (charging) {
            return "#39d353"; // Green when charging
        }
        if (battery !== null) {
            return battery < 20 ? "#f44336" : Appearance.colors.colOnPrimaryContainer;
        }
        return Appearance.colors.colOnPrimaryContainer;
    }

    Process {
        id: devicesProc
        command: ["python3", Quickshell.shellPath("scripts/devices/get_devices.py")]
        running: true
        stdout: StdioCollector {
            id: devicesOutputCollector
            onStreamFinished: {
                const output = devicesOutputCollector.text.trim();
                if (output) {
                    try {
                        const parsed = JSON.parse(output);
                        root.devicesList = Array.isArray(parsed) ? parsed : (parsed.devices ?? []);
                        root.deviceErrors = Array.isArray(parsed) ? [] : (parsed.errors ?? []);
                    } catch (e) {
                        root.deviceErrors = ["Unable to read device data"];
                        console.log("[DevicesWidget] Error parsing JSON:", e);
                    }
                } else {
                    root.deviceErrors = ["Device services unavailable"];
                }
                root.loading = false;
            }
        }
    }

    // Instant update trigger using dbus-monitor/udevadm background listener
    Process {
        id: triggerProc
        command: ["python3", Quickshell.shellPath("scripts/devices/monitor_trigger.py")]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                triggerProc.running = false;
                refreshDelayTimer.start();
            }
        }
    }

    Timer {
        id: refreshDelayTimer
        interval: 350
        repeat: false
        onTriggered: {
            root.refreshDevices();
            triggerProc.running = true;
        }
    }

    Timer {
        id: refreshTimer
        interval: 30000
        running: true
        repeat: true
        onTriggered: refreshDevices()
    }

    Component.onCompleted: {
        refreshDevices();
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: Appearance.rounding?.verylarge ?? 24
        color: Appearance.colors.colPrimaryContainer // Matched to World Clock base

        StyledRectangularShadow {
            target: card
            z: -2
        }

        // Layout for 2x2 Mode (Android M3 Vertical Rows List style)
        ColumnLayout {
            visible: root.sizeMode === "2x2"
            anchors {
                fill: parent
                margins: 14
            }
            spacing: 10

            // Header Row
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                MaterialSymbol {
                    text: "devices"
                    iconSize: 18
                    color: Appearance.colors.colOnPrimaryContainer // Changed to contrast primary
                    opacity: 0.6 // Matched to location icon opacity in Clock
                }

                StyledText {
                    text: "Devices"
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnPrimaryContainer
                    Layout.fillWidth: true
                }

                StyledText {
                    text: root.devicesList.length > 0 ? root.devicesList.length : ""
                    font.pixelSize: 11
                    color: Appearance.colors.colOnPrimaryContainer
                    opacity: 0.7
                }

                Rectangle {
                    width: 24
                    height: 24
                    radius: 12
                    color: allDevicesArea.containsMouse ? Appearance.colors.colPrimary : "transparent"
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "list"
                        iconSize: 16
                        color: allDevicesArea.containsMouse ? Appearance.colors.colOnPrimary : Appearance.colors.colOnPrimaryContainer
                    }
                    MouseArea {
                        id: allDevicesArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.allDevicesOpen = !root.allDevicesOpen
                    }
                }

                Rectangle {
                    width: 24
                    height: 24
                    radius: 12
                    color: refreshArea.containsMouse ? Appearance.colors.colPrimary : "transparent"
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "refresh"
                        iconSize: 16
                        color: refreshArea.containsMouse ? Appearance.colors.colOnPrimary : Appearance.colors.colOnPrimaryContainer
                    }
                    MouseArea {
                        id: refreshArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.refreshDevices()
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                MaterialLoadingIndicator {
                    anchors.centerIn: parent
                    visible: root.loading && root.devicesList.length === 0
                    loading: root.loading
                }

                StyledText {
                    anchors.centerIn: parent
                    text: root.deviceErrors.length > 0 ? root.deviceErrors[0] : "No devices detected"
                    font.pixelSize: 12
                    color: Appearance.colors.colOnPrimaryContainer
                    opacity: 0.7
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    visible: !root.loading && root.devicesList.length === 0
                }

                // Vertical Device Items List
                ColumnLayout {
                    anchors.fill: parent
                    spacing: 10
                    visible: !root.loading && root.devicesList.length > 0

                    Repeater {
                        model: root.devicesList.slice(0, 3)
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 12

                            // Battery Progress Ring with Center Icon
                            Item {
                                width: 42
                                height: 42

                                CircularProgress {
                                    id: progress
                                    anchors.centerIn: parent
                                    implicitSize: 42
                                    lineWidth: 4
                                    value: modelData.connected ? (modelData.battery !== null ? modelData.battery / 100 : 1.0) : 1.0
                                    gapAngle: 0
                                    colPrimary: root.batteryColor(modelData)
                                    colSecondary: ColorUtils.mix(Appearance.colors.colOnPrimaryContainer, Appearance.colors.colPrimaryContainer, 0.12)
                                }

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: modelData.charging ? "bolt" : root.getDeviceIcon(modelData.type)
                                    iconSize: 16
                                    color: root.batteryColor(modelData)
                                }
                            }

                            // Device Title & Subtitle
                            ColumnLayout {
                                spacing: 1
                                Layout.fillWidth: true

                                StyledText {
                                    text: modelData.name
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    color: Appearance.colors.colOnPrimaryContainer
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }

                            StyledText {
                                text: root.getDeviceSubtitle(modelData) + " • " + (modelData.connection ?? "unknown")
                                font.pixelSize: 11
                                    color: Appearance.colors.colOnPrimaryContainer
                                    opacity: 0.7 // Imitating colSubtext against primary
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }
                            }

                            // Battery Percentage Text
                            StyledText {
                                text: modelData.battery !== null ? modelData.battery + "%" : (modelData.connected ? "On" : "Off")
                                font.pixelSize: 13
                                font.weight: Font.Medium
                                color: modelData.battery !== null && modelData.battery < 20 ? "#f44336" : Appearance.colors.colOnPrimaryContainer
                            }
                        }
                    }
                }
            }
        }

        // Layout for 1x4 Horizontal Mode (Resized & Optimized)
        RowLayout {
            visible: root.sizeMode === "1x4"
            anchors {
                fill: parent
                margins: 14
            }
            spacing: 12

            // Compact Header Icon on the left
            MaterialSymbol {
                text: "devices"
                iconSize: 22
                color: Appearance.colors.colOnPrimaryContainer
                opacity: 0.6
            }

            Rectangle {
                width: 28
                height: 28
                radius: 14
                color: allDevicesArea1x4.containsMouse ? Appearance.colors.colPrimary : "transparent"

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "list"
                    iconSize: 20
                    color: allDevicesArea1x4.containsMouse ? Appearance.colors.colOnPrimary : Appearance.colors.colOnPrimaryContainer
                    opacity: 0.8
                }

                MouseArea {
                    id: allDevicesArea1x4
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.allDevicesOpen = !root.allDevicesOpen
                }
            }

            Rectangle {
                width: 28
                height: 28
                radius: 14
                color: refreshArea1x4.containsMouse ? Appearance.colors.colPrimary : "transparent"

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "refresh"
                    iconSize: 20
                    color: refreshArea1x4.containsMouse ? Appearance.colors.colOnPrimary : Appearance.colors.colOnPrimaryContainer
                    opacity: 0.8
                }

                MouseArea {
                    id: refreshArea1x4
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.refreshDevices()
                }
            }

            StyledText {
                text: root.devicesList.length > 0 ? root.devicesList.length : ""
                font.pixelSize: 11
                color: Appearance.colors.colOnPrimaryContainer
                opacity: 0.7
            }

            // Divider Line
            Rectangle {
                width: 1
                Layout.fillHeight: true
                Layout.topMargin: 4
                Layout.bottomMargin: 4
                color: Appearance.colors.colOnPrimaryContainer
                opacity: 0.2
            }

            // Expanded Horizontal Devices Row
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                Repeater {
                    model: root.devicesList.slice(0, 3)
                    delegate: Item {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.minimumWidth: 48
                        Layout.fillHeight: true

                        // Circular Progress Ring
                        Item {
                            Layout.alignment: Qt.AlignHCenter
                            width: 42
                            height: 42
                            anchors.centerIn: parent

                            CircularProgress {
                                anchors.centerIn: parent
                                implicitSize: 42
                                lineWidth: 4
                                value: modelData.connected ? (modelData.battery !== null ? modelData.battery / 100 : 1.0) : 1.0
                                gapAngle: 0
                                colPrimary: root.batteryColor(modelData)
                                colSecondary: ColorUtils.mix(Appearance.colors.colOnPrimaryContainer, Appearance.colors.colPrimaryContainer, 0.12)
                            }

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: modelData.charging ? "bolt" : root.getDeviceIcon(modelData.type)
                                iconSize: 16
                                color: root.batteryColor(modelData)
                            }
                        }
                    }
                }
            }
        }

        // Resize Handle in bottom right corner
        Rectangle {
            id: resizeHandle
            width: 14
            height: 14
            radius: 3
            color: Appearance.colors.colOnPrimaryContainer
            anchors {
                right: card.right
                bottom: card.bottom
                margins: 4
            }
            opacity: (root.containsMouse || resizeArea.containsMouse || resizeArea.pressed) ? 0.4 : 0
            visible: opacity > 0 && !Config.options.background.widgetsLocked
            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                }
            }

            MouseArea {
                id: resizeArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.SizeHorCursor
                preventStealing: true
                property real startWidth: 0
                property real startX: 0
                onPressed: mouse => {
                    startWidth = root.width;
                    startX = mapToItem(null, mouse.x, mouse.y).x;
                }
                onPositionChanged: mouse => {
                    if (!pressed)
                        return;
                    var globalX = mapToItem(null, mouse.x, mouse.y).x;
                    var dx = globalX - startX;
                    var newW = startWidth + dx;

                    if (newW > 338) {
                        root.sizeMode = "1x4";
                    } else {
                        root.sizeMode = "2x2";
                    }
                }
                onReleased: {
                    root.configEntry.sizeMode = root.sizeMode;
                }
            }
        }
    }

    PanelWindow {
        id: allDevicesPopup
        visible: root.allDevicesOpen
        screen: root.QsWindow?.screen ?? null
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell:popup:devices"
        property real popupX: root.x + root.width / 2 - implicitWidth / 2
        property real popupY: root.y + root.height + 10
        anchors { left: true; top: true }
        margins {
            left: Math.max(10, Math.min(popupX, (root.QsWindow?.screen?.width ?? 1920) - implicitWidth - 10))
            top: Math.max(10, Math.min(popupY, (root.QsWindow?.screen?.height ?? 1080) - implicitHeight - 10))
        }
        implicitWidth: 330
        // Keep a usable viewport for the list instead of deriving the popup
        // height from a fill-height Flickable.
        implicitHeight: Math.min(520, 150 + Math.max(1, root.devicesList.length) * 60)

        StyledRectangularShadow { target: allDevicesBackground }

        Rectangle {
            id: allDevicesBackground
            anchors.fill: parent
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer1Base
            border.width: 1
            border.color: Appearance.colors.colLayer0Border

            MouseArea { anchors.fill: parent }

            ColumnLayout {
                id: allDevicesColumn
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    MaterialSymbol {
                        text: "devices_other"
                        iconSize: 20
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                    StyledText {
                        text: "All Devices (" + root.devicesList.length + ")"
                        font.pixelSize: 16
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnPrimaryContainer
                        Layout.fillWidth: true
                    }
                    MaterialSymbol {
                        text: "close"
                        iconSize: 18
                        color: Appearance.colors.colOnPrimaryContainer
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.allDevicesOpen = false
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Appearance.colors.colOnPrimaryContainer
                    opacity: 0.12
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.devicesList.length === 0 ? "No devices detected" : "Showing all " + root.devicesList.length + " devices"
                    font.pixelSize: 11
                    color: Appearance.colors.colOnPrimaryContainer
                    opacity: 0.65
                }

                StyledFlickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 54
                    contentWidth: width
                    contentHeight: allDevicesList.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical.policy: ScrollBar.AlwaysOn

                    ColumnLayout {
                        id: allDevicesList
                        width: parent.width
                        spacing: 6

                        Repeater {
                            model: root.devicesList
                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 54
                                radius: Appearance.rounding.normal
                                color: deviceRowArea.containsMouse ? Appearance.colors.colLayer2 : "transparent"

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    spacing: 10

                                    MaterialSymbol {
                                        text: modelData.charging ? "bolt" : root.getDeviceIcon(modelData.type)
                                        iconSize: 22
                                        color: root.batteryColor(modelData)
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1
                                        StyledText {
                                            text: modelData.name
                                            font.pixelSize: 13
                                            font.weight: Font.Medium
                                            color: Appearance.colors.colOnPrimaryContainer
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                        StyledText {
                                            text: (modelData.connection ?? "unknown") + " • " + (modelData.connected ? "Connected" : "Disconnected")
                                            font.pixelSize: 11
                                            color: Appearance.colors.colOnPrimaryContainer
                                            opacity: 0.65
                                        }
                                    }

                                    StyledText {
                                        text: modelData.battery !== null ? modelData.battery + "%" : (modelData.charging ? "Charging" : (modelData.connected ? "On" : "Off"))
                                        font.pixelSize: 12
                                        color: root.batteryColor(modelData)
                                    }
                                }

                                MouseArea {
                                    id: deviceRowArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
