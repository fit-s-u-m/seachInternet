import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    pluginId: "dankDuckDuckGoSearch"

    StringSetting {
        settingKey: "trigger"
        label: "Trigger"
        description: "Prefix that activates DuckDuckGo search in the launcher (include a trailing space if you want one)."
        placeholder: "ddg "
        defaultValue: "ddg "
    }
}
