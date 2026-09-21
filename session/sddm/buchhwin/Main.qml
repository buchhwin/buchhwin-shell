import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import "Logic.js" as Logic
import "Style.js" as S

// buchhwin-shell login screen for SDDM (Theme-API 2, Qt 6 greeter). It looks
// like the shell's lock screen (shell/lock/): blurred wallpaper, date and a
// large rolling clock, avatar, name and password pill. SDDM loads it once per
// screen; the login controls only appear on the primary one.
//
// SDDM provides the context objects `sddm`, `config` (theme.conf and
// theme.conf.user), `userModel`, `sessionModel`, `keyboard` and
// `primaryScreen`.
Rectangle {
    id: root
    width: 1280
    height: 800
    color: S.base

    function setting(key) { return typeof config === "undefined" || !config ? undefined : config[key] }

    // theme.conf; install/system-install.sh writes `background` to theme.conf.user.
    readonly property string background: Logic.imageUrl(setting("background")) || "assets/background.svg"
    readonly property bool blur: Logic.configBool(setting("blur"), true)
    readonly property color accent: Logic.configColor(setting("accent"), S.accent)
    readonly property string fontFamily: Logic.configString(setting("font"), S.fontFamily)
    readonly property string dateFormat: Logic.configString(setting("dateFormat"), "dddd, d MMMM")
    // As much of the lock screen's arrangement as this screen can draw.
    readonly property var lockItems: Logic.lockItems(setting("lockItems"))
    readonly property bool showsClock: Logic.showsBlock(lockItems, "clock")
    readonly property bool showsDate: Logic.showsBlock(lockItems, "date")
    readonly property bool showsKeyboard: Logic.showsBlock(lockItems, "keyboard")
    readonly property bool dateAboveClock: Logic.dateAboveClock(lockItems)
    // Test mode has no daemon: "fail" or "success" simulates the answer to a
    // login and shows all power buttons; previewMenu opens a chooser.
    readonly property string previewLogin: Logic.configString(setting("previewLogin"), "")
    readonly property bool preview: previewLogin === "fail" || previewLogin === "success"

    readonly property bool primary: typeof primaryScreen === "undefined" || primaryScreen === true

    property int userIndex: Logic.clampIndex(userModel.lastIndex, userModel.count)
    property int sessionIndex: Logic.clampIndex(sessionModel.lastIndex, sessionModel.count)
    property var users: []
    property var sessions: []
    readonly property var user: userIndex >= 0 && userIndex < users.length ? users[userIndex] : null
    readonly property string userName: user ? user.name : Logic.configString(userModel.lastUser, "")

    property bool busy: false
    property bool leaving: false
    property string status: ""
    property bool statusIsError: false
    property string menu: ""
    property string confirmAction: ""
    // null until a typed letter tells (Logic.capsGuess).
    property var capsGuess: null
    readonly property bool capsLock: (typeof keyboard !== "undefined" && keyboard.capsLock) || capsGuess === true
    // Typing moves the login block to the middle; it returns after a while
    // without input while the field is empty.
    property bool engaged: false
    // 0 → 1 while the screen appears, back to 0 after a successful login.
    property real fade: 0
    readonly property real topIn: Logic.stagger(fade, 1, 3, S.staggerMs, S.enter, leaving)
    readonly property real bottomIn: Logic.stagger(fade, 2, 3, S.staggerMs, S.enter, leaving)
    readonly property real cornersIn: Logic.stagger(fade, 3, 3, S.staggerMs, S.enter, leaving)
    readonly property real travel: S.spaceXl * 2

    Behavior on fade {
        NumberAnimation {
            duration: root.leaving ? S.exit : S.enter
            easing.type: root.leaving ? Easing.InCubic : Easing.OutCubic
        }
    }
    Component.onCompleted: {
        fade = 1
        if (primary) password.focusInput()
        if (preview) menu = Logic.configString(setting("previewMenu"), "")
    }

    function engage() {
        engaged = true
        idleTimer.restart()
    }

    function login() {
        if (busy || leaving || !userName.length) return
        if (!password.text.length && (!user || user.needsPassword)) return
        menu = ""
        busy = true
        status = ""
        statusIsError = false
        engage()
        if (preview) previewTimer.restart()
        else sddm.login(userName, password.text, sessionIndex)
    }

    function failed() {
        busy = false
        password.clear()
        // No words for a rejected password: the shake is the answer, the same
        // way the lock screen answers.
        statusIsError = false
        status = ""
        password.shake()
        password.focusInput()
    }

    function succeeded() {
        busy = false
        leaving = true
        fade = 0
    }

    function chooseUser(index) {
        menu = ""
        if (index !== userIndex) {
            userIndex = index
            password.clear()
            status = ""
            statusIsError = false
        }
        password.focusInput()
    }

    function chooseSession(index) {
        menu = ""
        sessionIndex = index
        password.focusInput()
    }

    function power(action) {
        if (confirmAction !== action || preview) {
            confirmAction = action
            confirmTimer.restart()
            return
        }
        confirmAction = ""
        if (action === "suspend") sddm.suspend()
        else if (action === "reboot") sddm.reboot()
        else if (action === "poweroff") sddm.powerOff()
    }

    Connections {
        target: sddm
        function onLoginFailed() { root.failed() }
        function onLoginSucceeded() { root.succeeded() }
        function onInformationMessage(message) {
            root.status = message
            root.statusIsError = false
        }
    }

    // Model rows as plain objects for bindings (the models have no row getter).
    Instantiator {
        model: userModel
        delegate: QtObject {
            readonly property string name: model.name || ""
            readonly property string realName: model.realName || ""
            readonly property string icon: model.icon || ""
            readonly property bool needsPassword: model.needsPassword !== false
        }
        onObjectAdded: (index, object) => root.users = Array.from({ length: count }, (_, i) => objectAt(i)).filter(item => item)
        onObjectRemoved: (index, object) => root.users = Array.from({ length: count }, (_, i) => objectAt(i)).filter(item => item && item !== object)
    }
    Instantiator {
        model: sessionModel
        delegate: QtObject {
            readonly property string label: Logic.sessionLabel(model.name, model.file)
        }
        onObjectAdded: (index, object) => root.sessions = Array.from({ length: count }, (_, i) => objectAt(i)).filter(item => item)
        onObjectRemoved: (index, object) => root.sessions = Array.from({ length: count }, (_, i) => objectAt(i)).filter(item => item && item !== object)
    }

    Timer { id: previewTimer; interval: 900; onTriggered: root.previewLogin === "success" ? root.succeeded() : root.failed() }
    Timer { id: confirmTimer; interval: S.confirmReset; onTriggered: root.confirmAction = "" }
    Timer {
        id: idleTimer
        interval: S.idleReturn
        onTriggered: {
            if (password.text.length || root.busy || root.menu.length) restart()
            else root.engaged = false
        }
    }
    Timer {
        id: tick
        property date now: new Date()
        interval: 1000
        running: true
        repeat: true
        onTriggered: now = new Date()
    }

    // Background: the wallpaper decoded tiny, scaled up and blurred, slightly
    // darker and more saturated (the lock screen does the same with a capture).
    Image {
        id: wallpaper
        anchors.fill: parent
        visible: false
        asynchronous: true
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: root.blur ? S.backdropWidth : root.width
        source: root.background
        onStatusChanged: if (status === Image.Error && !source.toString().endsWith("assets/background.svg")) source = "assets/background.svg"
    }
    MultiEffect {
        anchors.fill: parent
        source: wallpaper
        visible: wallpaper.status === Image.Ready
        opacity: Math.min(1, root.fade * 1.6)
        scale: 1 + S.zoom * (1 - root.fade)
        autoPaddingEnabled: false
        blurEnabled: root.blur
        blur: 1
        blurMax: S.blurMax
        saturation: S.saturation
        brightness: S.brightness
    }
    Rectangle { anchors.fill: parent; color: S.shade }

    // Closes an open menu when clicking elsewhere.
    MouseArea {
        anchors.fill: parent
        enabled: root.menu.length > 0
        onClicked: {
            root.menu = ""
            password.focusInput()
        }
    }

    // Date and clock. A one-column GridLayout rather than a ColumnLayout,
    // because the lock screen's arrangement may put the date under the clock
    // and only a grid lets a child say which row it is in.
    GridLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: S.clockTop
        columns: 1
        rowSpacing: 0
        columnSpacing: 0
        opacity: root.topIn
        transform: Translate { y: -root.travel * (1 - root.topIn) }

        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.row: root.dateAboveClock ? 0 : 1
            visible: root.showsDate
            text: Qt.locale().toString(tick.now, root.dateFormat)
            color: S.text
            font.family: root.fontFamily
            font.pixelSize: S.dateSize
            font.weight: Font.DemiBold
            renderType: Text.QtRendering
            layer.enabled: true
            layer.effect: MultiEffect { shadowEnabled: true; shadowColor: S.base; shadowOpacity: S.clockShadow; shadowBlur: 0.5; shadowVerticalOffset: S.shadowOffset / 3 }
        }
        Clock {
            Layout.alignment: Qt.AlignHCenter
            Layout.row: root.dateAboveClock ? 1 : 0
            visible: root.showsClock
            time: tick.now
            fontFamily: root.fontFamily
        }
    }

    // Keyboard layout (click switches) and Caps Lock, top right.
    RowLayout {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: S.spaceXl
        visible: root.primary && root.showsKeyboard && layoutText.text.length > 0
        opacity: root.topIn
        spacing: S.spaceSm
        Icon { name: "keyboard"; size: S.iconMd; opacity: S.mutedOpacity + (1 - S.mutedOpacity) * (layoutArea.containsMouse ? 1 : 0) }
        Text {
            id: layoutText
            text: typeof keyboard === "undefined" ? "" : Logic.layoutLabel(keyboard.layouts, keyboard.currentLayout)
            color: S.text
            font.family: root.fontFamily
            font.pixelSize: S.bodySize
            font.weight: Font.Medium
            renderType: Text.QtRendering
            MouseArea {
                id: layoutArea
                anchors.fill: parent
                anchors.margins: -S.spaceSm
                hoverEnabled: true
                enabled: keyboard.layouts.length > 1
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: keyboard.currentLayout = Logic.nextIndex(keyboard.currentLayout, keyboard.layouts.length)
            }
        }
    }

    // Avatar, name, password and status.
    ColumnLayout {
        id: loginBlock
        visible: root.primary
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        // Glides to the middle of the screen while typing.
        anchors.bottomMargin: root.engaged ? (parent.height - implicitHeight) / 2 : S.bottomMargin
        Behavior on anchors.bottomMargin {
            NumberAnimation { duration: S.enter; easing.type: Easing.OutBack; easing.overshoot: 0.8 }
        }
        scale: root.engaged ? S.engagedScale : 1
        Behavior on scale { NumberAnimation { duration: S.enter; easing.type: Easing.OutCubic } }
        spacing: S.spaceMd
        opacity: root.bottomIn
        transform: Translate { y: root.travel * (1 - root.bottomIn) }

        Avatar {
            id: avatar
            Layout.alignment: Qt.AlignHCenter
            icon: root.user ? root.user.icon : ""
            name: root.user ? Logic.displayName(root.user.realName, root.user.name) : root.userName
            accent: root.accent
            fontFamily: root.fontFamily
            // Gentle pulse while SDDM checks the password.
            SequentialAnimation on scale {
                running: root.busy
                loops: Animation.Infinite
                NumberAnimation { to: 1.05; duration: S.pulse / 2; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: S.pulse / 2; easing.type: Easing.InOutSine }
                onRunningChanged: if (!running) avatar.scale = 1
            }
            layer.enabled: true
            layer.effect: MultiEffect { shadowEnabled: true; shadowColor: S.base; shadowOpacity: S.clockShadow; shadowBlur: 0.8; shadowVerticalOffset: S.shadowOffset / 2 }
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: avatar.name
            color: S.text
            font.family: root.fontFamily
            font.pixelSize: S.nameSize
            font.weight: Font.DemiBold
            renderType: Text.QtRendering
        }
        PasswordPill {
            id: password
            Layout.alignment: Qt.AlignHCenter
            fontFamily: root.fontFamily
            busy: root.busy
            needsPassword: !root.user || root.user.needsPassword
            onSubmitted: root.login()
            onKeyPressed: (text, shift, capsKey) => root.capsGuess = Logic.capsGuess(root.capsGuess, text, shift, capsKey)
            onEdited: {
                root.engage()
                if (root.statusIsError) {
                    root.status = ""
                    root.statusIsError = false
                }
            }
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: S.statusWidth
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: Logic.statusText(root.status, root.capsLock) || " "
            color: root.statusIsError ? S.error : S.muted
            font.family: root.fontFamily
            font.pixelSize: S.smallSize
            renderType: Text.QtRendering
        }
    }

    // User and session choosers, bottom left.
    RowLayout {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: S.spaceXl
        anchors.bottomMargin: S.spaceXl + S.captionSize + S.spaceXs
        visible: root.primary
        opacity: root.cornersIn
        spacing: S.spaceSm

        MenuPill {
            visible: root.users.length > 1
            icon: "users"
            label: "Switch User"
            showFaces: true
            fontFamily: root.fontFamily
            accent: root.accent
            entries: root.users.map(item => ({ label: Logic.displayName(item.realName, item.name), detail: item.realName.length ? item.name : "", face: item.icon }))
            currentIndex: root.userIndex
            open: root.menu === "users"
            onToggled: root.menu = open ? "" : "users"
            onChosen: index => root.chooseUser(index)
        }
        MenuPill {
            visible: root.sessions.length > 0
            icon: "session"
            label: root.sessionIndex >= 0 && root.sessionIndex < root.sessions.length ? root.sessions[root.sessionIndex].label : "Session"
            fontFamily: root.fontFamily
            accent: root.accent
            entries: root.sessions.map(item => ({ label: item.label }))
            currentIndex: root.sessionIndex
            open: root.menu === "sessions"
            onToggled: root.menu = open ? "" : "sessions"
            onChosen: index => root.chooseSession(index)
        }
    }

    // Power buttons, bottom right.
    RowLayout {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: S.spaceXl
        visible: root.primary
        opacity: root.cornersIn
        spacing: S.spaceLg
        Repeater {
            model: [
                { id: "suspend", icon: "sleep", label: "Sleep", available: root.preview || sddm.canSuspend },
                { id: "reboot", icon: "restart", label: "Restart", available: root.preview || sddm.canReboot },
                { id: "poweroff", icon: "power", label: "Shut down", available: root.preview || sddm.canPowerOff }
            ]
            PowerButton {
                required property var modelData
                visible: modelData.available
                icon: modelData.icon
                label: modelData.label
                confirming: root.confirmAction === modelData.id
                fontFamily: root.fontFamily
                accent: root.accent
                onClicked: root.power(modelData.id)
            }
        }
    }
}
