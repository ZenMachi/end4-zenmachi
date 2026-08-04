pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

Item {
    id: root
    property real padding: 12
    implicitWidth: Math.min(1050, Math.max(800, (QsWindow?.window?.screen.width * 0.75) ?? 900))
    implicitHeight: Math.min(640, Math.max(500, (QsWindow?.window?.screen.height * 0.7) ?? 600))

    StyledFlickable {
        id: flickable
        anchors.fill: parent
        anchors.margins: 12
        contentHeight: flow.implicitHeight + 20
        contentWidth: flickable.width
        clip: true

        Flow {
            id: flow
            width: flickable.width
            spacing: 24
            flow: Flow.LeftToRight

            Repeater {
                model: HyprlandKeybinds.keybindCategories
                delegate: CheatsheetKeybindsCategory {
                    required property var modelData
                    categoryName: modelData
                    width: Math.max(340, Math.floor((flow.width - 24) / 2))
                }
            }
        }
    }
}
