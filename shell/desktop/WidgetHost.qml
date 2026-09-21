import Quickshell
import QtQuick
import qs.services

// Creates the desktop widget surfaces for every screen and placement.
Variants {
    model: Quickshell.screens

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
