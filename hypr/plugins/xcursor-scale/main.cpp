// xcursor-scale: X11 pointers at the right size while X11 is sharp.
//
// With `xwayland:force_zero_scaling` the X server draws in real pixels, but
// the cursor surfaces XWayland hands to Hyprland still say buffer scale 1, so
// Hyprland multiplies every X11 pointer by the monitor's scale: a Windows
// pointer forwarded by Citrix came out 1.5 times too big on a 1.5 screen, and
// every theme pointer an X11 application drew at Xcursor.size (already the
// scaled size, scripts/apply-cursor-env.sh) did too. Hyprland 0.57 still
// takes the scale from the surface alone (PointerManager.cpp: logicalSize() is
// size / scale), and no option changes that.
//
// This used to be a patch on a home-built Hyprland
// (install/patches/Hyprland/0001-xwayland-cursor-monitor-scale.patch), which
// every upgrade of the package dropped. As a plugin it is rebuilt in seconds
// against the installed headers whenever Hyprland changes
// (scripts/hypr-plugin.sh, from scripts/session-init.sh), and a build for
// another Hyprland is refused at load, which leaves the pointer big and
// nothing else.
//
// How: every path that sets the cursor image's scale - a new cursor surface,
// a commit on it, a pointer move - calls recheckEnteredOutputs() right after,
// before the image is drawn. The hook there treats an XWayland cursor surface
// as scaled by the monitor under the pointer, size and hotspot alike - what
// the patch did per monitor. The hotspot the client asked for is kept from
// setCursorSurface(), so that a second pass does not divide it again.

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/pointer/PointerManager.hpp>
#include <hyprland/src/desktop/view/WLSurface.hpp>
#include <hyprland/src/protocols/core/Compositor.hpp>
#include <hyprland/src/xwayland/XWayland.hpp>
#include <hyprland/src/xwayland/Server.hpp>
#include <hyprland/src/state/MonitorState.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/config/ConfigValue.hpp>

#include <stdexcept>
#include <string>

namespace {
    using Pointer::CPointerManager;

    HANDLE         handle        = nullptr;
    CFunctionHook* recheckHook   = nullptr;
    CFunctionHook* setSurfaceHook = nullptr;

    // The hotspot as the client set it, for the surface it was set with.
    WP<Desktop::View::CWLSurface> rawSurface;
    Vector2D                      rawHotspot;

    using RecheckFn    = void (*)(void*);
    using SetSurfaceFn = void (*)(void*, SP<Desktop::View::CWLSurface>, const Vector2D&);

    bool fromXWayland(const SP<CWLSurfaceResource>& resource) {
        return g_pXWayland && g_pXWayland->m_server && g_pXWayland->m_server->m_xwaylandClient
            && resource->client() == g_pXWayland->m_server->m_xwaylandClient;
    }

    // The scale of the monitor the pointer is on; the first enabled one when
    // it is on none (between two screens of different sizes).
    float scaleAt(const Vector2D& position) {
        PHLMONITOR fallback;
        for (const auto& monitor : State::monitorState()->monitors()) {
            if (!monitor || !monitor->m_enabled || monitor->isMirror())
                continue;
            if (!fallback)
                fallback = monitor;
            const auto& origin = monitor->m_position;
            const auto& size   = monitor->m_size;
            if (position.x >= origin.x && position.y >= origin.y && position.x < origin.x + size.x && position.y < origin.y + size.y)
                return monitor->m_scale;
        }
        return fallback ? fallback->m_scale : 1.F;
    }

    void applyScale(CPointerManager* manager) {
        // A bool in 0.57 (CBoolValue: one byte); read as an INTEGER it took in
        // whatever lay beside it.
        static auto zeroScaling = CConfigValue<Config::BOOL>("xwayland:force_zero_scaling");
        if (!*zeroScaling)
            return;
        // currentCursorImage() is the private image itself, handed out const;
        // the scale and hotspot are plain values written before every draw.
        auto&      image   = const_cast<CPointerManager::SCursorImage&>(manager->currentCursorImage());
        const auto surface = image.surface.lock();
        if (!surface || !surface->resource() || !fromXWayland(surface->resource()))
            return;
        // XWayland always says 1; anything else already is what it means.
        if (surface->resource()->m_current.scale != 1)
            return;
        const float scale = scaleAt(manager->position());
        if (scale <= 0.F)
            return;
        image.scale = scale;
        if (rawSurface.lock() == surface)
            image.hotspot = rawHotspot / scale;
    }

    void hookRecheck(void* manager) {
        applyScale(static_cast<CPointerManager*>(manager));
        reinterpret_cast<RecheckFn>(recheckHook->m_original)(manager);
    }

    void hookSetSurface(void* manager, SP<Desktop::View::CWLSurface> surface, const Vector2D& hotspot) {
        rawSurface = surface;
        rawHotspot = hotspot;
        reinterpret_cast<SetSurfaceFn>(setSurfaceHook->m_original)(manager, surface, hotspot);
    }

    CFunctionHook* hookOne(const std::string& name, const std::string& owner, void* destination) {
        for (const auto& match : HyprlandAPI::findFunctionsByName(handle, name)) {
            if (match.demangled.find(owner + "::" + name + "(") == std::string::npos)
                continue;
            auto* hook = HyprlandAPI::createFunctionHook(handle, match.address, destination);
            if (hook && hook->hook())
                return hook;
            throw std::runtime_error("xcursor-scale: could not hook " + owner + "::" + name);
        }
        throw std::runtime_error("xcursor-scale: no " + owner + "::" + name + " in this Hyprland");
    }
}

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE pluginHandle) {
    handle = pluginHandle;
    if (std::string{__hyprland_api_get_hash()} != std::string{__hyprland_api_get_client_hash()})
        throw std::runtime_error("xcursor-scale: built for another Hyprland");
    setSurfaceHook = hookOne("setCursorSurface", "CPointerManager", reinterpret_cast<void*>(&hookSetSurface));
    recheckHook    = hookOne("recheckEnteredOutputs", "CPointerManager", reinterpret_cast<void*>(&hookRecheck));
    return {"xcursor-scale", "X11 pointers at the monitor's scale while xwayland:force_zero_scaling is on", "buchhwin-shell", "1"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    // Hyprland takes the hooks back itself after this returns.
}
