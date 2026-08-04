pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * A service that provides access to Hyprland keybinds.
 * Uses the `get_keybinds.py` script to parse comments in config files and convert to JSON.
 */
Singleton {
    id: root
    property string keybindParserPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/hyprland/get_keybinds.py`)
    property string defaultKeybindConfigPath: FileUtils.trimFileProtocol(`${Directories.config}/hypr/hyprland/keybinds.lua`)
    property string userKeybindConfigPath: FileUtils.trimFileProtocol(`${Directories.config}/hypr/custom/keybinds.lua`)

    property var keybinds: []
    property var keybindCategories: []
    property var rawDefault: null
    property var rawUser: null

    function flattenTree(node, list) {
        if (!node)
            return;
        if (Array.isArray(node)) {
            node.forEach(child => flattenTree(child, list));
            return;
        }
        if (node.keybinds && Array.isArray(node.keybinds)) {
            node.keybinds.forEach(bind => {
                const comment = bind.comment || bind.description || "";
                if (comment && comment.length > 0) {
                    list.push({
                        description: comment,
                        key: bind.key || "",
                        mods: bind.mods || [],
                        modmask: modsToMask(bind.mods || [])
                    });
                }
            });
        }
        if (node.children && Array.isArray(node.children)) {
            node.children.forEach(child => flattenTree(child, list));
        }
    }

    function modsToMask(mods) {
        let mask = 0;
        if (!Array.isArray(mods))
            return 0;
        mods.forEach(m => {
            const upper = String(m).toUpperCase();
            if (upper.includes("CTRL"))
                mask |= (1 << 2);
            else if (upper.includes("SUPER"))
                mask |= (1 << 6);
            else if (upper.includes("SHIFT"))
                mask |= (1 << 0);
            else if (upper.includes("ALT"))
                mask |= (1 << 3);
        });
        return mask;
    }

    function rebuild() {
        var all = [];
        flattenTree(rawDefault, all);
        flattenTree(rawUser, all);

        var uniqueBinds = [];
        var seen = new Set();
        all.forEach(b => {
            var keyStr = `${b.modmask}:${b.key}:${b.description}`;
            if (!seen.has(keyStr)) {
                seen.add(keyStr);
                uniqueBinds.push(b);
            }
        });

        var groups = [];
        uniqueBinds.forEach(b => {
            if (b.description && b.description.indexOf(":") !== -1) {
                var group = b.description.substring(0, b.description.indexOf(":")).trim();
                if (!groups.includes(group) && group.length > 0) {
                    groups.push(group);
                }
            }
        });

        root.keybinds = uniqueBinds;
        root.keybindCategories = groups;
    }

    function refreshKeybinds() {
        getDefaultKeybinds.running = true;
        getUserKeybinds.running = true;
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name == "configreloaded") {
                refreshKeybinds();
            }
        }
    }

    Process {
        id: getDefaultKeybinds
        running: true
        command: ["python3", root.keybindParserPath, "--path", root.defaultKeybindConfigPath]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.rawDefault = JSON.parse(text);
                    root.rebuild();
                } catch (e) {
                    console.error("[HyprlandKeybinds] Error parsing default keybinds:", e);
                }
            }
        }
    }

    Process {
        id: getUserKeybinds
        running: true
        command: ["python3", root.keybindParserPath, "--path", root.userKeybindConfigPath]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.rawUser = JSON.parse(text);
                    root.rebuild();
                } catch (e) {
                    console.error("[HyprlandKeybinds] Error parsing user keybinds:", e);
                }
            }
        }
    }
}
