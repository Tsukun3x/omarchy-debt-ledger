import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Panel {
  id: root
  moduleName: "bruce.debt-ledger"
  readonly property var panelScreen: anchorItem && anchorItem.QsWindow.window
    ? anchorItem.QsWindow.window.screen : null
  readonly property var mainScreen: {
    var best = null
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) {
      if (!best || screens[i].width * screens[i].height > best.width * best.height)
        best = screens[i]
    }
    return best
  }
  ipcTarget: panelScreen && panelScreen === mainScreen ? moduleName : ""

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME")
    || ((Quickshell.env("HOME") || "") + "/.local/state")
  readonly property string ledgerPath: stateHome + "/omarchy/debt-ledger.json"

  property var debts: []
  property string snowballTargetId: ""
  property bool dataLoaded: false
  property string dataError: ""
  property bool formOpen: false
  property string editingId: ""
  property string pendingDeleteId: ""
  property string draftName: ""
  property string draftDay: ""
  property string draftBalance: ""
  property string draftPayment: ""
  property string draftAdjustment: "0"
  property string draftPromoMonths: ""
  property bool draftPaid: false
  property string formError: ""

  readonly property color foreground: Commons.Color.popups.text
  readonly property color muted: Qt.alpha(foreground, 0.58)
  readonly property string fontFamily: "monospace"
  readonly property real totalBalance: {
    var total = 0
    for (var i = 0; i < debts.length; i++)
      if (debts[i].paid !== true) total += Number(debts[i].balance)
    return total
  }
  readonly property real snowballTotal: {
    var total = 0
    for (var i = 0; i < debts.length; i++)
      if (debts[i].paid === true) total += Number(debts[i].payment)
    return total
  }
  readonly property real allocatedSnowball: {
    for (var i = 0; i < debts.length; i++)
      if (debts[i].id === snowballTargetId && debts[i].paid !== true) return snowballTotal
    return 0
  }
  readonly property real totalMonthly: {
    var total = 0
    for (var i = 0; i < debts.length; i++)
      if (debts[i].paid !== true) total += Number(debts[i].payment)
    return total + allocatedSnowball
  }

  function money(amount) {
    var value = Qt.locale().toString(Number(amount) || 0, "f", 2)
    return Qt.locale().currencySymbol() + value
  }

  function payoffPayments(debt) {
    var balance = Number(debt.balance)
    var payment = Number(debt.payment) + snowballFor(debt)
    var extra = Number(debt.adjustment) || 0
    if (debt.paid === true) return 0
    if (balance <= 0) return 0
    if (payment <= 0) return -1
    return 1 + Math.ceil(Math.max(0, balance - payment - extra) / payment)
  }

  function snowballFor(debt) {
    return debt && debt.paid !== true && debt.id === snowballTargetId ? snowballTotal : 0
  }

  function payoffLabel(debt) {
    var payments = payoffPayments(debt)
    if (payments === 0) return "PAID OFF"
    if (payments < 0) return "PAYMENT NEEDED"
    var years = Math.floor(payments / 12)
    var months = payments % 12
    var parts = []
    if (years > 0) parts.push(years + (years === 1 ? " yr" : " yrs"))
    if (months > 0) parts.push(months + (months === 1 ? " mo" : " mos"))
    return parts.join(" ") + " est."
  }

  function loadLedger(raw) {
    if (!raw || raw.trim().length === 0) {
      debts = []
      snowballTargetId = ""
      dataLoaded = true
      dataError = ""
      return
    }

    try {
      var doc = JSON.parse(raw)
      if (!doc || doc.version !== 1 || !Array.isArray(doc.debts))
        throw new Error("Unsupported ledger format")
      var loadedDebts = []
      for (var i = 0; i < doc.debts.length; i++) {
        var debt = doc.debts[i]
        if (!debt || typeof debt.id !== "string" || typeof debt.name !== "string"
            || !Number.isInteger(Number(debt.day)) || Number(debt.day) < 1 || Number(debt.day) > 31
            || !isFinite(Number(debt.balance)) || Number(debt.balance) < 0
            || !isFinite(Number(debt.payment)) || Number(debt.payment) <= 0
            || !isFinite(Number(debt.adjustment)) || Number(debt.adjustment) < 0
            || !Number.isInteger(Number(debt.promoMonths)) || Number(debt.promoMonths) < 0
            || (debt.paid !== undefined && typeof debt.paid !== "boolean"))
          throw new Error("Invalid debt entry")
        loadedDebts.push({
          id: debt.id,
          name: debt.name,
          day: Number(debt.day),
          balance: Number(debt.balance),
          payment: Number(debt.payment),
          adjustment: Number(debt.adjustment),
          promoMonths: Number(debt.promoMonths),
          paid: debt.paid === true
        })
      }
      debts = loadedDebts
      snowballTargetId = typeof doc.snowballTargetId === "string" ? doc.snowballTargetId : ""
      if (!hasActiveDebt(snowballTargetId)) snowballTargetId = ""
      dataLoaded = true
      dataError = ""
    } catch (error) {
      debts = []
      snowballTargetId = ""
      dataLoaded = true
      dataError = "Ledger data could not be read: " + error.message
    }
  }

  function hasActiveDebt(id) {
    for (var i = 0; i < debts.length; i++)
      if (debts[i].id === id && debts[i].paid !== true) return true
    return false
  }

  function saveLedger() {
    if (!dataLoaded || dataError) {
      formError = dataError || "Ledger is still loading."
      return
    }
    ledgerFile.setText(JSON.stringify({
      version: 1,
      snowballTargetId: snowballTargetId,
      debts: debts
    }, null, 2) + "\n")
  }

  function clearDraft() {
    editingId = ""
    draftName = ""
    draftDay = ""
    draftBalance = ""
    draftPayment = ""
    draftAdjustment = "0"
    draftPromoMonths = ""
    draftPaid = false
    formError = ""
  }

  function focusDebtField(index) {
    var fields = [nameField, dayField, balanceField, paymentField, adjustmentField, promoField]
    var wrapped = ((index % fields.length) + fields.length) % fields.length
    fields[wrapped].focusEditor()
  }

  function beginNew() {
    if (!dataLoaded || dataError) return
    clearDraft()
    formOpen = true
    Qt.callLater(function() { nameField.focusEditor() })
  }

  function beginEdit(debt) {
    if (!dataLoaded || dataError) return
    pendingDeleteId = ""
    editingId = debt.id
    draftName = debt.name
    draftDay = String(debt.day)
    draftBalance = String(debt.balance)
    draftPayment = String(debt.payment)
    draftAdjustment = String(debt.adjustment)
    draftPromoMonths = debt.promoMonths > 0 ? String(debt.promoMonths) : ""
    draftPaid = debt.paid === true
    formError = ""
    formOpen = true
    Qt.callLater(function() { nameField.focusEditor() })
  }

  function saveDraft() {
    var name = draftName.trim()
    var day = Number(draftDay)
    var balance = Number(draftBalance)
    var payment = Number(draftPayment)
    var adjustment = draftAdjustment.trim() === "" ? 0 : Number(draftAdjustment)
    var promoMonths = draftPromoMonths.trim() === "" ? 0 : Number(draftPromoMonths)

    if (!name) { formError = "Enter a name for this debt."; return }
    if (!Number.isInteger(day) || day < 1 || day > 31) {
      formError = "Payment day must be a whole number from 1 to 31."; return
    }
    if (!isFinite(balance) || balance < 0) {
      formError = "Balance must be a non-negative amount."; return
    }
    if (!isFinite(payment) || payment <= 0) {
      formError = "Monthly payment must be greater than zero."; return
    }
    if (!isFinite(adjustment) || adjustment < 0) {
      formError = "One-time extra must be a non-negative amount."; return
    }
    if (!Number.isInteger(promoMonths) || promoMonths < 0) {
      formError = "Promo time must be a whole number of months, or blank."; return
    }

    var entry = {
      id: editingId || (Date.now().toString() + "-" + Math.floor(Math.random() * 1000000)),
      name: name,
      day: day,
      balance: Math.round(balance * 100) / 100,
      payment: Math.round(payment * 100) / 100,
      adjustment: Math.round(adjustment * 100) / 100,
      promoMonths: promoMonths,
      paid: draftPaid
    }
    var next = debts.slice()
    var replaced = false
    for (var i = 0; i < next.length; i++) {
      if (next[i].id === editingId) {
        next[i] = entry
        replaced = true
        break
      }
    }
    if (!replaced) next.push(entry)
    debts = next
    if (entry.paid && entry.id === snowballTargetId) snowballTargetId = ""
    saveLedger()
    formOpen = false
    clearDraft()
  }

  function removeDebt(id) {
    var next = []
    for (var i = 0; i < debts.length; i++)
      if (debts[i].id !== id) next.push(debts[i])
    debts = next
    if (snowballTargetId === id) snowballTargetId = ""
    pendingDeleteId = ""
    saveLedger()
  }

  function setPaid(id, paid) {
    var next = debts.slice()
    for (var i = 0; i < next.length; i++) {
      if (next[i].id !== id) continue
      next[i] = {
        id: next[i].id,
        name: next[i].name,
        day: next[i].day,
        balance: next[i].balance,
        payment: next[i].payment,
        adjustment: next[i].adjustment,
        promoMonths: next[i].promoMonths,
        paid: paid
      }
      break
    }
    debts = next
    if (paid && snowballTargetId === id) snowballTargetId = ""
    saveLedger()
  }

  function selectSnowballTarget(id) {
    if (!hasActiveDebt(id)) return
    snowballTargetId = id
    saveLedger()
  }

  function clearSnowballTarget() {
    snowballTargetId = ""
    saveLedger()
  }

  function open() {
    ledgerFile.reload()
    root.controller.show()
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    formOpen = false
    pendingDeleteId = ""
    clearDraft()
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
  }

  FileView {
    id: ledgerFile
    path: root.ledgerPath
    watchChanges: true
    printErrors: false
    onLoaded: root.loadLedger(text())
    onLoadFailed: function(error) {
      if (error === FileViewError.FileNotFound) {
        root.loadLedger("")
        return
      }
      root.debts = []
      root.dataLoaded = true
      root.dataError = "Could not read the local ledger. Data was not changed."
    }
    onFileChanged: reload()
  }

  KeyboardPanel {
    id: keyboardPanel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    padding: Style.space(14)
    contentWidth: keyboardPanel.fittedContentWidth(Style.space(720))
    contentHeight: keyboardPanel.fittedContentHeight(contentColumn.implicitHeight, Style.space(720))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: nameField.activeEditor === true || dayField.activeEditor === true
        || balanceField.activeEditor === true || paymentField.activeEditor === true
        || adjustmentField.activeEditor === true || promoField.activeEditor === true
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: contentColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        Row {
          width: parent.width
          spacing: Style.space(12)

          Column {
            width: parent.width - addButton.implicitWidth - parent.spacing
            spacing: Style.space(3)

            Text {
              text: "DEBT_LEDGER"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              renderType: Text.NativeRendering
            }
            Text {
              text: root.dataLoaded
                ? (root.dataError ? "READ ERROR" : "LOCAL ONLY | 0% INTEREST ESTIMATES")
                : "LOADING LOCAL LEDGER..."
              color: root.dataError ? Color.urgent : root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              renderType: Text.NativeRendering
            }
          }

          Text {
            id: addButton
            text: root.formOpen ? "[ CANCEL ]" : "[ + ADD DEBT ]"
            color: Color.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            verticalAlignment: Text.AlignVCenter
            renderType: Text.NativeRendering
            MouseArea {
              anchors.fill: parent
              onClicked: {
                if (root.formOpen) {
                  root.formOpen = false
                  root.clearDraft()
                } else {
                  root.beginNew()
                }
              }
            }
          }
        }

        Rectangle {
          width: parent.width
          height: Style.space(1)
          color: Color.popups.border
        }

        Row {
          width: parent.width
          spacing: Style.space(26)

          Column {
            spacing: Style.space(2)
            Text {
              text: "TOTAL BALANCE"
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              renderType: Text.NativeRendering
            }
            Text {
              text: root.money(root.totalBalance)
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              renderType: Text.NativeRendering
            }
          }
          Column {
            spacing: Style.space(2)
            Text {
              text: "ACTIVE MONTHLY PLAN"
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              renderType: Text.NativeRendering
            }
            Text {
              text: root.money(root.totalMonthly)
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              renderType: Text.NativeRendering
            }
          }
          Column {
            spacing: Style.space(2)
            Text {
              text: "SNOWBALL AVAILABLE"
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              renderType: Text.NativeRendering
            }
            Text {
              text: root.money(root.snowballTotal)
              color: Color.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              renderType: Text.NativeRendering
            }
          }
          Text {
            visible: root.snowballTargetId !== ""
            text: "[ CLEAR ALLOCATION ]"
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            MouseArea {
              anchors.fill: parent
              onClicked: root.clearSnowballTarget()
            }
          }
        }

        Rectangle {
          visible: root.dataError.length > 0
          width: parent.width
          height: visible ? errorText.implicitHeight + Style.space(14) : 0
          color: Qt.alpha(Color.urgent, 0.1)
          border.width: 1
          border.color: Color.urgent
          Text {
            id: errorText
            anchors.fill: parent
            anchors.margins: Style.space(7)
            text: root.dataError
            color: Color.urgent
            wrapMode: Text.Wrap
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            renderType: Text.NativeRendering
          }
        }

        Rectangle {
          visible: root.formOpen
          width: parent.width
          height: visible ? formColumn.implicitHeight + Style.space(16) : 0
          color: Qt.alpha(Color.popups.text, 0.025)
          border.width: 1
          border.color: Color.popups.border

          Column {
            id: formColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(8)
            spacing: Style.space(8)

            Field {
              id: nameField
              width: parent.width
              label: "DEBT / PAYMENT NAME"
              value: root.draftName
              placeholder: "e.g. Card or loan"
              onEdited: function(text) { root.draftName = text }
              onTabRequested: function(direction) { root.focusDebtField(direction > 0 ? 1 : 5) }
            }

            Grid {
              id: fieldsGrid
              width: parent.width
              columns: 3
              spacing: Style.space(8)

              Field {
                id: dayField
                width: (fieldsGrid.width - fieldsGrid.spacing * 2) / 3
                label: "DUE DAY (1-31)"
                value: root.draftDay
                placeholder: "15"
                onEdited: function(text) { root.draftDay = text }
                onTabRequested: function(direction) { root.focusDebtField(direction > 0 ? 2 : 0) }
              }
              Field {
                id: balanceField
                width: (fieldsGrid.width - fieldsGrid.spacing * 2) / 3
                label: "BALANCE"
                value: root.draftBalance
                placeholder: "0.00"
                onEdited: function(text) { root.draftBalance = text }
                onTabRequested: function(direction) { root.focusDebtField(direction > 0 ? 3 : 1) }
              }
              Field {
                id: paymentField
                width: (fieldsGrid.width - fieldsGrid.spacing * 2) / 3
                label: "MONTHLY PAYMENT"
                value: root.draftPayment
                placeholder: "0.00"
                onEdited: function(text) { root.draftPayment = text }
                onTabRequested: function(direction) { root.focusDebtField(direction > 0 ? 4 : 2) }
              }
              Field {
                id: adjustmentField
                width: (fieldsGrid.width - fieldsGrid.spacing * 2) / 3
                label: "ONE-TIME EXTRA (NEXT DUE)"
                value: root.draftAdjustment
                placeholder: "0.00"
                onEdited: function(text) { root.draftAdjustment = text }
                onTabRequested: function(direction) { root.focusDebtField(direction > 0 ? 5 : 3) }
              }
              Field {
                id: promoField
                width: (fieldsGrid.width - fieldsGrid.spacing * 2) / 3
                label: "PROMO MONTHS LEFT"
                value: root.draftPromoMonths
                placeholder: "optional"
                onEdited: function(text) { root.draftPromoMonths = text }
                onTabRequested: function(direction) { root.focusDebtField(direction > 0 ? 0 : 4) }
              }
            }

            Text {
              text: "Applied once with the next scheduled payment. Use a decimal point."
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              renderType: Text.NativeRendering
            }

            Text {
              visible: root.formError.length > 0
              text: root.formError
              color: Color.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              renderType: Text.NativeRendering
            }

            Text {
              text: root.editingId ? "[ SAVE CHANGES ]" : "[ SAVE ENTRY ]"
              color: Color.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              renderType: Text.NativeRendering
              MouseArea {
                anchors.fill: parent
                onClicked: root.saveDraft()
              }
            }
          }
        }

        Flickable {
          id: debtScroller
          width: parent.width
          height: Style.space(300)
          contentWidth: width
          contentHeight: debtList.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: debtList
            width: debtScroller.width
            spacing: Style.space(7)

            Repeater {
              model: root.debts

              delegate: Rectangle {
                required property var modelData
                required property int index
                width: debtList.width
                height: Style.space(92)
                color: index % 2 === 0
                  ? Qt.alpha(Color.popups.text, 0.025)
                  : "transparent"
                border.width: 1
                border.color: Color.popups.border

                Column {
                  id: rowToggles
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(8)
                  width: Style.space(72)
                  spacing: Style.space(8)

                  Item {
                    width: Style.space(72)
                    height: Style.space(16)
                    Row {
                      anchors.fill: parent
                      spacing: Style.space(5)
                      opacity: modelData.paid === true ? 0.35 : 1
                      Rectangle {
                        width: Style.space(14)
                        height: width
                        radius: width / 2
                        color: "transparent"
                        border.width: 1
                        border.color: root.snowballTargetId === modelData.id ? Color.accent : root.muted
                        anchors.verticalCenter: parent.verticalCenter
                        Rectangle {
                          anchors.centerIn: parent
                          width: Style.space(6)
                          height: width
                          radius: width / 2
                          color: Color.accent
                          visible: root.snowballTargetId === modelData.id
                        }
                      }
                      Text {
                        text: "SNOW"
                        color: root.snowballTargetId === modelData.id ? Color.accent : root.muted
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        renderType: Text.NativeRendering
                      }
                    }
                    MouseArea {
                      anchors.fill: parent
                      enabled: modelData.paid !== true
                      onClicked: root.selectSnowballTarget(modelData.id)
                    }
                  }

                  Item {
                    width: Style.space(72)
                    height: Style.space(16)
                    Row {
                      anchors.fill: parent
                      spacing: Style.space(5)
                      Rectangle {
                        width: Style.space(14)
                        height: width
                        radius: 0
                        color: "transparent"
                        border.width: 1
                        border.color: modelData.paid === true ? Color.accent : root.muted
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                          anchors.centerIn: parent
                          text: "x"
                          visible: modelData.paid === true
                          color: Color.accent
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.bodySmall
                          renderType: Text.NativeRendering
                        }
                      }
                      Text {
                        text: "PAID"
                        color: modelData.paid === true ? Color.accent : root.muted
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        renderType: Text.NativeRendering
                      }
                    }
                    MouseArea {
                      anchors.fill: parent
                      onClicked: root.setPaid(modelData.id, modelData.paid !== true)
                    }
                  }
                }

                Column {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(80)
                  anchors.right: actions.left
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  anchors.margins: Style.space(8)
                  spacing: Style.space(3)

                  Row {
                    width: parent.width
                    spacing: Style.space(10)
                    Text {
                      text: modelData.name + (modelData.paid === true ? " [PAID]" : "")
                      color: modelData.paid === true ? root.muted : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                      elide: Text.ElideRight
                      renderType: Text.NativeRendering
                    }
                    Text {
                      text: "DUE " + modelData.day
                      color: root.muted
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      renderType: Text.NativeRendering
                    }
                  }
                  Text {
                    text: "BAL " + root.money(modelData.balance)
                      + "   PAY " + root.money(Number(modelData.payment) + root.snowballFor(modelData))
                      + (root.snowballFor(modelData) > 0
                        ? " = " + root.money(modelData.payment) + " + " + root.money(root.snowballFor(modelData))
                        : "")
                      + (Number(modelData.adjustment) > 0
                        ? "   EXTRA " + root.money(modelData.adjustment) : "")
                    color: root.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    renderType: Text.NativeRendering
                  }
                  Text {
                    text: "PAYOFF " + (modelData.paid === true ? "PAID OFF" : root.payoffLabel(modelData))
                      + "   PROMO " + (Number(modelData.promoMonths) > 0
                        ? modelData.promoMonths + " mo left" : "none")
                    color: Color.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    renderType: Text.NativeRendering
                  }
                }

                Column {
                  id: actions
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  anchors.rightMargin: Style.space(8)
                  anchors.topMargin: Style.space(7)
                  anchors.bottomMargin: Style.space(7)
                  width: Style.space(76)
                  spacing: Style.space(3)
                  Text {
                    text: root.pendingDeleteId === modelData.id ? "[ REMOVE ]" : "[ EDIT ]"
                    color: root.pendingDeleteId === modelData.id ? Color.urgent : Color.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    renderType: Text.NativeRendering
                    MouseArea {
                      anchors.fill: parent
                      onClicked: {
                        if (root.pendingDeleteId === modelData.id)
                          root.removeDebt(modelData.id)
                        else
                          root.beginEdit(modelData)
                      }
                    }
                  }
                  Text {
                    visible: root.pendingDeleteId === modelData.id
                    text: "[ KEEP ]"
                    color: root.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    renderType: Text.NativeRendering
                    MouseArea {
                      anchors.fill: parent
                      onClicked: root.pendingDeleteId = ""
                    }
                  }
                  Text {
                    visible: root.pendingDeleteId !== modelData.id
                    text: "[ DELETE ]"
                    color: root.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    renderType: Text.NativeRendering
                    MouseArea {
                      anchors.fill: parent
                      onClicked: root.pendingDeleteId = modelData.id
                    }
                  }
                }
              }
            }

            Text {
              visible: root.dataLoaded && !root.dataError && root.debts.length === 0
              width: debtList.width
              height: Style.space(90)
              text: "NO DEBTS RECORDED\nSelect + ADD DEBT to create your first entry."
              color: root.muted
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              lineHeight: 1.5
              renderType: Text.NativeRendering
            }
          }
        }

        Text {
          width: parent.width
          text: "Mark a debt paid to add its manual monthly payment to the snowball. Select one unpaid debt to allocate it; its shown payment and payoff estimate update. Estimates assume 0% interest."
          color: root.muted
          wrapMode: Text.Wrap
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          renderType: Text.NativeRendering
        }

        Text {
          width: parent.width
          text: "Saved locally | " + root.ledgerPath
          color: Qt.alpha(root.muted, 0.75)
          elide: Text.ElideMiddle
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          renderType: Text.NativeRendering
        }
      }
    }
  }

}
