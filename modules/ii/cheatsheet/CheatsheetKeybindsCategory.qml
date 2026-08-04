pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

Column {
    id: root
    required property string categoryName
    readonly property bool isCategorized: categoryName?.length > 0
    property int maxBindWidth: 0
    property real columnSpacing: 16
    property real titleSpacing: 10

    property var macSymbolMap: ({
            "Ctrl": "Ctrl",
            "Alt": "Alt",
            "Shift": "Shift",
            "Space": "Space",
            "Tab": "Tab",
            "Equal": "=",
            "Minus": "-",
            "Print": "PrtSc",
            "BackSpace": "Backspace",
            "Delete": "Delete",
            "Return": "Enter",
            "Period": ".",
            "Escape": "Esc"
        })
    property var functionSymbolMap: ({
            "F1": "F1",
            "F2": "F2",
            "F3": "F3",
            "F4": "F4",
            "F5": "F5",
            "F6": "F6",
            "F7": "F7",
            "F8": "F8",
            "F9": "F9",
            "F10": "F10",
            "F11": "F11",
            "F12": "F12"
        })

    property var mouseSymbolMap: ({
            "mouse_up": "Scroll ↓",
            "mouse_down": "Scroll ↑",
            "mouse:272": "LMB",
            "mouse:273": "RMB",
            "Scroll ↑/↓": "Scroll ↑/↓",
            "Page_↑/↓": "PgUp/PgDn"
        })

    property var keyBlacklist: ["SUPER_L", "SUPER_R"]
    property var keySubstitutions: Object.assign({
        "Super": "Super",
        "Mouse_up": "Scroll ↓",
        "Mouse_down": "Scroll ↑",
        "Mouse:272": "LMB",
        "Mouse:273": "RMB",
        "Mouse:275": "MouseBack",
        "Slash": "/",
        "Hash": "#",
        "Return": "Enter"
    }, (Config.options?.cheatsheet?.superKey && Config.options.cheatsheet.superKey.length > 0 && Config.options.cheatsheet.superKey !== "") ? {
        "Super": Config.options.cheatsheet.superKey
    } : {
        "Super": "Super"
    }, (Config.options?.cheatsheet?.useMacSymbol ?? false) ? macSymbolMap : {}, (Config.options?.cheatsheet?.useFnSymbol ?? false) ? functionSymbolMap : {}, (Config.options?.cheatsheet?.useMouseSymbol ?? false) ? mouseSymbolMap : {})

    function modMaskToStringList(modMask: int): list<string> {
        var list = [];
        if (modMask & (1 << 2)) {
            list.push("Ctrl");
        }
        if (modMask & (1 << 6)) {
            list.push("Super");
        }
        if (modMask & (1 << 0)) {
            list.push("Shift");
        }
        if (modMask & (1 << 3)) {
            list.push("Alt");
        }
        if (modMask & (1 << 1)) {
            list.push("Caps");
        }
        if (modMask & (1 << 4)) {
            list.push("Mod2");
        }
        if (modMask & (1 << 5)) {
            list.push("Mod3");
        }
        if (modMask & (1 << 7)) {
            list.push("Mod5");
        }
        return list;
    }

    spacing: titleSpacing

    RowLayout {
        width: parent ? parent.width : 340
        spacing: 8

        Rectangle {
            implicitWidth: 4
            implicitHeight: 18
            radius: Appearance.rounding.full
            color: Appearance.m3colors.m3primary
        }

        StyledText {
            text: root.isCategorized ? root.categoryName : Translation.tr("Uncategorized")
            font.pixelSize: Appearance.font.pixelSize.title
            font.weight: Font.Bold
            color: Appearance.m3colors.m3primary
        }
    }

    Column {
        width: parent ? parent.width : 340
        spacing: 6

        Repeater {
            model: {
                if (!root.isCategorized) {
                    return HyprlandKeybinds.keybinds.filter(bind => bind.description?.length > 0 && bind.description.indexOf(":") === -1);
                }
                return HyprlandKeybinds.keybinds.filter(bind => bind.description?.length > 0 && bind.description.substring(0, bind.description.indexOf(":")).trim() === root.categoryName);
            }
            delegate: BindLine {
                width: parent ? parent.width : 340
                required property var modelData
                keyData: modelData
                categoryName: root.categoryName
            }
        }
    }

    component BindLine: RowLayout {
        id: bindLine
        required property var keyData
        property string categoryName: ""
        spacing: 12

        Row {
            id: modRow
            spacing: 4
            Layout.alignment: Qt.AlignVCenter

            Repeater {
                model: {
                    const modList = root.modMaskToStringList(bindLine.keyData.modmask).map(mod => root.keySubstitutions[mod] || mod);
                    if (modList.length == 0)
                        return [];
                    if (Config.options?.cheatsheet?.splitButtons ?? false)
                        return modList;
                    return [modList.join(" ")];
                }
                delegate: KeyboardKey {
                    required property var modelData
                    key: modelData
                    pixelSize: (Config.options?.cheatsheet?.fontSize?.key) ?? Appearance.font.pixelSize.smaller
                }
            }
            StyledText {
                id: keybindPlus
                anchors.verticalCenter: parent.verticalCenter
                visible: !keyBlacklist.includes(bindLine.keyData.key) && bindLine.keyData.modmask > 0 && bindLine.keyData.key.length > 0
                text: "+"
                color: Appearance.m3colors.m3outline
            }
            KeyboardKey {
                id: keybindKey
                anchors.verticalCenter: parent.verticalCenter
                visible: !keyBlacklist.includes(bindLine.keyData.key) && bindLine.keyData.key.length > 0
                key: {
                    const k = StringUtils.toTitleCase(bindLine.keyData.key);
                    return root.keySubstitutions[k] || k;
                }
                pixelSize: (Config.options?.cheatsheet?.fontSize?.key) ?? Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnLayer0
            }
        }

        StyledText {
            id: commentText
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            elide: Text.ElideRight
            font.pixelSize: (Config.options?.cheatsheet?.fontSize?.comment) ?? Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnLayer0
            text: {
                const desc = bindLine.keyData.description || "";
                const regex = new RegExp("^\\s*" + bindLine.categoryName + "\\s*:\\s*", "i");
                return desc.replace(regex, "");
            }
        }
    }
}
