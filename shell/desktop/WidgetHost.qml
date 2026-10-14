import Quickshell
import QtQuick
import qs.services

// Creates the desktop widget surfaces for every screen and placement - only
// while widgets are shown at all; hidden ones were built and kept anyway.
Variants {
    model: LayoutService.widgetsShown ? Quickshell.screens : []

    Scope {
        id: screenScope
        required property var modelData

        Variants {
            model: LayoutService.placementIds(screenScope.modelData.name, false)
            WidgetPlacement {
                required property string modelData
                screenModel: screenScope.modelData
                placementId: modelData
            }
        }
    }
}
