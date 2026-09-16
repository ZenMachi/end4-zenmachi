import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: page
    forceWidth: true

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

        ContentSection {
            icon: "smartphone"
            shape: MaterialShape.Shape.ClamShell
            title: Translation.tr("General")

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

        ContentSection {
            icon: "screen_mirror"
            shape: MaterialShape.Shape.Cookie6Sided
            title: Translation.tr("Mirror")

            GroupedList {
                ConfigSwitch {
                    buttonIcon: "volume_up"
                    text: Translation.tr("Mirror audio from phone")
                    checked: Config.options.androidConnect.embeddedMirrorAudioEnabled
                    onCheckedChanged: { Config.options.androidConnect.embeddedMirrorAudioEnabled = checked; }
                }
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
            }
        }

        ContentSection {
            icon: "wifi"
            shape: MaterialShape.Shape.Gem
            title: Translation.tr("Wireless ADB")

            GroupedList {
                ConfigTextArea {
                    id: pairHostField
                    Layout.fillWidth: true
                    buttonIcon: "router"
                    text: Translation.tr("Pair host")
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
                    id: connectHostField
                    Layout.fillWidth: true
                    buttonIcon: "link"
                    text: Translation.tr("Connect host")
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
            }
        }

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
                            margins: 12
                        }
                        spacing: 8

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
                            text: Translation.tr("To use the embedded phone mirror, you need the v4l2loopback kernel module loaded. Run this command once:")
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: cmdText.implicitHeight + 16
                            color: Appearance.colors.colLayer2
                            radius: Appearance.rounding.small

                            StyledText {
                                id: cmdText
                                anchors {
                                    fill: parent
                                    margins: 8
                                }
                                wrapMode: Text.WrapAnywhere
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.family: Appearance.font.family.monospace
                                color: Appearance.colors.colOnLayer2
                                text: "sudo modprobe v4l2loopback devices=1 video_nr=10 card_label=scrcpy-panel exclusive_caps=0 max_width=960 max_height=2160"
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
