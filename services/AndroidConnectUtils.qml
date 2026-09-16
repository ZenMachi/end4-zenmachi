pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    function getConnectionStateIcon(device, daemonAvailable) {
        if (device !== null && device.reachable) {
            if (device.battery !== undefined && device.battery >= 0 && device.battery < 10)
                return "battery_alert"
            if (device.notificationIds && device.notificationIds.length > 0)
                return "chat"
            if (device.isCharging)
                return "battery_charging_full"
            return "smartphone"
        }
        return "phone_disabled"
    }

    function getConnectionStateText(device, daemonAvailable) {
        if (device !== null && device.reachable)
            return qsTr("Connected")
        if (device === null)
            return qsTr("No device")
        if (!device.reachable)
            return qsTr("Disconnected")
        if (!daemonAvailable)
            return qsTr("Daemon unavailable")
        return qsTr("Disconnected")
    }

    function getSignalStrengthText(strength, isAirplaneMode) {
        if (isAirplaneMode) return qsTr("Off")
        if (strength === undefined || strength < 0) return qsTr("Unknown")
        if (strength >= 4) return qsTr("Excellent")
        if (strength >= 3) return qsTr("Good")
        if (strength >= 2) return qsTr("Fair")
        if (strength >= 1) return qsTr("Poor")
        return qsTr("No signal")
    }

    function getSignalStrengthIcon(strength, isAirplaneMode) {
        if (isAirplaneMode) return "airplanemode_active"
        if (strength === undefined || strength < 0) return "signal_cellular_off"
        if (strength >= 4) return "signal_cellular_4_bar"
        if (strength >= 3) return "signal_cellular_3_bar"
        if (strength >= 2) return "signal_cellular_2_bar"
        if (strength >= 1) return "signal_cellular_1_bar"
        return "signal_cellular_0_bar"
    }

    function getNetworkTypeText(networkType, isAirplaneMode, wifiSsid) {
        if (isAirplaneMode) {
            if (wifiSsid && wifiSsid !== "") return wifiSsid
            return qsTr("Airplane Mode")
        }
        if (!networkType || networkType === "" || networkType.toLowerCase() === "unknown") {
            if (wifiSsid && wifiSsid !== "") return wifiSsid
            return qsTr("Unknown")
        }
        const upper = networkType.toUpperCase()
        // Common cellular network types
        switch(upper) {
            case "LTE": return "LTE"
            case "NR": return "5G"
            case "HSPA": return "HSPA"
            case "HSPA+": return "HSPA+"
            case "HSDPA": return "HSDPA"
            case "UMTS": return "3G"
            case "EDGE": return "EDGE"
            case "GPRS": return "GPRS"
            case "CDMA": return "CDMA"
            case "EVDO": return "EVDO"
            case "IWLAN": return "Wi-Fi"
            default: return networkType
        }
    }

    function getBrandName(deviceName) {
        if (!deviceName) return ""
        const lower = deviceName.toLowerCase()
        if (lower.includes("pixel") || lower.includes("google")) return "Google"
        if (lower.includes("xiaomi") || lower.includes("redmi") || lower.includes("poco")) return "Xiaomi"
        if (lower.includes("motorola") || lower.includes("moto")) return "Motorola"
        if (lower.includes("samsung") || lower.includes("galaxy")) return "Samsung"
        if (lower.includes("oneplus")) return "OnePlus"
        if (lower.includes("oppo")) return "OPPO"
        if (lower.includes("vivo") || lower.includes("iqoo")) return "vivo"
        if (lower.includes("huawei")) return "Huawei"
        if (lower.includes("sony") || lower.includes("xperia")) return "Sony"
        if (lower.includes("nokia")) return "Nokia"
        if (lower.includes("asus") || lower.includes("rog") || lower.includes("zenfone")) return "ASUS"
        if (lower.includes("realme")) return "realme"
        if (lower.includes("nothing")) return "Nothing"
        return "Android"
    }

    function getBrandBadgeSource(deviceName) {
        const brand = getBrandName(deviceName)
        switch(brand) {
            case "Google": return Qt.resolvedUrl("../modules/ii/androidConnect/assets/brand-badges/google.svg")
            case "Xiaomi": return Qt.resolvedUrl("../modules/ii/androidConnect/assets/brand-badges/xiaomi.svg")
            case "Motorola": return Qt.resolvedUrl("../modules/ii/androidConnect/assets/brand-badges/motorola.svg")
            default: return Qt.resolvedUrl("../modules/ii/androidConnect/assets/brand-badges/android.svg")
        }
    }
}
