import QtQuick

// Panacea kit - a level in dots (Nothing): n dots, the first `lit` white, the rest faint;
// red when `low`.
Row {
    id: db
    property var sys
    readonly property var t: sys.pk
    property int n: 10
    property real level: 0.5          // 0..1
    property real d: 6
    property bool low: false
    spacing: d * 0.6
    Repeater {
        model: db.n
        Rectangle { required property int index; width: db.d; height: db.d; radius: db.d / 2
                    color: index < Math.round(db.level * db.n) ? (db.low ? db.t.accent : db.t.fg) : db.t.dotOff }
    }
}
