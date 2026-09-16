import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: page
    forceWidth: true

    property string statusText: ""
    property bool statusSuccess: true
    property bool copySuccess: false

    Connections {
        target: AndroidConnect
        function onWirelessAdbFinished(success, message) {
            page.statusSuccess = success;
            page.statusText = message;
            statusResetTimer.restart();
        }
    }

    Timer {
        id: statusResetTimer
        interval: 8000
        repeat: false
        onTriggered: page.statusText = ""
    }

    Timer {
        id: copyTimer
        interval: 2500
        repeat: false
        onTriggered: page.copySuccess = false
    }

    Process {
        id: copyProc
        command: ["wl-copy", ""]
    }

    function goTo(term) {
        const t = term.toLowerCase().trim()

        function findTarget(rootItem) {
            for (let i = 0; i < rootItem.children.length; i++) {
                let child = rootItem.children[i]
                if (child.title && child.title.toLowerCase().includes(t)) {
                    return child
                }
            }

            for (let i = 0; i < rootItem.children.length; i++) {
                let found = findTarget(rootItem.children[i])
                if (found) return found
            }
            return null
        }

        let target = findTarget(mainLayout)
        if (target) {
            let pos = target.mapToItem(mainLayout, 0, 0)
            page.contentY = Math.max(0, pos.y - 0)
        }
    }

    ColumnLayout {
        id: mainLayout
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 20

        // ==========================================
        // 1. GENERAL SECTION
        // ==========================================
        ContentSection {
            icon: "smartphone"
            shape: MaterialShape.Shape.ClamShell
            title: Translation.tr("General")

            // Connected Device Status Card
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: deviceRow.implicitHeight + 20
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1
                border.width: 1
                border.color: Appearance.colors.colLayer0Border

                RowLayout {
                    id: deviceRow
                    anchors {
                        fill: parent
                        leftMargin: 16
                        rightMargin: 16
                        topMargin: 10
                        bottomMargin: 10
                    }
                    spacing: 14

                    MaterialSymbol {
                        text: (AndroidConnect.anyDevicesConnected || AndroidConnect.adbConnectedSerials.length > 0) ? "phone_android" : "phonelink_off"
                        iconSize: Appearance.font.pixelSize.huge
                        color: (AndroidConnect.anyDevicesConnected || AndroidConnect.adbConnectedSerials.length > 0) ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            text: {
                                if (AndroidConnect.mainDevice && AndroidConnect.mainDevice.name)
                                    return AndroidConnect.mainDevice.name;
                                if (AndroidConnect.adbConnectedSerials.length > 0)
                                    return AndroidConnect.adbConnectedSerials[0];
                                return Translation.tr("No device connected");
                            }
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnLayer1
                        }

                        StyledText {
                            text: {
                                if (AndroidConnect.adbHasUsbTransport)
                                    return Translation.tr("Connected via USB");
                                if (AndroidConnect.adbConnectedSerials.length > 0)
                                    return Translation.tr("Connected via Wireless ADB");
                                if (AndroidConnect.mainDevice && AndroidConnect.mainDevice.paired)
                                    return Translation.tr("Paired via KDE Connect");
                                return Translation.tr("Plug in USB or pair via Wireless ADB / KDE Connect");
                            }
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }

                    RippleButtonWithIcon {
                        materialIcon: "refresh"
                        mainText: Translation.tr("Refresh")
                        colBackground: Appearance.colors.colLayer2
                        onClicked: {
                            AndroidConnect.refreshDevices();
                            AndroidConnect.refreshAdbDevices();
                        }
                    }
                }
            }

            GroupedList {
                ConfigSwitch {
                    buttonIcon: "toggle_on"
                    text: Translation.tr("Enable Android Connect")
                    checked: Config.options.androidConnect.enable
                    onCheckedChanged: { Config.options.androidConnect.enable = checked; }
                }
                ConfigSwitch {
                    buttonIcon: "visibility_off"
                    text: Translation.tr("Hide bar widget when no device connected")
                    checked: Config.options.androidConnect.hideBarIfNoDevice
                    onCheckedChanged: { Config.options.androidConnect.hideBarIfNoDevice = checked; }
                }
            }
        }

        // ==========================================
        // 2. MIRROR SECTION
        // ==========================================
        ContentSection {
            icon: "screen_share"
            shape: MaterialShape.Shape.Cookie6Sided
            title: Translation.tr("Mirror")

            GroupedList {
                ConfigSelectionArray {
                    text: Translation.tr("Phone size")
                    icon: "aspect_ratio"
                    currentValue: Config.options.androidConnect.phoneSizePresetIndex
                    onSelected: newValue => { Config.options.androidConnect.phoneSizePresetIndex = newValue; }
                    options: [
                        { displayName: Translation.tr("Small"),   icon: "zoom_out",     value: 0 },
                        { displayName: Translation.tr("Medium"),  icon: "crop_free",    value: 1 },
                        { displayName: Translation.tr("Large"),   icon: "zoom_in",      value: 2 }
                    ]
                }
                ConfigSelectionArray {
                    text: Translation.tr("Max resolution")
                    icon: "photo_size_select_large"
                    currentValue: Config.options.androidConnect.mirrorMaxSize
                    onSelected: newValue => { Config.options.androidConnect.mirrorMaxSize = newValue; }
                    options: [
                        { displayName: "720p",   icon: "photo_size_select_small",  value: 720 },
                        { displayName: "960p",   icon: "aspect_ratio",             value: 960 },
                        { displayName: "1200p",  icon: "hd",                       value: 1200 },
                        { displayName: "1440p",  icon: "2k",                       value: 1440 }
                    ]
                }
                ConfigSelectionArray {
                    text: Translation.tr("Video bitrate")
                    icon: "speed"
                    currentValue: Config.options.androidConnect.mirrorBitrateMbps
                    onSelected: newValue => { Config.options.androidConnect.mirrorBitrateMbps = newValue; }
                    options: [
                        { displayName: "6 Mbps",   icon: "speed",  value: 6 },
                        { displayName: "12 Mbps",  icon: "speed",  value: 12 },
                        { displayName: "16 Mbps",  icon: "speed",  value: 16 },
                        { displayName: "24 Mbps",  icon: "speed",  value: 24 }
                    ]
                }
                ConfigSelectionArray {
                    text: Translation.tr("Framerate")
                    icon: "motion_mode"
                    currentValue: Config.options.androidConnect.mirrorMaxFps
                    onSelected: newValue => { Config.options.androidConnect.mirrorMaxFps = newValue; }
                    options: [
                        { displayName: "30 fps",  icon: "slow_motion_video",  value: 30 },
                        { displayName: "60 fps",  icon: "fast_forward",        value: 60 }
                    ]
                }
                ConfigSwitch {
                    buttonIcon: "volume_up"
                    text: Translation.tr("Mirror audio from phone")
                    checked: Config.options.androidConnect.embeddedMirrorAudioEnabled
                    onCheckedChanged: { Config.options.androidConnect.embeddedMirrorAudioEnabled = checked; }
                }
                ConfigSwitch {
                    buttonIcon: "alarm_on"
                    text: Translation.tr("Never auto-lock phone (Always On)")
                    checked: Config.options.androidConnect.keepPhoneAwake
                    onCheckedChanged: {
                        Config.options.androidConnect.keepPhoneAwake = checked;
                        let serial = AndroidConnect.resolvedAdbSerial();
                        if (serial !== "") {
                            AndroidConnect.setKeepAwake(serial, checked);
                        }
                    }
                }
                ConfigSwitch {
                    buttonIcon: "visibility_off"
                    text: Translation.tr("Turn off phone screen when mirrored")
                    checked: Config.options.androidConnect.turnOffScreenOnMirror
                    onCheckedChanged: {
                        Config.options.androidConnect.turnOffScreenOnMirror = checked;
                        let serial = AndroidConnect.resolvedAdbSerial();
                        if (serial !== "" && AndroidConnect.scrcpyRunning) {
                            AndroidConnect.setPhysicalScreenPower(serial, !checked);
                        }
                    }
                }
            }
        }

        // ==========================================
        // 3. WIRELESS ADB SECTION
        // ==========================================
        ContentSection {
            icon: "wifi"
            shape: MaterialShape.Shape.Gem
            title: Translation.tr("Wireless ADB")

            // QR Code Pairing Card
            Rectangle {
                Layout.fillWidth: true
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
                implicitHeight: qrCardLayout.implicitHeight + 28

                ColumnLayout {
                    id: qrCardLayout
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: 14
                    }
                    spacing: 14

                    // Header row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        MaterialSymbol {
                            text: "qr_code_scanner"
                            iconSize: Appearance.font.pixelSize.huge
                            color: Appearance.colors.colPrimary
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            StyledText {
                                text: Translation.tr("Pair Device with QR Code")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.Bold
                                color: Appearance.colors.colOnLayer1
                            }

                            StyledText {
                                text: (AndroidConnect.qrPairingActive || AndroidConnect.qrImagePath !== "")
                                    ? Translation.tr("Open Wireless debugging > \"Pair device with QR code\" on your phone and scan.")
                                    : Translation.tr("Fast, one-step pairing. Scan QR code directly from your phone's Wireless debugging settings.")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }
                        }

                        RippleButtonWithIcon {
                            visible: !AndroidConnect.qrPairingActive && AndroidConnect.qrImagePath === ""
                            materialIcon: "qr_code_2"
                            mainText: Translation.tr("Pair with QR Code")
                            colBackground: Appearance.colors.colPrimaryContainer
                            onClicked: {
                                AndroidConnect.startQrPairing();
                            }
                        }

                        RowLayout {
                            visible: AndroidConnect.qrPairingActive || AndroidConnect.qrImagePath !== ""
                            spacing: 8

                            RippleButtonWithIcon {
                                materialIcon: "refresh"
                                mainText: Translation.tr("Regenerate")
                                colBackground: Appearance.colors.colLayer2
                                enabled: !AndroidConnect.wirelessAdbBusy
                                onClicked: {
                                    AndroidConnect.startQrPairing();
                                }
                            }

                            RippleButtonWithIcon {
                                materialIcon: "close"
                                mainText: Translation.tr("Close")
                                colBackground: Appearance.colors.colLayer2
                                onClicked: {
                                    AndroidConnect.stopQrPairing();
                                }
                            }
                        }
                    }

                    // QR Code and Pairing Details (Visible when active or image exists)
                    RowLayout {
                        visible: AndroidConnect.qrPairingActive || AndroidConnect.qrImagePath !== ""
                        Layout.fillWidth: true
                        spacing: 18

                        // QR Code container (clean white background for optimal camera scan contrast)
                        Rectangle {
                            width: 196
                            height: 196
                            radius: Appearance.rounding.normal
                            color: "#ffffff"
                            border.width: 1
                            border.color: Appearance.colors.colLayer0Border

                            Image {
                                id: qrCodeImg
                                anchors.centerIn: parent
                                width: 176
                                height: 176
                                fillMode: Image.PreserveAspectFit
                                smooth: false
                                cache: false
                                source: AndroidConnect.qrImagePath !== "" ? ("file://" + AndroidConnect.qrImagePath + "?t=" + AndroidConnect.qrImageTimestamp) : ""
                                visible: AndroidConnect.qrImagePath !== ""
                            }

                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 8
                                visible: AndroidConnect.qrImagePath === "" && AndroidConnect.qrPairingActive

                                MaterialLoadingIndicator {
                                    Layout.alignment: Qt.AlignHCenter
                                    implicitSize: 40
                                }

                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: Translation.tr("Generating...")
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: "#555555"
                                }
                            }
                        }

                        // Right column: Code box & Live Status
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 10

                            // 6-digit Code display
                            Rectangle {
                                Layout.fillWidth: true
                                radius: Appearance.rounding.small
                                color: Appearance.colors.colLayer2
                                border.width: 1
                                border.color: Appearance.colors.colLayer0Border
                                implicitHeight: codeBoxCol.implicitHeight + 16

                                ColumnLayout {
                                    id: codeBoxCol
                                    anchors {
                                        fill: parent
                                        margins: 10
                                    }
                                    spacing: 4

                                    StyledText {
                                        text: Translation.tr("Pairing Code (PIN)")
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colSubtext
                                    }

                                    StyledText {
                                        text: AndroidConnect.qrPairingCode !== "" ? AndroidConnect.qrPairingCode : "------"
                                        font.pixelSize: Appearance.font.pixelSize.hugeass
                                        font.weight: Font.Bold
                                        font.letterSpacing: 4
                                        font.features: { "tnum": 1 }
                                        color: Appearance.colors.colPrimary
                                    }

                                    StyledText {
                                        text: AndroidConnect.qrServiceName !== "" ? ("Service: " + AndroidConnect.qrServiceName) : ""
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: Appearance.colors.colSubtext
                                        visible: AndroidConnect.qrServiceName !== ""
                                    }
                                }
                            }

                            // Live Status Banner
                            Rectangle {
                                Layout.fillWidth: true
                                radius: Appearance.rounding.small
                                color: AndroidConnect.qrPairSuccess ? Appearance.colors.colPrimaryContainer : ((AndroidConnect.qrPairStatus.indexOf("error") !== -1 || AndroidConnect.qrPairStatus.indexOf("Timed out") !== -1) ? Appearance.colors.colErrorContainer : Appearance.colors.colLayer2)
                                border.width: 1
                                border.color: Appearance.colors.colLayer0Border
                                implicitHeight: qrStatusLayout.implicitHeight + 14

                                RowLayout {
                                    id: qrStatusLayout
                                    anchors {
                                        fill: parent
                                        margins: 10
                                    }
                                    spacing: 10

                                    MaterialSymbol {
                                        text: AndroidConnect.qrPairSuccess ? "check_circle" : (AndroidConnect.qrPairingActive ? "sync" : ((AndroidConnect.qrPairStatus.indexOf("error") !== -1 || AndroidConnect.qrPairStatus.indexOf("Timed out") !== -1) ? "error" : "info"))
                                        iconSize: Appearance.font.pixelSize.large
                                        color: AndroidConnect.qrPairSuccess ? Appearance.colors.colOnPrimaryContainer : ((AndroidConnect.qrPairStatus.indexOf("error") !== -1 || AndroidConnect.qrPairStatus.indexOf("Timed out") !== -1) ? Appearance.colors.colOnErrorContainer : Appearance.colors.colPrimary)
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: AndroidConnect.qrPairStatus !== "" ? AndroidConnect.qrPairStatus : Translation.tr("Listening for phone broadcast...")
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: AndroidConnect.qrPairSuccess ? Font.Bold : Font.Normal
                                        color: AndroidConnect.qrPairSuccess ? Appearance.colors.colOnPrimaryContainer : ((AndroidConnect.qrPairStatus.indexOf("error") !== -1 || AndroidConnect.qrPairStatus.indexOf("Timed out") !== -1) ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnLayer1)
                                        wrapMode: Text.WordWrap
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Manual Pairing Subsection
            ContentSubsection {
                title: Translation.tr("Manual Pairing (6-digit Code)")
                tooltip: Translation.tr("Pair with your device using IP address, port and 6-digit code from Wireless debugging")

                GroupedList {
                    ConfigTextArea {
                        id: pairHostField
                        Layout.fillWidth: true
                        buttonIcon: "router"
                        text: Translation.tr("Pair host / IP")
                        placeholderText: Translation.tr("e.g. 192.168.1.100")
                        value: Config.options.androidConnect.wirelessAdbPairHost
                        onValueChanged: {
                            pairHostDebounce.restart()
                        }
                        Timer {
                            id: pairHostDebounce
                            interval: 600; repeat: false
                            onTriggered: Config.options.androidConnect.wirelessAdbPairHost = pairHostField.value
                        }
                    }
                    ConfigTextArea {
                        id: pairPortField
                        Layout.fillWidth: true
                        buttonIcon: "tag"
                        text: Translation.tr("Pair port")
                        placeholderText: Translation.tr("e.g. 37251")
                        value: Config.options.androidConnect.wirelessAdbPairPort
                        onValueChanged: {
                            pairPortDebounce.restart()
                        }
                        Timer {
                            id: pairPortDebounce
                            interval: 600; repeat: false
                            onTriggered: Config.options.androidConnect.wirelessAdbPairPort = pairPortField.value
                        }
                    }
                    ConfigTextArea {
                        id: pairCodeField
                        Layout.fillWidth: true
                        buttonIcon: "pin"
                        text: Translation.tr("Pairing code (6 digits)")
                        placeholderText: Translation.tr("e.g. 123456")
                        value: Config.options.androidConnect.wirelessAdbPairCode
                        onValueChanged: {
                            pairCodeDebounce.restart()
                        }
                        Timer {
                            id: pairCodeDebounce
                            interval: 600; repeat: false
                            onTriggered: Config.options.androidConnect.wirelessAdbPairCode = pairCodeField.value
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 8
                        Layout.rightMargin: 8
                        spacing: 8

                        RippleButtonWithIcon {
                            materialIcon: "phonelink_ring"
                            mainText: Translation.tr("Pair Device")
                            enabled: !AndroidConnect.wirelessAdbBusy && Config.options.androidConnect.wirelessAdbPairHost !== "" && Config.options.androidConnect.wirelessAdbPairPort !== "" && Config.options.androidConnect.wirelessAdbPairCode !== ""
                            colBackground: Appearance.colors.colPrimaryContainer
                            onClicked: {
                                AndroidConnect.pairWirelessAdb(
                                    Config.options.androidConnect.wirelessAdbPairHost,
                                    Config.options.androidConnect.wirelessAdbPairPort,
                                    Config.options.androidConnect.wirelessAdbPairCode
                                );
                            }
                        }
                    }
                }
            }

            // Connection Subsection
            ContentSubsection {
                title: Translation.tr("Connect Paired Device")
                tooltip: Translation.tr("Connect to an already paired device via its IP and port")

                GroupedList {
                    ConfigTextArea {
                        id: connectHostField
                        Layout.fillWidth: true
                        buttonIcon: "link"
                        text: Translation.tr("Connect host / IP")
                        placeholderText: Translation.tr("e.g. 192.168.1.100")
                        value: Config.options.androidConnect.wirelessAdbConnectHost
                        onValueChanged: {
                            connectHostDebounce.restart()
                        }
                        Timer {
                            id: connectHostDebounce
                            interval: 600; repeat: false
                            onTriggered: Config.options.androidConnect.wirelessAdbConnectHost = connectHostField.value
                        }
                    }
                    ConfigTextArea {
                        id: connectPortField
                        Layout.fillWidth: true
                        buttonIcon: "tag"
                        text: Translation.tr("Connect port")
                        placeholderText: Translation.tr("e.g. 5555")
                        value: Config.options.androidConnect.wirelessAdbConnectPort
                        onValueChanged: {
                            connectPortDebounce.restart()
                        }
                        Timer {
                            id: connectPortDebounce
                            interval: 600; repeat: false
                            onTriggered: Config.options.androidConnect.wirelessAdbConnectPort = connectPortField.value
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 8
                        Layout.rightMargin: 8
                        spacing: 10

                        RippleButtonWithIcon {
                            materialIcon: "link"
                            mainText: Translation.tr("Connect")
                            enabled: !AndroidConnect.wirelessAdbBusy && Config.options.androidConnect.wirelessAdbConnectHost !== ""
                            colBackground: Appearance.colors.colPrimaryContainer
                            onClicked: {
                                AndroidConnect.connectWirelessAdb(
                                    Config.options.androidConnect.wirelessAdbConnectHost,
                                    Config.options.androidConnect.wirelessAdbConnectPort || "5555"
                                );
                            }
                        }

                        RippleButtonWithIcon {
                            materialIcon: "link_off"
                            mainText: Translation.tr("Disconnect All")
                            enabled: !AndroidConnect.wirelessAdbBusy
                            colBackground: Appearance.colors.colLayer2
                            onClicked: {
                                AndroidConnect.disconnectWirelessAdb();
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 8
                        Layout.rightMargin: 8
                        visible: page.statusText !== "" || AndroidConnect.wirelessAdbBusy
                        spacing: 8

                        MaterialSymbol {
                            text: AndroidConnect.wirelessAdbBusy ? "sync" : (page.statusSuccess ? "check_circle" : "error")
                            iconSize: Appearance.font.pixelSize.normal
                            color: AndroidConnect.wirelessAdbBusy ? Appearance.colors.colPrimary : (page.statusSuccess ? Appearance.colors.colPrimary : Appearance.colors.colError)
                        }

                        StyledText {
                            text: AndroidConnect.wirelessAdbBusy ? Translation.tr("Executing ADB command...") : page.statusText
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: AndroidConnect.wirelessAdbBusy ? Appearance.colors.colPrimary : (page.statusSuccess ? Appearance.colors.colPrimary : Appearance.colors.colError)
                        }
                    }
                }
            }
        }

        // ==========================================
        // 4. SETUP INFO SECTION
        // ==========================================
        ContentSection {
            icon: "info"
            shape: MaterialShape.Shape.Diamond
            title: Translation.tr("Setup Info")

            GroupedList {
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: infoColumn.implicitHeight + 24
                    color: Appearance.colors.colLayer1
                    radius: Appearance.rounding.normal

                    ColumnLayout {
                        id: infoColumn
                        anchors {
                            fill: parent
                            margins: 14
                        }
                        spacing: 10

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("V4L2 Loopback Setup")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnLayer1
                        }

                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer1Inactive
                            text: Translation.tr("To use the embedded phone mirror, you need the v4l2loopback kernel module loaded with sufficient buffer dimensions. Run this command once:")
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: cmdRow.implicitHeight + 16
                            color: Appearance.colors.colLayer2
                            radius: Appearance.rounding.small

                            RowLayout {
                                id: cmdRow
                                anchors {
                                    fill: parent
                                    margins: 8
                                }
                                spacing: 10

                                StyledText {
                                    id: cmdText
                                    Layout.fillWidth: true
                                    wrapMode: Text.WrapAnywhere
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.family: Appearance.font.family.monospace
                                    color: Appearance.colors.colOnLayer2
                                    text: 'sudo modprobe v4l2loopback devices=1 video_nr=10 card_label="scrcpy-panel" exclusive_caps=0 max_width=1440 max_height=3200'
                                }

                                RippleButtonWithIcon {
                                    materialIcon: page.copySuccess ? "done" : "content_copy"
                                    mainText: page.copySuccess ? Translation.tr("Copied!") : Translation.tr("Copy")
                                    colBackground: page.copySuccess ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer1
                                    onClicked: {
                                        copyProc.command = ["wl-copy", cmdText.text];
                                        copyProc.running = true;
                                        page.copySuccess = true;
                                        copyTimer.restart();
                                    }
                                }
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer1Inactive
                            text: Translation.tr("Required packages: scrcpy, android-tools, v4l2loopback-dkms, kdeconnect")
                        }
                    }
                }
            }
        }
    }
}
