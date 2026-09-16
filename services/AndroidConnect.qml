import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services
pragma Singleton

Singleton {
    id: root

    // --- 1. Device Telemetry & KDE Connect State ---
    property var devices: []
    property bool daemonAvailable: false
    property var mainDevice: null
    property string mainDeviceId: ""
    property bool anyDevicesConnected: false
    // --- 2. ADB Device State ---
    property var adbDeviceStates: ({
    })
    property var adbConnectedSerials: []
    property string adbUsbSerial: ""
    property bool adbHasUsbTransport: false
    property int adbScreenWidth: 1080
    property int adbScreenHeight: 2400
    // ADB Device Telemetry Cache
    property string adbDeviceName: ""
    property int adbBatteryLevel: -1
    property bool adbIsCharging: false
    property string adbNetworkType: ""
    property int adbSignalStrength: 4
    // --- 4. scrcpy Session Management ---
    property bool scrcpyLaunching: false
    property bool scrcpyStopRequested: false
    readonly property bool scrcpyRunning: scrcpySessionProc.running
    property bool scrcpyStreamReady: false
    property string scrcpyActiveSerial: ""
    property string scrcpyFeedDevicePath: "/dev/video10"
    property string scrcpyLaunchError: ""
    property string scrcpyLastStderr: ""
    // --- Direct Windowed Scrcpy Management ---
    property bool directScrcpyRunning: directScrcpyProc.running
    property string directScrcpyActiveSerial: ""
    // --- 6. ADB Input Queue ---
    property var adbCommandQueue: []
    property bool adbScreenRecordingActive: adbRecordProc.running
    property string adbRecordingPath: ""
    property bool keepAwakeActive: false
    property string originalScreenTimeout: "60000"
    property bool physicalScreenOff: (Config.options.androidConnect && Config.options.androidConnect.turnOffScreenOnMirror) ? true : false
    // --- 7. Wireless ADB ---
    property bool wirelessAdbBusy: false
    property bool qrPairingActive: qrPairProc.running
    property string qrImagePath: ""
    property double qrImageTimestamp: 0
    property string qrPairingCode: ""
    property string qrServiceName: ""
    property string qrPairStatus: ""
    property bool qrPairSuccess: false
    property string qrDiscoveredIp: ""
    signal qrPairEvent(string event, var data)
    // --- 8. Periodic Refresh ---
    property bool reduceBackgroundRefresh: false

    signal wirelessAdbFinished(bool success, string message)

    // Resolves the best ADB serial to use for commands
    function resolvedAdbSerial() {
        if (adbUsbSerial !== "")
            return adbUsbSerial;

        if (adbConnectedSerials.length > 0)
            return adbConnectedSerials[0];

        return "";
    }

    // --- 3. KDE Connect D-Bus Integration ---
    function checkDaemon() {
        daemonCheckProc.running = true;
    }

    function refreshDevices() {
        if (!daemonAvailable)
            return ;

        deviceDiscoveryProc.running = true;
    }

    function setMainDevice(deviceId) {
        mainDeviceId = deviceId;
        refreshMainDeviceProps();
    }

    function refreshMainDeviceProps() {
        if (mainDeviceId === "") {
            mainDevice = null;
            return ;
        }
        mainDevicePropsProc.running = true;
    }

    function triggerFindMyPhone(deviceId) {
        runBusctlCall("/modules/kdeconnect/devices/" + deviceId + "/findmyphone", "org.kde.kdeconnect.device.findmyphone", "ring", []);
    }

    function browseFiles(deviceId) {
        runBusctlCall("/modules/kdeconnect/devices/" + deviceId + "/sftp", "org.kde.kdeconnect.device.sftp", "mountAndWait", []);
    }

    function shareFile(deviceId, filePath) {
        var proc = Qt.createQmlObject('import Quickshell.Io; Process { command: ["kdeconnect-cli", "-d", "' + deviceId + '", "--share", "' + filePath + '"] }', root);
        proc.running = true;
    }

    function requestPairing(deviceId) {
        runBusctlCall("/modules/kdeconnect/devices/" + deviceId, "org.kde.kdeconnect.device", "requestPair", []);
    }

    function unpairDevice(deviceId) {
        runBusctlCall("/modules/kdeconnect/devices/" + deviceId, "org.kde.kdeconnect.device", "unpair", []);
    }

    function wakeUpDevice(deviceId) {
        var serial = resolvedAdbSerial();
        if (serial !== "")
            queueAdbTask(serial, ["shell", "input", "keyevent", "KEYCODE_WAKEUP"], "wakeup");

    }

    function runBusctlCall(obj, itf, method, params) {
        var args = ["busctl", "--user", "call", "org.kde.kdeconnect", obj, itf, method].concat(params);
        var proc = Qt.createQmlObject('import Quickshell.Io; Process { command: ' + JSON.stringify(args) + ' }', root);
        proc.running = true;
    }

    function launchScrcpySession(deviceId, commandString) {
        var targetSerial = deviceId || resolvedAdbSerial();
        if (!targetSerial || targetSerial === "")
            return ;

        scrcpyLaunching = true;
        scrcpyStopRequested = false;
        scrcpyStreamReady = false;
        scrcpyActiveSerial = targetSerial;
        scrcpyPreLaunchProc.command = ["bash", "-c", "pkill -f 'scrcpy.*--v4l2-sink' 2>/dev/null || true; v4l2-ctl -d " + shellQuote(scrcpyFeedDevicePath) + " -c keep_format=0 2>/dev/null || true; adb -s " + shellQuote(targetSerial) + " shell \"input keyevent 224; input keyevent 82 2>/dev/null || true\"; sleep 0.2"];
        scrcpyPreLaunchProc.running = true;
    }

    Timer {
        id: scrcpyRestartTimer

        interval: 350
        repeat: false
        property string restartSerial: ""
        onTriggered: {
            launchScrcpySession(restartSerial);
        }
    }

    function restartScrcpySession(serial) {
        var s = serial || scrcpyActiveSerial || resolvedAdbSerial();
        scrcpyRestartTimer.restartSerial = s;
        if (scrcpySessionProc.running)
            scrcpySessionProc.running = false;
        scrcpyRestartTimer.restart();
    }

    function stopScrcpySession() {
        scrcpyStopRequested = true;
        scrcpyLaunching = false;
        scrcpyStreamReady = false;
        scrcpyStreamSafetyTimer.stop();
        if (scrcpySessionProc.running)
            scrcpySessionProc.running = false;

        scrcpyCleanupProc.running = true;
    }

    function launchDirectScrcpy(deviceSerial, extraArgs) {
        var targetSerial = deviceSerial || resolvedAdbSerial();
        if (!targetSerial || targetSerial === "") {
            console.warn("[AndroidConnect] Cannot launch direct scrcpy: no target serial");
            return ;
        }
        if (directScrcpyProc.running) {
            hyprFocusProc.running = true;
            return ;
        }
        var devName = adbDeviceName || (mainDevice ? mainDevice.name : "Android");
        var title = "Android - " + devName;
        var cmd = ["scrcpy", "-s", targetSerial, "--display-id=0", "--window-title=" + title, "--stay-awake"];
        if (extraArgs && Array.isArray(extraArgs))
            cmd = cmd.concat(extraArgs);

        directScrcpyActiveSerial = targetSerial;
        directScrcpyProc.command = cmd;
        directScrcpyProc.running = true;
    }

    function stopDirectScrcpy() {
        if (directScrcpyProc.running)
            directScrcpyProc.running = false;

        var p = Qt.createQmlObject('import Quickshell.Io; Process { command: ["bash", "-c", "pkill -f \'scrcpy.*--window-title\' 2>/dev/null || true"] }', root);
        p.running = true;
    }

    function toggleDirectScrcpy() {
        if (directScrcpyRunning)
            hyprFocusProc.running = true;
        else
            launchDirectScrcpy();
    }

    function launchDetachedScrcpy(deviceSerial, commandString) {
        launchDirectScrcpy(deviceSerial);
    }

    function forceStopScrcpyProcesses(feedDevicePath) {
        var cmd = ["bash", "-c", "pkill -f 'scrcpy.*--v4l2-sink=" + feedDevicePath + "'"];
        var p = Qt.createQmlObject('import Quickshell.Io; Process { command: ' + JSON.stringify(cmd) + ' }', root);
        p.running = true;
    }

    // --- 5. ADB Device Management & Telemetry ---
    function refreshAdbDevices() {
        adbDevicesProc.running = true;
    }

    function queryAdbDeviceInfo(serial) {
        adbDeviceInfoProc.command = ["bash", "-c", 'SERIAL="' + serial + '"\n' + 'MODEL=$(adb -s "$SERIAL" shell getprop ro.product.model 2>/dev/null)\n' + 'HOST=$(adb -s "$SERIAL" shell getprop net.hostname 2>/dev/null)\n' + 'BRAND=$(adb -s "$SERIAL" shell getprop ro.product.brand 2>/dev/null)\n' + 'SIZE=$(adb -s "$SERIAL" shell wm size 2>/dev/null | grep -o "[0-9]\\+x[0-9]\\+" | head -1)\n' + 'BATTERY=$(adb -s "$SERIAL" shell dumpsys battery 2>/dev/null)\n' + 'LEVEL=$(echo "$BATTERY" | grep "level:" | head -1 | awk "{print \\$2}")\n' + 'AC=$(echo "$BATTERY" | grep "AC powered: true" || echo "")\n' + 'USB=$(echo "$BATTERY" | grep "USB powered: true" || echo "")\n' + 'CHARGING="false"\n' + '[ -n "$AC" ] || [ -n "$USB" ] && CHARGING="true"\n' + 'NET_TYPE=$(adb -s "$SERIAL" shell getprop gsm.network.type 2>/dev/null | awk -F"," "{print \\$1}")\n' + 'SIGNAL=$(adb -s "$SERIAL" shell dumpsys telephony.registry 2>/dev/null | grep -o "level=[0-4]" | sort -rn | head -1 | cut -d= -f2)\n' + 'TIMEOUT=$(adb -s "$SERIAL" shell settings get system screen_off_timeout 2>/dev/null)\n' + '[ -z "$SIGNAL" ] && SIGNAL="4"\n' + '[ -z "$LEVEL" ] && LEVEL="-1"\n' + '[ -z "$TIMEOUT" ] && TIMEOUT="60000"\n' + 'echo "JSON:{\\"model\\":\\"$MODEL\\",\\"host\\":\\"$HOST\\",\\"brand\\":\\"$BRAND\\",\\"size\\":\\"$SIZE\\",\\"battery\\":$LEVEL,\\"charging\\":$CHARGING,\\"net\\":\\"$NET_TYPE\\",\\"signal\\":$SIGNAL,\\"timeout\\":\\"$TIMEOUT\\"}"'];
        adbDeviceInfoProc.running = true;
    }

    function queueAdbTask(serial, args, kind) {
        adbCommandQueue.push({
            "serial": serial,
            "args": args,
            "kind": kind
        });
        if (adbCommandQueue.length === 1 && !adbTaskProc.running)
            runNextAdbTask();

    }

    function runNextAdbTask() {
        if (adbCommandQueue.length > 0) {
            var task = adbCommandQueue[0];
            var cmd = ["adb"].concat(adbSelectorArgsForSerial(task.serial)).concat(task.args);
            adbTaskProc.command = cmd;
            adbTaskProc.running = true;
        }
    }

    function runAdbTap(serial, x, y) {
        queueAdbTask(serial, ["shell", "input", "tap", String(x), String(y)], "tap");
    }

    function runAdbSwipe(serial, x1, y1, x2, y2, durationMs) {
        queueAdbTask(serial, ["shell", "input", "swipe", String(x1), String(y1), String(x2), String(y2), String(durationMs)], "swipe");
    }

    function runAdbKeyevent(serial, keyCode) {
        queueAdbTask(serial, ["shell", "input", "keyevent", String(keyCode)], "key");
    }

    function runAdbText(serial, text) {
        queueAdbTask(serial, ["shell", "input", "text", encodeAdbInputText(text)], "text");
    }

    function takeAdbScreenshot(serial) {
        var targetSerial = serial || resolvedAdbSerial();
        if (!targetSerial || targetSerial === "")
            return ;

        var selectorArgs = adbSelectorArgsForSerial(targetSerial).join(" ");
        var timestamp = new Date().toISOString().replace(/[:.]/g, "-");
        var filePath = "/tmp/android_screenshot_" + timestamp + ".png";
        var cmd = "adb " + selectorArgs + " exec-out screencap -p > " + shellQuote(filePath) + " && notify-send -i " + shellQuote(filePath) + " 'Android Screenshot' 'Saved to " + filePath + "' && xdg-open " + shellQuote(filePath) + " 2>/dev/null || true";
        var p = Qt.createQmlObject('import Quickshell.Io; Process { command: ["bash", "-c", "' + cmd.replace(/"/g, '\\"') + '"]; Component.onCompleted: running = true }', root);
    }

    function startAdbScreenRecording(serial) {
        var targetSerial = serial || resolvedAdbSerial();
        if (!targetSerial || targetSerial === "")
            return ;

        var timestamp = new Date().toISOString().replace(/[:.]/g, "-");
        adbRecordingPath = "/tmp/android_record_" + timestamp + ".mp4";
        adbRecordProc.command = ["adb", "-s", targetSerial, "shell", "screenrecord", "/sdcard/screenrecord.mp4"];
        adbRecordProc.running = true;
    }

    function stopAdbScreenRecording() {
        if (adbRecordProc.running) {
            var targetSerial = resolvedAdbSerial();
            var p = Qt.createQmlObject('import Quickshell.Io; Process { command: ["adb", "-s", "' + targetSerial + '", "shell", "pkill", "-2", "screenrecord"] }', root);
            p.running = true;
            adbRecordProc.running = false;
        }
    }

    function setKeepAwake(serial, enabled) {
        var targetSerial = serial || resolvedAdbSerial();
        if (!targetSerial || targetSerial === "")
            return;

        keepAwakeActive = enabled;
        if (enabled) {
            var cmd = "adb -s " + shellQuote(targetSerial) + " shell \"settings put system screen_off_timeout 2147483647; svc power stayon true; input keyevent KEYCODE_WAKEUP\"";
            var p1 = Qt.createQmlObject('import Quickshell.Io; Process { command: ["bash", "-c", ' + JSON.stringify(cmd) + '] }', root);
            p1.running = true;
            if (Config.options.androidConnect && Config.options.androidConnect.turnOffScreenOnMirror && scrcpyRunning && !physicalScreenOff) {
                setPhysicalScreenPower(targetSerial, false);
            }
        } else {
            var restoreTimeout = originalScreenTimeout || "60000";
            var cmdRestore = "adb -s " + shellQuote(targetSerial) + " shell \"settings put system screen_off_timeout " + restoreTimeout + "; svc power stayon false\"";
            var p2 = Qt.createQmlObject('import Quickshell.Io; Process { command: ["bash", "-c", ' + JSON.stringify(cmdRestore) + '] }', root);
            p2.running = true;
            if (physicalScreenOff) {
                setPhysicalScreenPower(targetSerial, true);
            }
        }
    }

    function toggleKeepAwake(serial) {
        setKeepAwake(serial, !keepAwakeActive);
    }

    function setPhysicalScreenPower(serial, powerOn) {
        var targetSerial = serial || resolvedAdbSerial();
        if (!targetSerial || targetSerial === "")
            return;

        if (powerOn) {
            physicalScreenOff = false;
            var cmdOn = "adb -s " + shellQuote(targetSerial) + " shell \"cmd display power-reset 0; input keyevent KEYCODE_WAKEUP\"";
            var pOn = Qt.createQmlObject('import Quickshell.Io; Process { command: ["bash", "-c", ' + JSON.stringify(cmdOn) + '] }', root);
            pOn.running = true;
            if (scrcpyRunning) {
                var currentSerialOn = scrcpyActiveSerial || targetSerial;
                restartScrcpySession(currentSerialOn);
            }
        } else {
            physicalScreenOff = true;
            if (scrcpyRunning) {
                var currentSerialOff = scrcpyActiveSerial || targetSerial;
                restartScrcpySession(currentSerialOff);
            } else {
                var cmdOff = "adb -s " + shellQuote(targetSerial) + " shell \"cmd display power-off 0\"";
                var pOff = Qt.createQmlObject('import Quickshell.Io; Process { command: ["bash", "-c", ' + JSON.stringify(cmdOff) + '] }', root);
                pOff.running = true;
            }
        }
    }

    function togglePhysicalScreen(serial) {
        setPhysicalScreenPower(serial, physicalScreenOff);
    }

    function restoreDeviceScreenSettings(serial) {
        var targetSerial = serial || resolvedAdbSerial();
        if (!targetSerial || targetSerial === "")
            return;

        if (physicalScreenOff) {
            physicalScreenOff = false;
            var cmdReset = "adb -s " + shellQuote(targetSerial) + " shell \"cmd display power-reset 0; input keyevent KEYCODE_WAKEUP\"";
            var pR = Qt.createQmlObject('import Quickshell.Io; Process { command: ["bash", "-c", ' + JSON.stringify(cmdReset) + '] }', root);
            pR.running = true;
        }
        if (keepAwakeActive && !(Config.options.androidConnect && Config.options.androidConnect.keepPhoneAwake)) {
            keepAwakeActive = false;
            var restoreTimeout = originalScreenTimeout || "60000";
            var cmdT = "adb -s " + shellQuote(targetSerial) + " shell \"settings put system screen_off_timeout " + restoreTimeout + "; svc power stayon false\"";
            var pT = Qt.createQmlObject('import Quickshell.Io; Process { command: ["bash", "-c", ' + JSON.stringify(cmdT) + '] }', root);
            pT.running = true;
        }
    }

    function pairWirelessAdb(host, port, code) {
        wirelessAdbBusy = true;
        var cmd = ["bash", "-c", "adb pair " + host + ":" + port + " " + code];
        var p = Qt.createQmlObject('import Quickshell.Io; Process { command: ' + JSON.stringify(cmd) + '; onExited: (c, s) => { root.wirelessAdbBusy = false; root.wirelessAdbFinished(c === 0, c === 0 ? "Paired successfully" : "Pairing failed") } }', root);
        p.running = true;
    }

    function connectWirelessAdb(host, port) {
        wirelessAdbBusy = true;
        var cmd = ["bash", "-c", "adb connect " + host + ":" + port];
        var p = Qt.createQmlObject('import Quickshell.Io; Process { command: ' + JSON.stringify(cmd) + '; onExited: (c, s) => { root.wirelessAdbBusy = false; root.wirelessAdbFinished(c === 0, c === 0 ? "Connected successfully" : "Connection failed"); root.refreshAdbDevices() } }', root);
        p.running = true;
    }

    function disconnectWirelessAdb(host, port) {
        wirelessAdbBusy = true;
        var target = (host && port) ? (host + ":" + port) : "";
        var cmd = target !== "" ? ["bash", "-c", "adb disconnect " + target] : ["bash", "-c", "adb disconnect"];
        var p = Qt.createQmlObject('import Quickshell.Io; Process { command: ' + JSON.stringify(cmd) + '; onExited: (c, s) => { root.wirelessAdbBusy = false; root.wirelessAdbFinished(c === 0, c === 0 ? "Disconnected" : "Disconnect failed"); root.refreshAdbDevices() } }', root);
        p.running = true;
    }

    function startQrPairing() {
        qrPairSuccess = false;
        qrImagePath = "";
        qrPairingCode = "";
        qrServiceName = "";
        qrDiscoveredIp = "";
        qrImageTimestamp = Date.now();
        qrPairStatus = qsTr("Generating QR code...");
        if (qrPairProc.running) {
            qrPairProc.running = false;
        }
        qrPairProc.command = ["python3", Quickshell.shellPath("scripts/devices/adb_qr_pair.py")];
        qrPairProc.running = true;
    }

    function stopQrPairing() {
        if (qrPairProc.running) {
            qrPairProc.running = false;
        }
        qrPairStatus = "";
        qrImagePath = "";
        qrPairingCode = "";
        qrServiceName = "";
        qrDiscoveredIp = "";
        qrPairSuccess = false;
    }

    function handleQrPairEvent(msg) {
        if (!msg || !msg.event) return;
        qrPairEvent(msg.event, msg);
        if (msg.event === "qr_ready") {
            qrImageTimestamp = Date.now();
            qrImagePath = msg.qr_path;
            qrPairingCode = msg.code;
            qrServiceName = msg.name;
            qrPairStatus = qsTr("Scan this QR code on your phone");
            qrPairSuccess = false;
        } else if (msg.event === "discovered") {
            qrDiscoveredIp = msg.ip;
            qrPairStatus = qsTr("Phone detected (%1), pairing...").arg(msg.ip);
        } else if (msg.event === "pairing") {
            qrPairStatus = qsTr("Pairing with %1:%2...").arg(msg.ip).arg(msg.port);
        } else if (msg.event === "paired_success") {
            qrPairSuccess = true;
            qrPairStatus = qsTr("Paired successfully with %1!").arg(msg.ip);
            if (Config.options.androidConnect) {
                Config.options.androidConnect.wirelessAdbConnectHost = msg.ip;
            }
            root.refreshAdbDevices();
        } else if (msg.event === "connected") {
            qrPairSuccess = true;
            qrPairStatus = qsTr("Connected to %1:%2!").arg(msg.ip).arg(msg.port);
            if (Config.options.androidConnect) {
                Config.options.androidConnect.wirelessAdbConnectHost = msg.ip;
                Config.options.androidConnect.wirelessAdbConnectPort = msg.port.toString();
            }
            root.refreshAdbDevices();
        } else if (msg.event === "paired_ready_connect") {
            qrPairSuccess = true;
            qrPairStatus = qsTr("Paired! Ready to connect.");
            if (Config.options.androidConnect) {
                Config.options.androidConnect.wirelessAdbConnectHost = msg.ip;
            }
            root.refreshAdbDevices();
        } else if (msg.event === "timeout") {
            qrPairStatus = qsTr("Timed out. Make sure phone is on same Wi-Fi.");
        } else if (msg.event === "error") {
            qrPairStatus = msg.message || qsTr("Pairing error");
        }
    }

    // --- 9. Helper Functions ---
    function busctlCall(obj, itf, method, params) {
        return ["busctl", "--user", "call", "--json=short", "org.kde.kdeconnect", obj, itf, method].concat(params);
    }

    function busctlGet(obj, itf, prop) {
        return ["busctl", "--user", "get-property", "--json=short", "org.kde.kdeconnect", obj, itf, prop];
    }

    function shellQuote(value) {
        if (!value)
            return "''";

        return "'" + value.replace(/'/g, "'\\''") + "'";
    }

    function adbSelectorArgsForSerial(serial) {
        if (!serial || serial === "")
            return [];

        return ["-s", serial];
    }

    function encodeAdbInputText(text) {
        if (!text)
            return "";

        var escaped = text.replace(/(["\s'&])/g, "\\$1");
        return escaped;
    }

    Component.onCompleted: {
        checkDaemon();
        refreshAdbDevices();
    }

    Process {
        id: daemonCheckProc

        command: ["busctl", "--user", "status", "org.kde.kdeconnect"]
        onExited: (exitCode, exitStatus) => {
            daemonAvailable = (exitCode === 0);
            if (daemonAvailable)
                refreshDevices();

        }
    }

    Process {
        id: deviceDiscoveryProc

        property string output: ""

        command: ["busctl", "--user", "call", "--json=short", "org.kde.kdeconnect", "/modules/kdeconnect", "org.kde.kdeconnect.daemon", "devices"]
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0 && output.length > 0) {
                try {
                    var parsed = JSON.parse(output);
                    var data = parsed.data || [];
                    var newDevices = [];
                    if (data.length > 0 && Array.isArray(data[0])) {
                        for (var i = 0; i < data[0].length; i++) {
                            newDevices.push({
                                "id": data[0][i]
                            });
                        }
                    }
                    devices = newDevices;
                    if (mainDeviceId === "" && devices.length > 0)
                        setMainDevice(devices[0].id);

                } catch (e) {
                    console.error("Failed to parse devices json", e);
                }
            }
            output = "";
        }

        stdout: SplitParser {
            onRead: (data) => {
                deviceDiscoveryProc.output += data;
            }
        }

    }

    Process {
        id: mainDevicePropsProc

        property string output: ""

        command: ["bash", "-c", "busctl --user introspect --json=short org.kde.kdeconnect /modules/kdeconnect/devices/" + mainDeviceId]
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0 && output.length > 0) {
                try {
                    var parsed = JSON.parse(output);
                    var props = {
                        "id": mainDeviceId,
                        "reachable": false,
                        "paired": false,
                        "name": ""
                    };
                    if (Array.isArray(parsed)) {
                        for (var i = 0; i < parsed.length; i++) {
                            var item = parsed[i];
                            if (item.name === ".name" && item.result_value)
                                props.name = item.result_value.replace(/^"|"$/g, "");
                            else if (item.name === ".isReachable" && item.result_value)
                                props.reachable = (item.result_value === "true");
                            else if (item.name === ".isPaired" && item.result_value)
                                props.paired = (item.result_value === "true");
                        }
                    }
                    if (props.reachable) {
                        mainDevice = props;
                        anyDevicesConnected = true;
                    } else if (resolvedAdbSerial() === "") {
                        mainDevice = props;
                    }
                } catch (e) {
                    console.error("Failed to parse device properties json", e);
                }
            }
            output = "";
        }

        stdout: SplitParser {
            onRead: (data) => {
                mainDevicePropsProc.output += data;
            }
        }

    }

    Timer {
        id: scrcpyStreamSafetyTimer

        interval: 6000
        repeat: false
        onTriggered: {
            if (scrcpySessionProc.running && !root.scrcpyStreamReady) {
                console.log("[AndroidConnect] Safety timer: scrcpy stream ready fallback");
                root.scrcpyStreamReady = true;
            }
        }
    }

    Process {
        id: directScrcpyProc

        onExited: (exitCode, exitStatus) => {
            console.log("[AndroidConnect] Direct scrcpy exited with code:", exitCode);
            directScrcpyActiveSerial = "";
        }
    }

    Process {
        id: hyprFocusProc

        command: ["bash", "-c", "hyprctl dispatch focuswindow class:scrcpy 2>/dev/null || true"]
    }

    function getScrcpyStreamParams(w, h, maxDim) {
        let screenW = w || 1080;
        let screenH = h || 2400;
        let baseMax = maxDim || 960;
        let ratio = screenW / screenH;

        let bestW = 432;
        let bestH = 960;
        let minDiff = 999;

        // Find (outW, outH) both divisible by 16 closest to device aspect ratio
        for (let targetH = baseMax - 64; targetH <= baseMax + 64; targetH += 16) {
            let idealW = targetH * ratio;
            let targetW = Math.round(idealW / 16) * 16;
            if (targetW <= 0)
                continue;
            let diff = Math.abs((targetW / targetH) - ratio);
            if (diff < minDiff) {
                minDiff = diff;
                bestW = targetW;
                bestH = targetH;
            }
        }

        // Calculate exact crop to guarantee that scrcpy scales EXACTLY to (bestW, bestH)
        // without fractional pixel truncation by the hardware encoder (which breaks YUV420 stride)
        let targetRatio = bestW / bestH;
        let cropW = screenW;
        let cropH = screenH;

        if (targetRatio >= ratio) {
            cropH = Math.round(screenW / targetRatio);
        } else {
            cropW = Math.round(screenH * targetRatio);
        }

        // Fine-tune by single pixels to guarantee exact match with scrcpy rounding
        while (Math.round(bestH * (cropW / cropH)) < bestW && cropH > 100) {
            cropH--;
        }
        while (Math.round(bestH * (cropW / cropH)) > bestW && cropW > 100) {
            cropW--;
        }

        let cropX = Math.floor((screenW - cropW) / 2);
        let cropY = Math.floor((screenH - cropH) / 2);

        return {
            "outWidth": bestW,
            "outHeight": bestH,
            "maxSize": bestH,
            "cropArg": cropW + ":" + cropH + ":" + cropX + ":" + cropY
        };
    }

    Process {
        id: scrcpyPreLaunchProc

        onExited: (exitCode, exitStatus) => {
            if (!scrcpyStopRequested && scrcpyActiveSerial !== "") {
                var userMaxSize = (Config.options.androidConnect && Config.options.androidConnect.mirrorMaxSize) ? Config.options.androidConnect.mirrorMaxSize : 960;
                var userFps = (Config.options.androidConnect && Config.options.androidConnect.mirrorMaxFps) ? Config.options.androidConnect.mirrorMaxFps : 60;
                var userBitrate = (Config.options.androidConnect && Config.options.androidConnect.mirrorBitrateMbps) ? Config.options.androidConnect.mirrorBitrateMbps : 12;
                var audioEnabled = (Config.options.androidConnect && Config.options.androidConnect.embeddedMirrorAudioEnabled);

                var streamParams = root.getScrcpyStreamParams(adbScreenWidth, adbScreenHeight, userMaxSize);
                var cmd = [
                    "stdbuf", "-oL", "-eL", "scrcpy",
                    "-s", scrcpyActiveSerial,
                    "--v4l2-sink=" + scrcpyFeedDevicePath,
                    "--no-window",
                    "--display-id=0",
                    "--stay-awake",
                    "--crop=" + streamParams.cropArg,
                    "--max-size=" + streamParams.maxSize,
                    "--max-fps=" + userFps,
                    "--video-bit-rate=" + userBitrate + "M",
                    "--video-codec=h264",
                    "--v4l2-buffer=0"
                ];
                if (!audioEnabled) {
                    cmd.splice(4, 0, "--no-audio");
                }
                var screenOffRequested = root.physicalScreenOff;
                if (screenOffRequested) {
                    cmd.push("--turn-screen-off");
                }
                if (Config.options.androidConnect && Config.options.androidConnect.keepPhoneAwake && !root.keepAwakeActive) {
                    root.setKeepAwake(scrcpyActiveSerial, true);
                }
                scrcpySessionProc.command = cmd;
                root.scrcpyStreamReady = false;
                scrcpySessionProc.running = true;
                scrcpyStreamSafetyTimer.restart();
                scrcpyLaunching = false;
            } else {
                scrcpyLaunching = false;
            }
        }
    }

    Timer {
        id: streamReadyDelayTimer

        interval: 800
        repeat: false
        onTriggered: {
            console.log("[AndroidConnect] Stream ready delay elapsed, activating stream");
            root.scrcpyStreamReady = true;
        }
    }

    Process {
        id: scrcpySessionProc

        onExited: (exitCode, exitStatus) => {
            streamReadyDelayTimer.stop();
            root.scrcpyStreamReady = false;
            scrcpyStreamSafetyTimer.stop();
            scrcpyLaunching = false;
            scrcpyCleanupProc.running = true;
        }

        stdout: SplitParser {
            onRead: (data) => {
                if (data.indexOf("v4l2 sink started") !== -1) {
                    console.log("[AndroidConnect] v4l2 sink started detected in stdout");
                    scrcpyStreamSafetyTimer.stop();
                    streamReadyDelayTimer.restart();
                }
            }
        }

        stderr: SplitParser {
            onRead: (data) => {
                root.scrcpyLastStderr = data;
                if (data.indexOf("v4l2 sink started") !== -1) {
                    console.log("[AndroidConnect] v4l2 sink started detected in stderr");
                    scrcpyStreamSafetyTimer.stop();
                    streamReadyDelayTimer.restart();
                }
            }
        }

    }

    Process {
        id: scrcpyCleanupProc

        command: ["bash", "-c", "pkill -f 'scrcpy.*--v4l2-sink' 2>/dev/null || true"]
    }

    Process {
        id: adbDevicesProc

        property string output: ""

        command: ["adb", "devices", "-l"]
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                var lines = output.split("\n");
                var serials = [];
                var usbSerialFound = "";
                var usb = false;
                for (var i = 1; i < lines.length; i++) {
                    var line = lines[i].trim();
                    if (line && line.indexOf("device ") !== -1) {
                        var parts = line.replace(/\s+/g, " ").split(" ");
                        var serial = parts[0];
                        serials.push(serial);
                        if (line.indexOf("usb:") !== -1) {
                            usb = true;
                            if (!usbSerialFound)
                                usbSerialFound = serial;

                        }
                    }
                }
                adbConnectedSerials = serials;
                adbHasUsbTransport = usb;
                adbUsbSerial = usbSerialFound;
                var activeSerial = resolvedAdbSerial();
                if (activeSerial !== "") {
                    anyDevicesConnected = true;
                    queryAdbDeviceInfo(activeSerial);
                } else if (mainDevice === null || !mainDevice.reachable) {
                    anyDevicesConnected = false;
                }
            }
            output = "";
        }

        stdout: SplitParser {
            onRead: (data) => {
                adbDevicesProc.output += data + "\n";
            }
        }

    }

    Process {
        id: adbDeviceInfoProc

        property string output: ""

        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0 && output.indexOf("JSON:") !== -1) {
                try {
                    var jsonStr = output.substring(output.indexOf("JSON:") + 5).trim();
                    var parsed = JSON.parse(jsonStr);
                    if (parsed.size) {
                        var dims = parsed.size.split("x");
                        if (dims.length === 2) {
                            adbScreenWidth = parseInt(dims[0]) || 1080;
                            adbScreenHeight = parseInt(dims[1]) || 2400;
                        }
                    }
                    var brandFormatted = parsed.brand ? (parsed.brand.charAt(0).toUpperCase() + parsed.brand.slice(1)) : "";
                    var displayName = "";
                    if (brandFormatted && parsed.model)
                        displayName = brandFormatted + " " + parsed.model;
                    else
                        displayName = parsed.host || parsed.model || "Android Phone";
                    adbDeviceName = displayName;
                    adbBatteryLevel = parsed.battery !== undefined ? parsed.battery : -1;
                    adbIsCharging = parsed.charging === true;
                    adbNetworkType = parsed.net || "LTE";
                    adbSignalStrength = parsed.signal !== undefined ? parsed.signal : 4;
                    // Update mainDevice telemetry
                    mainDevice = {
                        "id": resolvedAdbSerial(),
                        "name": (mainDevice && mainDevice.name && mainDevice.name !== "Android Phone") ? mainDevice.name : displayName,
                        "reachable": true,
                        "paired": true,
                        "battery": adbBatteryLevel >= 0 ? adbBatteryLevel : (mainDevice ? mainDevice.battery : -1),
                        "isCharging": adbIsCharging,
                        "cellularNetworkType": adbNetworkType || (mainDevice ? mainDevice.cellularNetworkType : "LTE"),
                        "cellularNetworkStrength": adbSignalStrength !== undefined ? adbSignalStrength : (mainDevice ? mainDevice.cellularNetworkStrength : 4)
                    };
                    if (parsed.timeout && parsed.timeout !== "2147483647" && parsed.timeout !== "null" && parseInt(parsed.timeout) > 0) {
                        originalScreenTimeout = parsed.timeout;
                    }
                    if (Config.options.androidConnect && Config.options.androidConnect.keepPhoneAwake && !keepAwakeActive) {
                        setKeepAwake(resolvedAdbSerial(), true);
                    }
                } catch (e) {
                    console.error("Failed to parse adb device info json", e);
                }
            }
            output = "";
        }

        stdout: SplitParser {
            onRead: (data) => {
                adbDeviceInfoProc.output += data;
            }
        }

    }

    Process {
        id: adbTaskProc

        onExited: (exitCode, exitStatus) => {
            adbCommandQueue.shift();
            runNextAdbTask();
        }
    }

    Process {
        id: qrPairProc
        command: ["python3", Quickshell.shellPath("scripts/devices/adb_qr_pair.py")]

        stdout: SplitParser {
            onRead: (data) => {
                try {
                    let lines = data.trim().split("\n");
                    for (let l of lines) {
                        l = l.trim();
                        if (!l.startsWith("{")) continue;
                        let msg = JSON.parse(l);
                        root.handleQrPairEvent(msg);
                    }
                } catch (e) {
                    console.warn("[AndroidConnect] QR pair parse error:", e);
                }
            }
        }

        stderr: SplitParser {
            onRead: (data) => {
                console.warn("[AndroidConnect] QR pair stderr:", data);
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 && !root.qrPairSuccess && root.qrPairStatus !== "") {
                root.qrPairStatus = qsTr("Pairing canceled or timed out");
            }
        }
    }

    Process {
        id: adbRecordProc

        onExited: (exitCode, exitStatus) => {
            console.log("[AndroidConnect] Screen recording process exited, code:", exitCode);
            if (adbRecordingPath !== "") {
                var savePath = adbRecordingPath;
                var targetSerial = resolvedAdbSerial();
                var cmd = "adb -s " + shellQuote(targetSerial) + " pull /sdcard/screenrecord.mp4 " + shellQuote(savePath) + " && adb -s " + shellQuote(targetSerial) + " shell rm -f /sdcard/screenrecord.mp4 && notify-send 'Android Recording' 'Saved to " + savePath + "' && xdg-open " + shellQuote(savePath) + " 2>/dev/null || true";
                var pullProc = Qt.createQmlObject('import Quickshell.Io; Process { command: ["bash", "-c", ' + JSON.stringify(cmd) + '] }', root);
                pullProc.running = true;
            }
        }
    }

    Timer {
        id: refreshTimer

        interval: reduceBackgroundRefresh ? 20000 : 4000
        running: true
        repeat: true
        onTriggered: {
            refreshDevices();
            refreshAdbDevices();
        }
    }

}
