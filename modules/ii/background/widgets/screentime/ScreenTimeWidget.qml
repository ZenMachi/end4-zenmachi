import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Quickshell
import Quickshell.Widgets
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
    configEntryName: "screentime"
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

    property var parsedData: null
    property int totalScreentime: parsedData?.total_screentime ?? 0
    property int totalUptime: parsedData?.total_uptime ?? 0
    property var appsData: parsedData?.apps ?? {}
    property var hourlyUsage: parsedData?.hourly_usage ?? {}

    property bool historyOpen: false
    readonly property int activeWorkspaceId: WM.activeWorkspaceForMonitor(root.QsWindow?.screen?.name ?? "")?.id ?? 0
    property int monthShift: 0

    onActiveWorkspaceIdChanged: {
        root.historyOpen = false;
        root.selectedDateKey = "";
        root.selectedDateLabel = "";
    }

    Connections {
        target: WM
        function onActiveWorkspaceChanged() {
            root.historyOpen = false;
            root.selectedDateKey = "";
            root.selectedDateLabel = "";
        }
    }

    Connections {
        target: HyprlandData
        function onActiveWorkspaceChanged() {
            root.historyOpen = false;
            root.selectedDateKey = "";
            root.selectedDateLabel = "";
        }
    }

    Timer {
        interval: 200
        repeat: true
        running: root.historyOpen
        property int lastWorkspaceId: root.activeWorkspaceId
        onTriggered: {
            if (root.activeWorkspaceId !== lastWorkspaceId) {
                lastWorkspaceId = root.activeWorkspaceId;
                root.historyOpen = false;
                root.selectedDateKey = "";
                root.selectedDateLabel = "";
            }
        }
    }

    property string selectedDateKey: ""
    property string selectedDateLabel: ""
    property var historyDays: []
    property var selectedData: null

    readonly property string historyDir: Quickshell.env("HOME") + "/.cache/screentime_history"

    function historyFilePath(key) {
        return root.historyDir + "/" + key + ".json";
    }

    property var viewingDate: {
        let d = new Date();
        d.setDate(1);
        d.setMonth(d.getMonth() + root.monthShift);
        return d;
    }
    readonly property var todayDate: new Date()
    readonly property string todayDateKey: {
        const n = root.todayDate;
        return n.getFullYear() + "-" + String(n.getMonth() + 1).padStart(2, "0") + "-" + String(n.getDate()).padStart(2, "0");
    }

    property var historyDateMap: {}
    function historyTotal(key) {
        return root.historyDateMap[key] ?? null;
    }

    function hasHistory(key) {
        return root.historyDateMap[key] !== undefined;
    }

    function selectDate(key, label) {
        root.selectedDateKey = key;
        root.selectedDateLabel = label;
        if (key === root.todayDateKey)
            return;
        const dayView = historyDayFileView;
        if (dayView) {
            dayView.path = root.historyFilePath(key);
            dayView.reload();
        }
    }

    function getMonthMatrix(date) {
        const year = date.getFullYear();
        const month = date.getMonth();
        const firstOfMonth = new Date(year, month, 1);
        const startOffset = (firstOfMonth.getDay() + 6) % 7;
        const daysInMonth = new Date(year, month + 1, 0).getDate();
        const daysInPrevMonth = new Date(year, month, 0).getDate();
        let cells = [];
        for (let i = 0; i < startOffset; i++)
            cells.push({ day: daysInPrevMonth - startOffset + i + 1, currentMonth: false });
        for (let d = 1; d <= daysInMonth; d++) {
            const key = year + "-" + String(month + 1).padStart(2, "0") + "-" + String(d).padStart(2, "0");
            cells.push({ day: d, currentMonth: true, key: key });
        }
        let nextDay = 1;
        while (cells.length < 42)
            cells.push({ day: nextDay++, currentMonth: false, key: "" });
        let weeks = [];
        for (let i = 0; i < cells.length; i += 7)
            weeks.push(cells.slice(i, i + 7));
        return weeks;
    }

    function dateKeyLabel(key) {
        if (!key) return "";
        const parts = key.split("-");
        const d = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
        return d.toLocaleDateString(Qt.locale(), "d MMMM yyyy");
    }

    property var monthWeeks: root.getMonthMatrix(root.viewingDate)

    function formatTime(seconds) {
        if (seconds <= 0)
            return "0m";
        const h = Math.floor(seconds / 3600);
        const m = Math.floor((seconds % 3600) / 60);
        if (h > 0) {
            return h + "h " + m + "m";
        }
        return m + "m";
    }

    function getSortedApps() {
        if (!appsData)
            return [];
        let list = [];
        for (let name in appsData) {
            list.push({
                name: name,
                time: appsData[name]
            });
        }
        list.sort((a, b) => b.time - a.time);
        return list;
    }

    function formatAppName(name) {
        if (!name)
            return "";
        if (name.includes(".")) {
            const parts = name.split(".");
            name = parts[parts.length - 1];
        }
        return name.charAt(0).toUpperCase() + name.slice(1);
    }

    function formatHourAxis(seconds) {
        if (seconds <= 0)
            return "0h/hr";
        const h = (seconds / 3600).toFixed(1);
        return h + "h/hr";
    }

    Process {
        id: trackerProc
        command: ["python3", Quickshell.shellPath("scripts/screentime/screentime_tracker.py")]
        running: true
    }

    FileView {
        id: screentimeFileView
        path: Quickshell.env("HOME") + "/.cache/screentime.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const textData = screentimeFileView.text().trim();
                if (textData) {
                    root.parsedData = JSON.parse(textData);
                }
            } catch (e) {
                console.log("[ScreenTimeWidget] Error parsing JSON:", e);
            }
        }
    }

    FileView {
        id: historyIndexFileView
        path: root.historyDir + "/index.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const textData = historyIndexFileView.text().trim();
                if (!textData) { root.historyDays = []; root.historyDateMap = {}; return; }
                const obj = JSON.parse(textData);
                root.historyDateMap = obj;
                root.historyDays = Object.keys(obj).sort();
            } catch (e) {
                console.log("[ScreenTimeWidget] Error parsing history index:", e);
            }
        }
    }

    FileView {
        id: historyDayFileView
        path: ""
        onFileChanged: reload()
        onLoaded: {
            try {
                const textData = historyDayFileView.text().trim();
                if (!textData) { if (historyDayFileView.path !== "") root.selectedData = null; return; }
                root.selectedData = JSON.parse(textData);
            } catch (e) {
                console.log("[ScreenTimeWidget] Error parsing history day:", e);
            }
        }
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

        // Layout for 2x2 Square mode (Material 3 Android Wellbeing style)
        ColumnLayout {
            visible: root.sizeMode === "2x2"
            anchors {
                fill: parent
                margins: 14
            }
            spacing: 6

            // Top Header Row
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                MaterialSymbol {
                    text: "hourglass_bottom"
                    iconSize: 18
                    color: Appearance.colors.colOnPrimaryContainer // Changed to contrast primary
                    opacity: 0.6 // Matched to location icon opacity in Clock
                }

                StyledText {
                    text: "Screen Time"
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnPrimaryContainer
                    Layout.fillWidth: true
                }

                StyledText {
                    text: "24h History"
                    font.pixelSize: 11
                    color: Appearance.colors.colOnPrimaryContainer
                    opacity: 0.7 // Imitating colSubtext against primary
                }

                Rectangle {
                    id: historyButton2x2
                    width: 24
                    height: 24
                    radius: 12
                    color: root.historyOpen ? ColorUtils.mix(Appearance.colors.colOnPrimaryContainer, Appearance.colors.colPrimaryContainer, 0.15) : "transparent"
                    Layout.rightMargin: -4
                    Behavior on color {
                        ColorAnimation { duration: 150 }
                    }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "history"
                        iconSize: 16
                        fill: root.historyOpen ? 1 : 0
                        color: Appearance.colors.colOnPrimaryContainer
                        opacity: 0.75
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.historyOpen = !root.historyOpen
                    }
                }
            }

            // Main Metric Readout + Peak rate
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter

                StyledText {
                    text: root.formatTime(root.totalScreentime)
                    font.pixelSize: 28
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnPrimaryContainer
                }

                StyledText {
                    property real maxVal: {
                        let max = 0;
                        for (let i = 0; i < 24; i++) {
                            let val = root.hourlyUsage[i.toString()] ?? 0;
                            if (val > max)
                                max = val;
                        }
                        return max;
                    }
                    text: "Peak: " + root.formatHourAxis(maxVal)
                    font.pixelSize: 11
                    color: Appearance.colors.colOnPrimaryContainer
                    opacity: 0.7
                    Layout.alignment: Qt.AlignBottom
                    Layout.bottomMargin: 4
                }
            }

            // Material 3 Bar Chart with 0-24 Full Day Timeline
            ColumnLayout {
                id: chartContainer2x2
                Layout.fillWidth: true
                spacing: 3

                Item {
                    id: chart2x2
                    Layout.fillWidth: true
                    implicitHeight: 38

                    property real maxVal: {
                        let max = 0;
                        for (let i = 0; i < 24; i++) {
                            let val = root.hourlyUsage[i.toString()] ?? 0;
                            if (val > max)
                                max = val;
                        }
                        return max > 0 ? max : 1;
                    }

                    property int currentHour: new Date().getHours()

                    Row {
                        anchors.centerIn: parent
                        spacing: 3

                        Repeater {
                            model: 24
                            delegate: Item {
                                required property int index
                                property int hourIndex: index
                                property real hourVal: root.hourlyUsage[hourIndex.toString()] ?? 0
                                property bool isCurrentHour: hourIndex === chart2x2.currentHour

                                width: 6
                                height: chart2x2.implicitHeight

                                Rectangle {
                                    width: parent.width
                                    height: Math.max(4, (hourVal / chart2x2.maxVal) * chart2x2.implicitHeight)
                                    radius: width / 2
                                    anchors.bottom: parent.bottom

                                    color: isCurrentHour ? Appearance.colors.colOnPrimaryContainer : (hourVal > 0 ? ColorUtils.mix(Appearance.colors.colOnPrimaryContainer, Appearance.colors.colPrimaryContainer, 0.45) : ColorUtils.mix(Appearance.colors.colOnPrimaryContainer, Appearance.colors.colPrimaryContainer, 0.12))
                                    border.width: isCurrentHour ? 1 : 0
                                    border.color: Appearance.colors.colOnPrimaryContainer
                                }
                            }
                        }
                    }
                }

                // 0-24 Hour Timeline Markings Row
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 10
                    Layout.rightMargin: 10

                    StyledText {
                        text: "00"
                        font.pixelSize: 9
                        color: Appearance.colors.colOnPrimaryContainer
                        opacity: 0.7
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    StyledText {
                        text: "06"
                        font.pixelSize: 9
                        color: Appearance.colors.colOnPrimaryContainer
                        opacity: 0.7
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    StyledText {
                        text: "12"
                        font.pixelSize: 9
                        color: Appearance.colors.colOnPrimaryContainer
                        opacity: 0.7
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    StyledText {
                        text: "18"
                        font.pixelSize: 9
                        color: Appearance.colors.colOnPrimaryContainer
                        opacity: 0.7
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    StyledText {
                        text: "24"
                        font.pixelSize: 9
                        color: Appearance.colors.colOnPrimaryContainer
                        opacity: 0.7
                    }
                }
            }

            // Top Apps Usage List (Android M3 Rows)
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 5

                Repeater {
                    model: root.getSortedApps().slice(0, 3)
                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 10

                        // Squircle Icon Box
                        Rectangle {
                            width: 26
                            height: 26
                            radius: 8
                            color: ColorUtils.mix(Appearance.colors.colOnPrimaryContainer, Appearance.colors.colPrimaryContainer, 0.1)

                            IconImage {
                                anchors.centerIn: parent
                                width: 16
                                height: 16
                                source: Quickshell.iconPath(AppSearch.guessIcon(modelData.name), "image-missing")
                            }
                        }

                        StyledText {
                            text: root.formatAppName(modelData.name)
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnPrimaryContainer
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }

                        StyledText {
                            text: root.formatTime(modelData.time)
                            font.pixelSize: 12
                            color: Appearance.colors.colOnPrimaryContainer
                            opacity: 0.7
                        }
                    }
                }
            }
        }

        // Layout for 1x4 Horizontal mode
        RowLayout {
            visible: root.sizeMode === "1x4"
            anchors {
                fill: parent
                margins: 12
            }
            spacing: 14

            // Left Column (Stats & Bar Chart)
            ColumnLayout {
                Layout.fillHeight: true
                Layout.preferredWidth: 210
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    MaterialSymbol {
                        text: "hourglass_bottom"
                        iconSize: 16
                        color: Appearance.colors.colOnPrimaryContainer
                        opacity: 0.6
                    }

                    StyledText {
                        text: "Screen Time"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnPrimaryContainer
                        Layout.fillWidth: true
                    }

                    Rectangle {
                        id: historyButton1x4
                        width: 22
                        height: 22
                        radius: 11
                        color: root.historyOpen ? ColorUtils.mix(Appearance.colors.colOnPrimaryContainer, Appearance.colors.colPrimaryContainer, 0.15) : "transparent"
                        Behavior on color {
                            ColorAnimation { duration: 150 }
                        }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "history"
                            iconSize: 15
                            fill: root.historyOpen ? 1 : 0
                            color: Appearance.colors.colOnPrimaryContainer
                            opacity: 0.75
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.historyOpen = !root.historyOpen
                        }
                    }
                }

                StyledText {
                    text: root.formatTime(root.totalScreentime)
                    font.pixelSize: 22
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnPrimaryContainer
                }

                // Small M3 Bar Chart with 0-24 Timeline
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Item {
                        id: chart1x4
                        Layout.fillWidth: true
                        implicitHeight: 28

                        property real maxVal: {
                            let max = 0;
                            for (let i = 0; i < 24; i++) {
                                let val = root.hourlyUsage[i.toString()] ?? 0;
                                if (val > max)
                                    max = val;
                            }
                            return max > 0 ? max : 1;
                        }

                        property int currentHour: new Date().getHours()

                        Row {
                            anchors.centerIn: parent
                            spacing: 3

                            Repeater {
                                model: 24
                                delegate: Item {
                                    required property int index
                                    property int hourIndex: index
                                    property real hourVal: root.hourlyUsage[hourIndex.toString()] ?? 0
                                    property bool isCurrentHour: hourIndex === chart1x4.currentHour

                                    width: 5
                                    height: chart1x4.implicitHeight

                                    Rectangle {
                                        width: parent.width
                                        height: Math.max(3, (hourVal / chart1x4.maxVal) * chart1x4.implicitHeight)
                                        radius: width / 2
                                        anchors.bottom: parent.bottom

                                        color: isCurrentHour ? Appearance.colors.colOnPrimaryContainer : (hourVal > 0 ? ColorUtils.mix(Appearance.colors.colOnPrimaryContainer, Appearance.colors.colPrimaryContainer, 0.45) : ColorUtils.mix(Appearance.colors.colOnPrimaryContainer, Appearance.colors.colPrimaryContainer, 0.12))
                                        border.width: isCurrentHour ? 1 : 0
                                        border.color: Appearance.colors.colOnPrimaryContainer
                                    }
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 6
                        Layout.rightMargin: 6

                        StyledText {
                            text: "00"
                            font.pixelSize: 8
                            color: Appearance.colors.colOnPrimaryContainer
                            opacity: 0.7
                        }
                        Item {
                            Layout.fillWidth: true
                        }
                        StyledText {
                            text: "12"
                            font.pixelSize: 8
                            color: Appearance.colors.colOnPrimaryContainer
                            opacity: 0.7
                        }
                        Item {
                            Layout.fillWidth: true
                        }
                        StyledText {
                            text: "24"
                            font.pixelSize: 8
                            color: Appearance.colors.colOnPrimaryContainer
                            opacity: 0.7
                        }
                    }
                }
            }

            // Divider
            Rectangle {
                width: 1
                Layout.fillHeight: true
                color: Appearance.colors.colOnPrimaryContainer
                opacity: 0.2
            }

            // Right Column (App List)
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 4

                Repeater {
                    model: root.getSortedApps().slice(0, 3)
                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 8

                        Rectangle {
                            width: 22
                            height: 22
                            radius: 6
                            color: ColorUtils.mix(Appearance.colors.colOnPrimaryContainer, Appearance.colors.colPrimaryContainer, 0.1)

                            IconImage {
                                anchors.centerIn: parent
                                width: 14
                                height: 14
                                source: Quickshell.iconPath(AppSearch.guessIcon(modelData.name), "image-missing")
                            }
                        }

                        StyledText {
                            text: root.formatAppName(modelData.name)
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnPrimaryContainer
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }

                        StyledText {
                            text: root.formatTime(modelData.time)
                            font.pixelSize: 11
                            color: Appearance.colors.colOnPrimaryContainer
                            opacity: 0.7
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
        id: historyPopup
        visible: root.historyOpen
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        screen: root.QsWindow?.screen ?? null
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell:popup:screentime"

        // The widget lives in a fullscreen per-screen window (screen origin = window origin),
        // so root.x/root.y are already screen coordinates.
        property real widgetScreenX: root.x
        property real widgetScreenY: root.y
        property real targetX: root.x + root.width / 2 - historyPopup.implicitWidth / 2
        property real targetY: root.y + root.height + 10

        anchors { left: true; top: true }
        margins {
            left: Math.max(10, Math.min(targetX, (root.QsWindow?.screen?.width ?? 1920) - historyPopup.implicitWidth - 10))
            top: {
                var maxTop = (root.QsWindow?.screen?.height ?? 1080) - historyPopup.implicitHeight - 10;
                // If it doesn't fit below, show it above the widget
                if (targetY > maxTop && root.y - historyPopup.implicitHeight - 10 > 10) {
                    return root.y - historyPopup.implicitHeight - 10;
                }
                return Math.max(10, Math.min(targetY, maxTop));
            }
        }

        implicitWidth: 320
        implicitHeight: popupColumn.implicitHeight + 24

        StyledRectangularShadow {
            target: popupBg
        }

        Rectangle {
            id: popupBg
            anchors.fill: parent
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer1Base
            border.width: 1
            border.color: Appearance.colors.colLayer0Border

            MouseArea {
                anchors.fill: parent
                // absorb clicks inside popup
            }

            ColumnLayout {
                id: popupColumn
                anchors {
                    fill: parent
                    margins: 12
                }
                spacing: 12

                // Header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    MaterialSymbol {
                        text: root.selectedDateKey === "" ? "calendar_month" : "arrow_back"
                        iconSize: 18
                        color: Appearance.colors.colOnPrimaryContainer
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            visible: root.selectedDateKey !== ""
                            onClicked: {
                                root.selectedDateKey = "";
                                root.selectedDateLabel = "";
                            }
                        }
                    }

                    StyledText {
                        text: root.selectedDateKey === "" ? "History" : root.selectedDateLabel
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
                            onClicked: root.historyOpen = false
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Appearance.colors.colOnPrimaryContainer
                    opacity: 0.1
                }

                // Calendar View
                ColumnLayout {
                    visible: root.selectedDateKey === ""
                    Layout.fillWidth: true
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true

                        StyledText {
                            Layout.fillWidth: true
                            font.pixelSize: 14
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnPrimaryContainer
                            text: root.viewingDate.toLocaleDateString(Qt.locale(), "MMMM yyyy")
                        }

                        Rectangle {
                            implicitWidth: 26; implicitHeight: 26; radius: 13
                            color: "transparent"
                            border.width: 1
                            border.color: Appearance.colors.colPrimary
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "chevron_left"
                                iconSize: 18
                                color: Appearance.colors.colOnPrimaryContainer
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.monthShift--
                            }
                        }

                        Rectangle {
                            implicitWidth: 26; implicitHeight: 26; radius: 13
                            color: "transparent"
                            border.width: 1
                            border.color: Appearance.colors.colPrimary
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "chevron_right"
                                iconSize: 18
                                color: Appearance.colors.colOnPrimaryContainer
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.monthShift++
                            }
                        }
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 6
                        Repeater {
                            model: ["Mo","Tu","We","Th","Fr","Sa","Su"]
                            delegate: StyledText {
                                Layout.preferredWidth: 32
                                horizontalAlignment: Text.AlignHCenter
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                color: Appearance.colors.colOnPrimaryContainer
                                opacity: 0.6
                                text: modelData
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: weeksColumn.implicitHeight + 16
                        color: Appearance.colors.colLayer0
                        radius: Appearance.rounding.normal

                        ColumnLayout {
                            id: weeksColumn
                            anchors.centerIn: parent
                            spacing: 4

                            Repeater {
                                model: root.monthWeeks
                                delegate: RowLayout {
                                    required property var modelData
                                    spacing: 6
                                    Repeater {
                                        model: parent.modelData
                                        delegate: Rectangle {
                                            required property var modelData
                                            property bool isToday: modelData.key === root.todayDateKey
                                            property bool hasData: root.hasHistory(modelData.key)
                                            property bool canSelect: hasData || isToday

                                            implicitWidth: 32
                                            implicitHeight: 32
                                            radius: 16
                                            color: isToday ? Appearance.colors.colPrimary : (canSelect && dayHoverArea.containsMouse ? Appearance.colors.colLayer1 : "transparent")
                                            border.width: hasData && !isToday ? 1 : 0
                                            border.color: Appearance.colors.colPrimaryContainer

                                            StyledText {
                                                anchors.centerIn: parent
                                                text: parent.modelData.day
                                                font.pixelSize: 12
                                                font.weight: parent.isToday ? Font.Bold : Font.Normal
                                                color: parent.isToday ? Appearance.colors.colOnPrimary : Appearance.colors.colOnPrimaryContainer
                                                opacity: parent.modelData.currentMonth ? (parent.canSelect ? 1.0 : 0.4) : 0.2
                                            }

                                            MouseArea {
                                                id: dayHoverArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: parent.canSelect ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                onClicked: {
                                                    if (parent.canSelect) {
                                                        root.selectDate(parent.modelData.key, root.dateKeyLabel(parent.modelData.key));
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Selected Day View
                ColumnLayout {
                    id: selectedDayView
                    visible: root.selectedDateKey !== ""
                    Layout.fillWidth: true
                    spacing: 12

                    property var currentData: root.selectedDateKey === root.todayDateKey ? root.parsedData : root.selectedData
                    property int currentScreentime: currentData?.total_screentime ?? 0
                    property var currentApps: currentData?.apps ?? {}
                    property var currentHourly: currentData?.hourly_usage ?? {}

                    function getCurrentSortedApps() {
                        let list = [];
                        for (let name in selectedDayView.currentApps) {
                            list.push({ name: name, time: selectedDayView.currentApps[name] });
                        }
                        list.sort((a, b) => b.time - a.time);
                        return list;
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter

                        StyledText {
                            text: root.formatTime(selectedDayView.currentScreentime)
                            font.pixelSize: 28
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnPrimaryContainer
                        }

                        StyledText {
                            property real maxVal: {
                                let max = 0;
                                for (let i = 0; i < 24; i++) {
                                    let val = selectedDayView.currentHourly[i.toString()] ?? 0;
                                    if (val > max) max = val;
                                }
                                return max;
                            }
                            text: "Peak: " + root.formatHourAxis(maxVal)
                            font.pixelSize: 11
                            color: Appearance.colors.colOnPrimaryContainer
                            opacity: 0.7
                            Layout.alignment: Qt.AlignBottom
                            Layout.bottomMargin: 4
                        }
                    }

                    // Bar Chart
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3

                        Item {
                            id: selectedBarChart
                            Layout.fillWidth: true
                            implicitHeight: 48

                            property var chartData: selectedDayView.currentHourly
                            property real maxVal: {
                                let max = 0;
                                for (let i = 0; i < 24; i++) {
                                    let val = selectedBarChart.chartData[i.toString()] ?? 0;
                                    if (val > max) max = val;
                                }
                                return max > 0 ? max : 1;
                            }
                            property int currentHour: root.selectedDateKey === root.todayDateKey ? new Date().getHours() : -1

                            Row {
                                anchors.centerIn: parent
                                spacing: 6

                                Repeater {
                                    model: 24
                                    delegate: Item {
                                        required property int index
                                        property int hourIndex: index
                                        property real hourVal: selectedBarChart.chartData[hourIndex.toString()] ?? 0
                                        property bool isCurrentHour: hourIndex === selectedBarChart.currentHour

                                        width: 6
                                        height: selectedBarChart.implicitHeight

                                        Rectangle {
                                            width: parent.width
                                            height: Math.max(4, (hourVal / selectedBarChart.maxVal) * selectedBarChart.implicitHeight)
                                            radius: width / 2
                                            anchors.bottom: parent.bottom
                                            color: isCurrentHour ? Appearance.colors.colOnPrimaryContainer : (hourVal > 0 ? ColorUtils.mix(Appearance.colors.colOnPrimaryContainer, Appearance.colors.colPrimaryContainer, 0.45) : ColorUtils.mix(Appearance.colors.colOnPrimaryContainer, Appearance.colors.colPrimaryContainer, 0.12))
                                            border.width: isCurrentHour ? 1 : 0
                                            border.color: Appearance.colors.colOnPrimaryContainer
                                        }
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: 8
                            Layout.rightMargin: 8

                            StyledText { text: "00"; font.pixelSize: 9; color: Appearance.colors.colOnPrimaryContainer; opacity: 0.7 }
                            Item { Layout.fillWidth: true }
                            StyledText { text: "06"; font.pixelSize: 9; color: Appearance.colors.colOnPrimaryContainer; opacity: 0.7 }
                            Item { Layout.fillWidth: true }
                            StyledText { text: "12"; font.pixelSize: 9; color: Appearance.colors.colOnPrimaryContainer; opacity: 0.7 }
                            Item { Layout.fillWidth: true }
                            StyledText { text: "18"; font.pixelSize: 9; color: Appearance.colors.colOnPrimaryContainer; opacity: 0.7 }
                            Item { Layout.fillWidth: true }
                            StyledText { text: "24"; font.pixelSize: 9; color: Appearance.colors.colOnPrimaryContainer; opacity: 0.7 }
                        }
                    }

                    // Top Apps
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Layout.topMargin: 8

                        Repeater {
                            model: selectedDayView.getCurrentSortedApps().slice(0, 5)
                            delegate: RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 10

                                Rectangle {
                                    width: 26
                                    height: 26
                                    radius: 8
                                    color: ColorUtils.mix(Appearance.colors.colOnPrimaryContainer, Appearance.colors.colPrimaryContainer, 0.1)

                                    IconImage {
                                        anchors.centerIn: parent
                                        width: 16
                                        height: 16
                                        source: Quickshell.iconPath(AppSearch.guessIcon(modelData.name), "image-missing")
                                    }
                                }

                                StyledText {
                                    text: root.formatAppName(modelData.name)
                                    font.pixelSize: 13
                                    font.weight: Font.Medium
                                    color: Appearance.colors.colOnPrimaryContainer
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    text: root.formatTime(modelData.time)
                                    font.pixelSize: 12
                                    color: Appearance.colors.colOnPrimaryContainer
                                    opacity: 0.7
                                }
                            }
                        }

                        StyledText {
                            visible: selectedDayView.getCurrentSortedApps().length === 0
                            text: "No app data available."
                            font.pixelSize: 12
                            color: Appearance.colors.colOnPrimaryContainer
                            opacity: 0.5
                            horizontalAlignment: Text.AlignHCenter
                            Layout.fillWidth: true
                            Layout.margins: 10
                        }
                    }
                }
            }
        }
    }
}
